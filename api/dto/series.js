/**
 * @fileoverview Series DTO — one named run of values inside a Chart.
 *
 * Wire format is a positional array, not a named object, for the same reason
 * every other DTO here is: under ADVANCED compilation the compiler renames
 * property accesses but leaves JSON string keys untouched, so `s.label` and
 * `"label"` silently stop matching. With no names on the wire there is
 * nothing to rename.
 *
 * `key` and `label` are deliberately separate. Clients map `key` to a named
 * colour asset; `label` is display text and is safe to reword. Mapping colour
 * on display text would mean a copy edit silently recolours a chart, which is
 * very hard to notice in a screenshot.
 *
 * Append-only: new fields take new slots at the end. Never reorder or
 * repurpose an existing slot — web-proxy packs by the same indices.
 */

goog.provide('funwithactivity.dto.Series');


/** Series DTO. */
funwithactivity.dto.Series = class {
  /**
   * @param {string} key Stable mapping handle, e.g. "deep" or "vigorous".
   * @param {string} label Display text, e.g. "Deep".
   * @param {!Array<number>} values One per Chart category for bar charts; a
   *     single value for a pie slice.
   */
  constructor(key, label, values) {
    /** @type {string} */
    this.key = key;
    /** @type {string} */
    this.label = label;
    /** @type {!Array<number>} */
    this.values = values;
  }

  /** @return {!Array} Packed wire form. */
  toJSON() {
    return [this.key, this.label, this.values];
  }

  /**
   * @param {!Array} arr
   * @return {!funwithactivity.dto.Series}
   */
  static fromJSON(arr) {
    const F = funwithactivity.dto.Series.Fields;
    return new funwithactivity.dto.Series(
        String(arr[F.KEY] || ''),
        String(arr[F.LABEL] || ''),
        (arr[F.VALUES] || []).map(Number));
  }
};


/**
 * Slot indices. Append-only.
 * @enum {number}
 */
funwithactivity.dto.Series.Fields = {
  KEY: 0,
  LABEL: 1,
  VALUES: 2,
};
