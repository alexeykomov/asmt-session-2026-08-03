/**
 * @fileoverview Recommendation DTO.
 *
 * Wire format is a positional array, not a named object. That is deliberate:
 * under ADVANCED compilation the compiler renames property accesses, but JSON
 * string keys are untouched — so `rec.score` and `"score"` silently stop
 * matching. With no names on the wire there is nothing to rename. It also
 * removes the need for an externs file.
 *
 * Append-only: new fields take new slots at the end. Never reorder or
 * repurpose an existing slot — the server packs by the same indices.
 */

goog.provide('funwithactivity.dto.Recommendation');


/** Recommendation DTO. */
funwithactivity.dto.Recommendation = class {
  /**
   * @param {string} title Short recommendation text.
   * @param {string} details Longer explanation; empty for providers that
   *     do not supply one.
   * @param {string} source Provider name, shown as provenance in the UI.
   * @param {number} score Final ranked score, 0..1.
   */
  constructor(title, details, source, score) {
    /** @type {string} */
    this.title = title;
    /** @type {string} */
    this.details = details;
    /** @type {string} */
    this.source = source;
    /** @type {number} */
    this.score = score;
  }

  /**
   * @return {!Array} Packed wire form.
   */
  toJSON() {
    return [this.title, this.details, this.source, this.score];
  }

  /**
   * @param {!Array} arr
   * @return {!funwithactivity.dto.Recommendation}
   */
  static fromJSON(arr) {
    const F = funwithactivity.dto.Recommendation.Fields;
    return new funwithactivity.dto.Recommendation(
        String(arr[F.TITLE] || ''),
        String(arr[F.DETAILS] || ''),
        String(arr[F.SOURCE] || ''),
        Number(arr[F.SCORE] || 0));
  }
};


/**
 * Slot indices. Append-only.
 * @enum {number}
 */
funwithactivity.dto.Recommendation.Fields = {
  TITLE: 0,
  DETAILS: 1,
  SOURCE: 2,
  SCORE: 3,
};
