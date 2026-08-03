'use strict';

/**
 * Packs gRPC results into the packed-array wire format the browser expects.
 *
 * Slot order MIRRORS api/dto/*.js and must stay in lockstep — dto-parity.test.js
 * fails if the two drift. Append-only: new fields take new slots at the end.
 *
 * Booleans encode as 1/0.
 */

const SLOTS = {
  Recommendation: { TITLE: 0, DETAILS: 1, SOURCE: 2, SCORE: 3 },
  ProviderStatus: { NAME: 0, OK: 1, SKIPPED: 2, ERROR: 3, COUNT: 4, LATENCY_MS: 5, BASE_URL: 6 },
  RecommendationsResponse: { RECOMMENDATIONS: 0, STATUSES: 1 },
};

function packRecommendation(r) {
  return [
    r.title || '',
    r.details || '',
    r.source || '',
    Number(r.score || 0),
  ];
}

function packProviderStatus(s) {
  return [
    s.name || '',
    s.ok ? 1 : 0,
    s.skipped ? 1 : 0,
    s.error || '',
    Number(s.count || 0),
    Number(s.latencyMs || 0),
    s.baseUrl || '',
  ];
}

/**
 * @param {{recommendations: !Array, statuses: !Array}} result gRPC response.
 * @return {!Array} packed envelope
 */
function packRecommendationsResponse(result) {
  return [
    (result.recommendations || []).map(packRecommendation),
    (result.statuses || []).map(packProviderStatus),
  ];
}

module.exports = {
  SLOTS,
  packRecommendation,
  packProviderStatus,
  packRecommendationsResponse,
};
