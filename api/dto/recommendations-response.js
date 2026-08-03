/**
 * @fileoverview RecommendationsResponse DTO — the POST /api/recommendations
 * envelope. Packed at every level, including the nested children.
 *
 * Append-only: new fields take new slots at the end.
 */

goog.provide('funwithactivity.dto.RecommendationsResponse');

goog.require('funwithactivity.dto.ProviderStatus');
goog.require('funwithactivity.dto.Recommendation');


/** RecommendationsResponse DTO. */
funwithactivity.dto.RecommendationsResponse = class {
  /**
   * @param {!Array<!funwithactivity.dto.Recommendation>} recommendations
   *     Ranked, deduped, highest score first.
   * @param {!Array<!funwithactivity.dto.ProviderStatus>} statuses
   *     One per provider considered, including skipped ones.
   */
  constructor(recommendations, statuses) {
    /** @type {!Array<!funwithactivity.dto.Recommendation>} */
    this.recommendations = recommendations;
    /** @type {!Array<!funwithactivity.dto.ProviderStatus>} */
    this.statuses = statuses;
  }

  /**
   * @return {!Array}
   */
  toJSON() {
    return [
      this.recommendations.map((r) => r.toJSON()),
      this.statuses.map((s) => s.toJSON()),
    ];
  }

  /**
   * @param {!Array} arr
   * @return {!funwithactivity.dto.RecommendationsResponse}
   */
  static fromJSON(arr) {
    const F = funwithactivity.dto.RecommendationsResponse.Fields;
    const recs = (arr[F.RECOMMENDATIONS] || [])
        .map((a) => funwithactivity.dto.Recommendation.fromJSON(a));
    const statuses = (arr[F.STATUSES] || [])
        .map((a) => funwithactivity.dto.ProviderStatus.fromJSON(a));
    return new funwithactivity.dto.RecommendationsResponse(recs, statuses);
  }
};


/**
 * Slot indices. Append-only.
 * @enum {number}
 */
funwithactivity.dto.RecommendationsResponse.Fields = {
  RECOMMENDATIONS: 0,
  STATUSES: 1,
};
