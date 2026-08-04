goog.provide('funwithactivity.features.recommendations.api');

goog.require('funwithactivity.dto.HealthChartsResponse');
goog.require('funwithactivity.dto.RecommendationsResponse');
goog.require('goog.net.XhrIo');


/**
 * Anti-XSSI prefix web-proxy prepends to every JSON response under
 * /api/* (see web-proxy/src/xssi.js) — this API's wire format is a bare
 * JSON array (see api/dto/), the classic XSSI vector: a bare array is
 * valid JavaScript, so it can be pulled cross-origin via a
 * `<script src>` tag and read back through constructor/prototype tricks.
 * The prefix makes the body invalid JavaScript until stripped.
 * `goog.net.XhrIo#getResponseJson` strips a supplied prefix natively —
 * exactly why this module uses XhrIo instead of raw `fetch()`. Must stay
 * equal to web-proxy's `XSSI_PREFIX` (src/xssi.js) and the reference
 * implementation's `cyberfight.core.ApiClient.XSSI_PREFIX`.
 * @const {string}
 */
funwithactivity.features.recommendations.api.XSSI_PREFIX = ')]}\'\n';


/**
 * POSTs measurements and returns the parsed response as a DTO.
 *
 * The wire format is a packed array (see api/dto/), so there are no property
 * names for ADVANCED compilation to rename — the quoted-access discipline and
 * the externs file this used to need are both gone.
 *
 * @param {{heightCm: number, weightKg: number, birthDateUnix: number,
 *          faults: !Object<string,string>}} payload
 * @return {!Promise<!funwithactivity.dto.RecommendationsResponse>}
 */
funwithactivity.features.recommendations.api.fetch = function(payload) {
  return new Promise(function(resolve, reject) {
    goog.net.XhrIo.send(
        '/api/recommendations',
        function(e) {
          const xhr = /** @type {!goog.net.XhrIo} */ (e.target);
          if (!xhr.isSuccess()) {
            reject(new Error('request failed: ' + xhr.getStatus()));
            return;
          }
          const arr = xhr.getResponseJson(
              funwithactivity.features.recommendations.api.XSSI_PREFIX);
          resolve(funwithactivity.dto.RecommendationsResponse.fromJSON(
              /** @type {!Array} */ (arr)));
        },
        'POST',
        JSON.stringify(payload),
        {'Content-Type': 'application/json'});
  });
};


/**
 * POSTs measurements and returns the health charts for that profile.
 *
 * Separate call, not a field added to the recommendations response: charts
 * call no vendor and cannot be degraded by one, so bundling them would tie a
 * drawing feature's latency to two cold third-party Lambdas and make a vendor
 * outage look like a chart failure.
 *
 * @param {{heightCm: number, weightKg: number, birthDateUnix: number}} payload
 * @return {!Promise<!funwithactivity.dto.HealthChartsResponse>}
 */
funwithactivity.features.recommendations.api.fetchCharts = function(payload) {
  return new Promise(function(resolve, reject) {
    goog.net.XhrIo.send(
        '/api/charts',
        function(e) {
          const xhr = /** @type {!goog.net.XhrIo} */ (e.target);
          if (!xhr.isSuccess()) {
            reject(new Error('request failed: ' + xhr.getStatus()));
            return;
          }
          const arr = xhr.getResponseJson(
              funwithactivity.features.recommendations.api.XSSI_PREFIX);
          resolve(funwithactivity.dto.HealthChartsResponse.fromJSON(
              /** @type {!Array} */ (arr)));
        },
        'POST',
        JSON.stringify(payload),
        {'Content-Type': 'application/json'});
  });
};
