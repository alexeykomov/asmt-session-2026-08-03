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
  Series: { KEY: 0, LABEL: 1, VALUES: 2 },
  Chart: { ID: 0, TITLE: 1, TYPE: 2, CATEGORIES: 3, SERIES: 4 },
  HealthChartsResponse: { CHARTS: 0 },
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

function packSeries(s) {
  return [
    s.key || '',
    s.label || '',
    (s.values || []).map(Number),
  ];
}

/**
 * ChartType name -> number, mirroring the enum in
 * api/proto/recommendations.proto and Chart.Type in api/dto/chart.js.
 *
 * This table exists because grpc-client loads the proto with
 * `enums: String`, so an enum field arrives as its NAME ("CHART_TYPE_BAR"),
 * not its number. Passing that through Number() yields NaN, which
 * JSON.stringify writes as null — a chart that reaches the browser with no
 * type and silently renders as unsupported. That is exactly what happened,
 * and it survived the unit tests because the fixture used numbers while the
 * real gRPC layer sends names.
 */
const CHART_TYPE_NUMBERS = {
  CHART_TYPE_UNSPECIFIED: 0,
  CHART_TYPE_BAR: 1,
  CHART_TYPE_PIE: 2,
  CHART_TYPE_GROUPED_BAR: 3,
};

/**
 * Accepts either form so this keeps working if the loader's `enums` option
 * is ever flipped to Number.
 */
function chartTypeNumber(type) {
  if (typeof type === 'number') return Number.isFinite(type) ? type : 0;
  if (typeof type === 'string') return CHART_TYPE_NUMBERS[type] || 0;
  return 0;
}

function packChart(c) {
  return [
    c.id || '',
    c.title || '',
    chartTypeNumber(c.type),
    (c.categories || []).map(String),
    (c.series || []).map(packSeries),
  ];
}

/**
 * @param {{charts: !Array}} result gRPC response.
 * @return {!Array} packed envelope
 */
function packHealthChartsResponse(result) {
  return [
    (result.charts || []).map(packChart),
  ];
}

module.exports = {
  SLOTS,
  packRecommendation,
  packProviderStatus,
  packRecommendationsResponse,
  packSeries,
  packChart,
  packHealthChartsResponse,
  chartTypeNumber,
};
