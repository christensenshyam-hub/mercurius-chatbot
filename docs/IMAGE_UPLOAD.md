# Mercurius v3 — image upload (end-to-end)

**Status:** Implemented on branch `v3/image-upload`. Backend + iOS, with tests.
First feature of the v3 overhaul. Not yet shipped to TestFlight.

This is the foundational image pipeline for v3: the iOS app can pick, preview,
and upload an image; the backend validates, stores, and serves it; and the
upload returns a stable descriptor (`id` + `url`) that later v3 features
(e.g. attaching an image to a chat turn for Claude's vision API) reuse.

---

## Design decisions

| Concern | Choice | Why |
|---|---|---|
| Transport | **base64-JSON** (`POST /api/images`), not multipart | Matches the repo's existing JSON API style; **no new dependency** (no multer); mirrors how images reach Claude later (base64 content blocks) |
| Storage | `lib/imageStore.js` abstraction → **DB-backed default** (Postgres `BYTEA` / SQLite `BLOB`) | Works end-to-end on Railway with zero new infra or credentials; clean seam to swap in object storage later |
| Auth | `sessionId` (existing `SessionIdentity`) validated by the existing `validate()` Zod middleware | Same model as every other endpoint — there's no separate login; the session id *is* the bearer credential |
| Access to bytes | Opaque, unguessable `id` (~192 bits) doubles as the retrieval capability | Consistent with the app's bearer-style session model; the `url` is only ever returned to the uploader |
| Client validation | Validate type + size **client-side**, compress to JPEG, then upload | Instant feedback + smaller uploads; the server re-validates as defense-in-depth |

---

## API contract

### `POST /api/images`

Request (`application/json`, body limit 12 MB for this route only):

| Field | Type | Notes |
|---|---|---|
| `sessionId` | string | Required. `^[A-Za-z0-9_-]{1,64}$` |
| `contentType` | string | Required. One of `image/jpeg`, `image/png`, `image/webp`, `image/gif` |
| `data` | string | Required. Base64 image bytes. A `data:<mime>;base64,` prefix is tolerated and stripped |
| `fileName` | string | Optional. ≤ 255 chars |

Validation is two-layered: Zod checks the shape (`lib/schemas.js`
`ImageUploadRequest`); the handler decodes the bytes and checks **real
decoded size** + a **magic-byte sniff** (`lib/imageValidation.js`) so a client
can't smuggle a non-image or a lying `contentType` past the allowlist.

Success — **201**:
```json
{
  "id": "kQ7c…",
  "url": "/api/images/kQ7c…",
  "contentType": "image/jpeg",
  "fileName": "photo.jpg",
  "size": 84213,
  "createdAt": "2026-05-30T12:00:00.000Z"
}
```
`url` is **server-relative**; the iOS client resolves it against its API base
URL via `APIClient.imageURL(for:)`.

Errors (`{ error, message }`):

| Case | Status | `error` |
|---|---|---|
| No / empty data | 400 | `image_missing` |
| Unsupported type or bytes≠declared type | 400 | `image_invalid_type` |
| Over 8 MB decoded (or base64 over the char cap) | 413 / 400 | `image_too_large` |
| Missing / invalid session | 400 | `invalid_session` |
| Storage write failed | 500 | `storage_error` |
| Body over the 12 MB route limit | 413 | `payload_too_large` |

Rate limit: **20/min/IP** (`uploadLimiter`), under the global 60/min/IP.

### `GET /api/images/:id`

Streams the raw bytes with `Content-Type` from the stored record and
`Cache-Control: private, max-age=31536000, immutable`. The opaque `id` is the
capability. Returns **404** (`not_found`) for unknown or malformed ids.

---

## Environment variables

| Var | Default | Meaning |
|---|---|---|
| `IMAGE_STORAGE_DRIVER` | `db` | Image store backend. `db` persists bytes in the existing database. `s3` / `r2` are recognized but intentionally **not configured** — they throw until implemented, so a mis-set value fails loudly instead of dropping data |
| `DATABASE_URL` | _(unset → SQLite)_ | Already used app-wide. When set, images land in Postgres `BYTEA`; otherwise ephemeral SQLite `BLOB` (dev) |

No new secrets are required to run image upload. Swapping to object storage
later means implementing a driver in `lib/imageStore.js` that reads its
credentials from env (e.g. `S3_BUCKET` / `S3_REGION` / `S3_ACCESS_KEY_ID` /
`S3_SECRET_ACCESS_KEY`) and setting `IMAGE_STORAGE_DRIVER=s3` — **no endpoint,
schema, or client changes**.

---

## Files

**Backend**
- `db.js` — `images` table (both Postgres + SQLite branches) + `saveImage` / `getImage`.
- `lib/imageStore.js` — storage abstraction (DB driver default; S3/R2 seams).
- `lib/schemas.js` — `ImageUploadRequest` + `ALLOWED_IMAGE_TYPES` / `MAX_IMAGE_BYTES`; image error codes in `legacyErrorCode` + the `validate` reply map.
- `lib/imageValidation.js` — pure decode + size + magic-byte sniff (`decodeAndValidateImage`).
- `server.js` — `POST /api/images`, `GET /api/images/:id`, the route-scoped 12 MB JSON parser, and the `uploadLimiter`.
- Tests: `tests/images.test.js`, plus `ImageUploadRequest` cases in `tests/schemas.test.js`.

**iOS**
- `NetworkingKit`: `ImageDTO.swift` (`ImageUploadInput` / `ImageUploadResponse` / `ImageUploadLimits`), `APIClient+Images.swift` (`uploadImage`, `imageURL(for:)`), `ImageUploading.swift` (protocol).
- `ImageUploadFeature` (new SPM package): `ImagePreparing.swift` (protocol + errors), `JPEGImagePreparer.swift` (ImageIO-backed compression/normalization), `ImageUploadViewModel.swift` (state machine), `ImageUploadView.swift` (PhotosPicker + preview + states).
- `AppFeature/Sources/AppShellView.swift`: a new **Upload** tab presents the screen, wired with the shared `APIClient` + `SessionIdentity`.
- Tests: `ImageUploadFeature/Tests/*` (ViewModel state machine + preparer); `APIClientEndToEndTests.swift` (client round-trip).

The new package is registered in `Packages/Package.swift`, composed via
`AppFeature`, governed by `ArchitectureTests` (added to `featureModules`), and
the pinned `ArchitectureTests/Tests/Fixtures/manifest.json` was regenerated.

---

## iOS upload state machine

`ImageUploadViewModel` (`@MainActor @Observable`, mirrors `ChatViewModel`):

```
idle ──upload()──▶ uploading ──▶ uploaded(response)
                       └────────▶ failed(reason, isRetryable)
failed ──retry()──▶ uploading …
```

- **Duplicate uploads** are blocked two ways: `upload()` is a no-op while in
  flight, and the button is disabled via `canUpload`.
- **Compression/normalization** (`JPEGImagePreparer`) runs off the main actor
  (`Task.detached`) so the UI stays responsive; it downscales to ≤ 2048 px,
  bakes in EXIF orientation, and steps JPEG quality down to fit the size cap.
- **Errors** use `APIError.userFacingMessage` / `isRetryable`; preparation and
  session failures are non-retryable, network failures are retryable.

---

## Assumptions

- HEIC/HEIF are **not** accepted by the server — the iOS client normalizes
  every capture to JPEG first, and JPEG/PNG/WebP/GIF cover the rest (and match
  Claude's vision input formats).
- Uploads associate with a `sessionId` but retrieval is capability-based on the
  opaque `id` (not session-scoped) — adequate given the unguessable id and the
  app's existing bearer model. If image listing/ownership is needed later, the
  `images.session_id` column already supports it.
- The **Upload tab** is a deliberately simple, reversible home for this feature.
  When image-in-chat lands, the natural move is to surface upload from the chat
  composer and likely retire the standalone tab.

## TestFlight / versioning

This feature does **not** bump the build number. When cutting the v3 TestFlight
build, set the build in **`ios/project.yml`** → `CURRENT_PROJECT_VERSION`
(currently `"5"` → `"6"`), then archive via `ios/scripts/release.sh`. No
`project.yml` dependency change is required: the app target depends on
`AppFeature`, which now depends transitively on `ImageUploadFeature`.

## Follow-ups (not in this change)

- Wire an uploaded image into a chat turn (Claude vision content block).
- Object-storage driver (S3/R2) once volume warrants it.
- Optional: a TTL / cleanup job for orphaned images.
