'use strict';

const db = require('../db');
const logger = require('./logger');

/**
 * Image storage abstraction (v3).
 *
 * The endpoint layer (server.js) talks ONLY to this module — never to a
 * concrete provider. The default `db` driver persists bytes in the existing
 * database (`images` table, Postgres/SQLite via db.js), so uploads work
 * end-to-end with zero new infrastructure or credentials.
 *
 * To move to object storage later (S3, Cloudflare R2, Supabase, Firebase),
 * implement a driver below that reads its config from environment variables
 * and set `IMAGE_STORAGE_DRIVER`. No endpoint, schema, or client changes are
 * required — the contract (`put` / `get`) is the seam.
 *
 * Never hardcode storage credentials here; drivers read them from env.
 *
 * Environment:
 *   IMAGE_STORAGE_DRIVER   'db' (default) | 's3' | 'r2' | ...
 *
 * Stored-image shape returned by `get`:
 *   { id, sessionId, contentType, fileName, sizeBytes, data: Buffer, createdAt }
 */

const DRIVER_NAME = process.env.IMAGE_STORAGE_DRIVER || 'db';

// ── Default driver: bytes live in the existing database ──
const dbDriver = {
  async put(image) {
    await db.saveImage(image);
  },
  async get(id) {
    const row = await db.getImage(id);
    if (!row) return null;
    return {
      id: row.id,
      sessionId: row.session_id,
      contentType: row.content_type,
      fileName: row.file_name,
      sizeBytes: Number(row.size_bytes),
      data: row.data, // Buffer on both pg (BYTEA) and better-sqlite3 (BLOB)
      createdAt: Number(row.created_at),
    };
  },
};

// ── Object-storage drivers — seams, intentionally not wired yet ──
// To enable: implement put/get against the provider's SDK, reading creds
// from env (e.g. S3_BUCKET / S3_REGION / S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY
// for S3; R2_* for Cloudflare R2), then set IMAGE_STORAGE_DRIVER. Throwing
// here makes a mis-set env var fail loudly instead of silently dropping data.
function unconfiguredDriver(name) {
  const fail = async () => {
    throw new Error(`imageStore: '${name}' driver is selected but not configured`);
  };
  return { put: fail, get: fail };
}

const drivers = {
  db: dbDriver,
  s3: unconfiguredDriver('s3'),
  r2: unconfiguredDriver('r2'),
};

const resolvedName = drivers[DRIVER_NAME] ? DRIVER_NAME : 'db';
const driver = drivers[resolvedName];

if (!drivers[DRIVER_NAME]) {
  logger.warn({ requested: DRIVER_NAME }, 'imageStore: unknown driver, falling back to db');
} else {
  logger.info({ driver: resolvedName }, 'imageStore driver selected');
}

module.exports = {
  /** Name of the active driver — handy for /api/health and tests. */
  driverName: resolvedName,
  /** Persist an image. `image` is the full stored-image record incl. Buffer. */
  put: (image) => driver.put(image),
  /** Fetch a stored image by id, or null. */
  get: (id) => driver.get(id),
};
