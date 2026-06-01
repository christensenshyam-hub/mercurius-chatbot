'use strict';

const { ALLOWED_IMAGE_TYPES } = require('./schemas');

/**
 * Build the Anthropic `content` for the latest user turn (v3 vision).
 *
 * Text-only returns a plain string (the existing behavior). With a valid
 * attached image it returns Claude's multimodal content array — an image
 * block followed by a text block — so the model can actually see the image.
 *
 * Pure (no I/O) so it's unit-testable; the handler does the image fetch and
 * passes the decoded bits in.
 *
 * @param {string} text - the user's typed message (may be empty if they sent
 *   only a photo).
 * @param {{contentType: string, dataBase64: string}|null} image - the attached
 *   image, already fetched + base64-encoded, or null/invalid for text-only.
 */
function buildUserContent(text, image) {
  const trimmed = (text || '').trim();

  const hasValidImage =
    image &&
    typeof image.contentType === 'string' &&
    typeof image.dataBase64 === 'string' &&
    image.dataBase64.length > 0 &&
    ALLOWED_IMAGE_TYPES.includes(image.contentType);

  if (!hasValidImage) {
    return trimmed;
  }

  return [
    {
      type: 'image',
      source: { type: 'base64', media_type: image.contentType, data: image.dataBase64 },
    },
    {
      // A non-empty text block is required; default to a gentle prompt when the
      // student sent only a photo.
      type: 'text',
      text: trimmed || 'Take a look at this image and help me understand it.',
    },
  ];
}

module.exports = { buildUserContent };
