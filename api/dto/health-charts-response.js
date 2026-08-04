/**
 * @fileoverview HealthChartsResponse DTO — the POST /api/charts envelope.
 * Packed at every level, including the nested children.
 *
 * A one-field envelope rather than a bare array of charts: this response has
 * already needed one additive change in its life (base_url on ProviderStatus)
 * and an envelope is what makes the next one a new slot instead of a breaking
 * reshape.
 *
 * Append-only: new fields take new slots at the end.
 */

goog.provide('funwithactivity.dto.HealthChartsResponse');

goog.require('funwithactivity.dto.Chart');


/** HealthChartsResponse DTO. */
funwithactivity.dto.HealthChartsResponse = class {
  /**
   * @param {!Array<!funwithactivity.dto.Chart>} charts In server order; the
   *     client renders them top to bottom as given.
   */
  constructor(charts) {
    /** @type {!Array<!funwithactivity.dto.Chart>} */
    this.charts = charts;
  }

  /** @return {!Array} Packed wire form. */
  toJSON() {
    return [this.charts.map((c) => c.toJSON())];
  }

  /**
   * @param {!Array} arr
   * @return {!funwithactivity.dto.HealthChartsResponse}
   */
  static fromJSON(arr) {
    const F = funwithactivity.dto.HealthChartsResponse.Fields;
    return new funwithactivity.dto.HealthChartsResponse(
        (arr[F.CHARTS] || []).map(
            (a) => funwithactivity.dto.Chart.fromJSON(a)));
  }
};


/**
 * Slot indices. Append-only.
 * @enum {number}
 */
funwithactivity.dto.HealthChartsResponse.Fields = {
  CHARTS: 0,
};
