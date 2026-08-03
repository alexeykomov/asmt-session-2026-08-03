/**
 * @fileoverview ProviderStatus DTO — per-provider outcome for one request.
 *
 * Three outcomes are distinguishable and must stay so: ok; skipped (the user
 * declined an input this provider requires — deliberate data minimisation,
 * NOT a failure); and failed. Note `error` is populated for skipped statuses
 * too, which is why consumers must test `skipped` before `error`.
 *
 * Append-only: new fields take new slots at the end.
 */

goog.provide('funwithactivity.dto.ProviderStatus');


/** ProviderStatus DTO. */
funwithactivity.dto.ProviderStatus = class {
  /**
   * @param {string} name Provider name.
   * @param {boolean} ok Whether the provider returned results.
   * @param {boolean} skipped Whether it was deliberately not called.
   * @param {string} error Human-readable reason; set for skipped too.
   * @param {number} count Number of recommendations returned.
   * @param {number} latencyMs Round-trip time; 0 when skipped.
   * @param {string=} baseUrl The provider's configured endpoint, for
   *     display only. Set even when skipped. Optional so old callers /
   *     fixtures that predate this field keep working.
   */
  constructor(name, ok, skipped, error, count, latencyMs, baseUrl) {
    /** @type {string} */
    this.name = name;
    /** @type {boolean} */
    this.ok = ok;
    /** @type {boolean} */
    this.skipped = skipped;
    /** @type {string} */
    this.error = error;
    /** @type {number} */
    this.count = count;
    /** @type {number} */
    this.latencyMs = latencyMs;
    /** @type {string} */
    this.baseUrl = baseUrl || '';
  }

  /**
   * Booleans encode as 1/0 for consistency with the reference monorepo's
   * DTO convention.
   * @return {!Array}
   */
  toJSON() {
    return [
      this.name,
      this.ok ? 1 : 0,
      this.skipped ? 1 : 0,
      this.error,
      this.count,
      this.latencyMs,
      this.baseUrl,
    ];
  }

  /**
   * Tolerant of 1/0 (canonical wire) or true/false (fixtures).
   * @param {!Array} arr
   * @return {!funwithactivity.dto.ProviderStatus}
   */
  static fromJSON(arr) {
    const F = funwithactivity.dto.ProviderStatus.Fields;
    return new funwithactivity.dto.ProviderStatus(
        String(arr[F.NAME] || ''),
        !!arr[F.OK],
        !!arr[F.SKIPPED],
        String(arr[F.ERROR] || ''),
        Number(arr[F.COUNT] || 0),
        Number(arr[F.LATENCY_MS] || 0),
        String(arr[F.BASE_URL] || ''));
  }
};


/**
 * Slot indices. Append-only.
 * @enum {number}
 */
funwithactivity.dto.ProviderStatus.Fields = {
  NAME: 0,
  OK: 1,
  SKIPPED: 2,
  ERROR: 3,
  COUNT: 4,
  LATENCY_MS: 5,
  BASE_URL: 6,
};
