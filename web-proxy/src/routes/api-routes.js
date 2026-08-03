'use strict';

const express = require('express');
const { packRecommendationsResponse } = require('../dto');

const VALID_FAULT_MODES = new Set(['error', 'timeout', 'malformed']);

// Factory so tests can inject a stub gRPC client.
module.exports = function apiRouter({ getRecommendations }) {
  const router = express.Router();

  router.post('/api/recommendations', async (req, res) => {
    const measurements = parseMeasurements(req.body);
    if (!measurements) {
      return res.status(400).json({ error: 'invalid_measurements' });
    }

    try {
      const result = await getRecommendations(
        { measurements, faults: parseFaults(req.body.faults) },
        req.requestId,
      );
      // Packed-array wire format — see api/dto/. No property names cross the
      // wire, so ADVANCED compilation in the browser has nothing to rename.
      res.json(packRecommendationsResponse(result));
    } catch (err) {
      // No measurement values in the log line — request id only.
      req.log.error('get_recommendations_failed', { error: err.message });
      res.status(502).json({ error: 'upstream_unavailable' });
    }
  });

  return router;
};

function parseMeasurements(body) {
  const heightCm = Number(body.heightCm);
  const weightKg = Number(body.weightKg);
  if (!Number.isFinite(heightCm) || heightCm <= 0) return null;
  if (!Number.isFinite(weightKg) || weightKg <= 0) return null;

  // Birth date is optional by design: a user who declines it still gets
  // Service 1 results. 0 is the proto's "not supplied" sentinel.
  //
  // A birth date before 1970-01-01 is a NEGATIVE unix timestamp — that is a
  // legitimate value (Service 2 must still run), not an absence signal.
  // Only exactly 0 (or non-finite/missing input) means "not supplied".
  // Plausibility is validated explicitly here, independent of sign: reject
  // dates in the future or absurdly far in the past instead of leaning on
  // whether the number happens to be negative.
  const birthDateUnix = Number(body.birthDateUnix);
  if (body.birthDateUnix !== undefined && body.birthDateUnix !== null && body.birthDateUnix !== '') {
    if (!Number.isFinite(birthDateUnix)) return null;
    if (birthDateUnix !== 0) {
      const nowSec = Date.now() / 1000;
      if (birthDateUnix > nowSec) return null; // future date
      const earliestPlausible = -(150 * 365.25 * 24 * 60 * 60); // ~150 years before epoch
      if (birthDateUnix < earliestPlausible) return null; // absurdly old
    }
  }
  return {
    heightCm,
    weightKg,
    birthDateUnix: Number.isFinite(birthDateUnix) && birthDateUnix !== 0 ? birthDateUnix : 0,
  };
}

// Closed set: never build a fault mode from arbitrary request bytes.
function parseFaults(raw) {
  if (!raw || typeof raw !== 'object') return {};
  const out = {};
  for (const [provider, mode] of Object.entries(raw)) {
    if (VALID_FAULT_MODES.has(mode)) out[provider] = mode;
  }
  return out;
}
