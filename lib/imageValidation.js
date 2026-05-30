'use strict';

const { ALLOWED_IMAGE_TYPES, MAX_IMAGE_BYTES } = require('./schemas');

/**
 * Image payload validation (v3) — pure, no I/O, so it's directly unit-testable.
 *
 * Zod (lib/schemas.js) has already checked the request *shape* by the time
 * these run: sessionId, that `contentType` is one of the allowlist, and that
 * the base64 string is non-empty and under the length cap. What Zod can't see
 * is the decoded bytes — that's what this module covers: real decoded size and
 * a magic-byte sniff so a client can't smuggle a non-image (or a lying
 * content-type) past the MIME allowlist.
 */

/** Strip an optional `data:<mime>;base64,` prefix, returning bare base64. */
function stripDataUriPrefix(s) {
  const str = String(s || '');
  if (str.startsWith('data:')) {
    const comma = str.indexOf(',');
    if (comma !== -1) return str.slice(comma + 1);
  }
  return str;
}

/**
 * Identify an image by its leading bytes. Returns the canonical MIME string,
 * or null if the bytes match none of the supported formats.
 */
function sniffImageType(buf) {
  if (!Buffer.isBuffer(buf)) return null;
  // JPEG: FF D8 FF
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    return 'image/jpeg';
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (
    buf.length >= 8 &&
    buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47 &&
    buf[4] === 0x0d && buf[5] === 0x0a && buf[6] === 0x1a && buf[7] === 0x0a
  ) {
    return 'image/png';
  }
  // GIF: "GIF87a" or "GIF89a"
  if (
    buf.length >= 6 &&
    buf[0] === 0x47 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x38 &&
    (buf[4] === 0x37 || buf[4] === 0x39) && buf[5] === 0x61
  ) {
    return 'image/gif';
  }
  // WebP: "RIFF" .... "WEBP" (bytes 0-3 and 8-11)
  if (
    buf.length >= 12 &&
    buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46 &&
    buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50
  ) {
    return 'image/webp';
  }
  return null;
}

/**
 * Decode a base64 image payload and validate it. Returns one of:
 *   { ok: true,  buffer, contentType }
 *   { ok: false, status, error, message }
 *
 * `error`/`message` are the exact wire envelope the route returns, so the
 * handler is a thin pass-through and these cases are testable without HTTP.
 */
function decodeAndValidateImage({ data, contentType }) {
  if (!ALLOWED_IMAGE_TYPES.includes(contentType)) {
    return { ok: false, status: 400, error: 'image_invalid_type', message: 'Unsupported image type. Use JPEG, PNG, WebP, or GIF.' };
  }

  const buffer = Buffer.from(stripDataUriPrefix(data), 'base64');
  if (buffer.length === 0) {
    return { ok: false, status: 400, error: 'image_missing', message: 'No image data provided.' };
  }
  if (buffer.length > MAX_IMAGE_BYTES) {
    return { ok: false, status: 413, error: 'image_too_large', message: 'Image is too large.' };
  }

  // The declared type must match the actual bytes.
  if (sniffImageType(buffer) !== contentType) {
    return { ok: false, status: 400, error: 'image_invalid_type', message: 'Unsupported image type. Use JPEG, PNG, WebP, or GIF.' };
  }

  return { ok: true, buffer, contentType };
}

module.exports = {
  decodeAndValidateImage,
  sniffImageType,
  stripDataUriPrefix,
  ALLOWED_IMAGE_TYPES,
  MAX_IMAGE_BYTES,
};
