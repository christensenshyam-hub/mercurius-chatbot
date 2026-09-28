'use strict';

// Polls `read` until `until(value)` holds and resolves with that value. For
// asserting on a write the server makes fire-and-forget in another process:
// a fixed sleep fails a correct build whenever a loaded runner is slower.
// On timeout it resolves with the last value read, so the caller's assertion
// reports what was actually there.
async function waitFor(read, until, { timeoutMs = 5000, intervalMs = 25 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let value = await read();
  while (!until(value) && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, intervalMs));
    value = await read();
  }
  return value;
}

module.exports = { waitFor };
