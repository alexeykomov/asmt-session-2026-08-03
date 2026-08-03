goog.provide('funwithactivity.features.recommendations.api');

goog.require('funwithactivity.dto.RecommendationsResponse');


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
  return fetch('/api/recommendations', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(payload),
  }).then(function(res) {
    if (!res.ok) throw new Error('request failed: ' + res.status);
    return res.json();
  }).then(function(arr) {
    return funwithactivity.dto.RecommendationsResponse.fromJSON(arr);
  });
};
