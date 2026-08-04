/**
 * @fileoverview Chart DTO — one drawable chart.
 *
 * `type` is on the wire so a client never has to infer a shape from `id`: a
 * server that later adds a chart must not require a client release to know
 * how to draw it, and a client that meets an unknown type can skip it rather
 * than guess.
 *
 * Append-only: new fields take new slots at the end.
 */

goog.provide('funwithactivity.dto.Chart');

goog.require('funwithactivity.dto.Series');


/** Chart DTO. */
funwithactivity.dto.Chart = class {
  /**
   * @param {string} id Stable identifier: "steps" | "sleep" |
   *     "active_minutes".
   * @param {string} title Display heading.
   * @param {number} type One of funwithactivity.dto.Chart.Type.
   * @param {!Array<string>} categories X-axis labels for bar charts; slice
   *     labels for pies.
   * @param {!Array<!funwithactivity.dto.Series>} series
   */
  constructor(id, title, type, categories, series) {
    /** @type {string} */
    this.id = id;
    /** @type {string} */
    this.title = title;
    /** @type {number} */
    this.type = type;
    /** @type {!Array<string>} */
    this.categories = categories;
    /** @type {!Array<!funwithactivity.dto.Series>} */
    this.series = series;
  }

  /** @return {!Array} Packed wire form. */
  toJSON() {
    return [
      this.id,
      this.title,
      this.type,
      this.categories,
      this.series.map((s) => s.toJSON()),
    ];
  }

  /**
   * @param {!Array} arr
   * @return {!funwithactivity.dto.Chart}
   */
  static fromJSON(arr) {
    const F = funwithactivity.dto.Chart.Fields;
    return new funwithactivity.dto.Chart(
        String(arr[F.ID] || ''),
        String(arr[F.TITLE] || ''),
        Number(arr[F.TYPE] || 0),
        (arr[F.CATEGORIES] || []).map(String),
        (arr[F.SERIES] || []).map(
            (a) => funwithactivity.dto.Series.fromJSON(a)));
  }
};


/**
 * Slot indices. Append-only.
 * @enum {number}
 */
funwithactivity.dto.Chart.Fields = {
  ID: 0,
  TITLE: 1,
  TYPE: 2,
  CATEGORIES: 3,
  SERIES: 4,
};


/**
 * Mirrors ChartType in api/proto/recommendations.proto. Values must match the
 * proto enum's numbers exactly — web-proxy passes the number straight
 * through rather than translating it.
 * @enum {number}
 */
funwithactivity.dto.Chart.Type = {
  UNSPECIFIED: 0,
  BAR: 1,
  PIE: 2,
  GROUPED_BAR: 3,
};
