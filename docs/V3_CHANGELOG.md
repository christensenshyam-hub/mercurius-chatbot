# Mercurius v3 — changelog

Running log of the v3 production overhaul (targeting TestFlight build 6).
Newest first.

---

## Pre-beta bug fixes — branch `v3/image-upload`

Four issues found while testing the build:

- **Quiz + Report Card did nothing.** Two `.sheet` modifiers were stacked on
  the chat header — a SwiftUI conflict where the second (tools) silently fails
  to present while the first (settings) works. Consolidated settings + quiz +
  report card into one enum-driven `.sheet(item:)`. The backend `/api/quiz` and
  `/api/report-card` endpoints were verified healthy against production.
- **Light/Dark toggle did nothing.** `MercuriusApp` pinned the app to the system
  appearance via `.preferredColorScheme(nil)`, overriding `RootView`'s correct,
  store-driven application. Removed the override; the toggle now takes effect
  immediately.
- **Chat history search.** Added a `.searchable` field to the History page that
  filters saved conversations by title + preview (case/diacritic-insensitive),
  alongside the existing mode filter. New unit tests for the predicate.
- **Mac window was phone-sized.** The build was portrait-only +
  `UIRequiresFullScreen`, which pins "iPad apps on Mac" to a fixed, phone-shaped
  window. Gave iPad/Mac all four orientations and dropped the fullscreen lock so
  the window resizes and fills; iPhone stays portrait-only.

Verified: backend 165 tests, iOS 232 tests (`swift test --parallel`), full iOS
app `xcodebuild` BUILD SUCCEEDED.

---

## Image upload (end-to-end) — branch `v3/image-upload`

First v3 feature. The app can select, preview, and upload an image; the
backend validates, stores, and serves it; the upload returns a stable
`{ id, url, … }` descriptor that later v3 features reuse. Full design,
contract, and env vars in [`IMAGE_UPLOAD.md`](IMAGE_UPLOAD.md).

**Backend**
- `POST /api/images` (base64-JSON, no new dependency) + `GET /api/images/:id`.
- Two-layer validation: Zod shape (`ImageUploadRequest`) + decoded size &
  magic-byte sniff (`lib/imageValidation.js`).
- `lib/imageStore.js` storage abstraction — DB-backed default (Postgres
  `BYTEA` / SQLite `BLOB`), swappable to S3/R2 via `IMAGE_STORAGE_DRIVER`.
- `images` table (both DB branches); `uploadLimiter` (20/min/IP); route-scoped
  12 MB JSON parser.
- Tests: `tests/images.test.js` + `ImageUploadRequest` cases in
  `tests/schemas.test.js`. Full backend suite green (165 tests).

**iOS**
- `NetworkingKit`: image DTOs + `APIClient.uploadImage` + `ImageUploading`
  protocol (mirrors the Mode pattern).
- New `ImageUploadFeature` SPM package: ImageIO-backed JPEG preparer,
  `@Observable` ViewModel (idle → uploading → uploaded/failed, duplicate guard,
  retry), and a PhotosPicker-based view using the design system.
- Surfaced as an **Upload** tab in `AppShellView`; composed via `AppFeature`.
- Architecture fixture regenerated; `ImageUploadFeature` added to the governed
  feature modules. Full iOS package suite green (226 tests).

**Not done here:** build-number bump (set `CURRENT_PROJECT_VERSION` `5`→`6` in
`ios/project.yml` at release time), object-storage driver, image-in-chat.
