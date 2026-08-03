'use strict';

const request = require('supertest');
const { expect } = require('chai');
const { buildApp } = require('../src/server');
const { SLOTS } = require('../src/dto');
const { XSSI_PREFIX } = require('../src/xssi');

// supertest/superagent auto-parses an `application/json` body as JSON,
// which throws on this API's XSSI-prefixed responses — the prefix is
// deliberately invalid JSON/JS until stripped (see ../src/xssi.js), the
// same way the real client (web-client's
// funwithactivity.features.recommendations.api, via goog.net.XhrIo's
// built-in prefix argument) handles it. Requests against /api/* use this
// raw-text parser instead, so tests strip the prefix themselves.
function rawTextParser(res, cb) {
  res.setEncoding('utf8');
  let data = '';
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => cb(null, data));
}

function apiRequest(app, method, path) {
  return request(app)[method](path).buffer(true).parse(rawTextParser);
}

// Strips the XSSI prefix and parses the remainder as JSON. Asserts the
// prefix was actually present first — a response missing it must fail the
// test loudly rather than happen to parse anyway.
function stripXssi(rawText) {
  expect(rawText.startsWith(XSSI_PREFIX), 'response body must start with the XSSI prefix').to.equal(true);
  return JSON.parse(rawText.slice(XSSI_PREFIX.length));
}

const OK_RESPONSE = {
  recommendations: [
    { title: 'Have more workouts per day', details: 'Workouts help.', source: 'service2', score: 0.75 },
    { title: 'Walk more', details: '', source: 'service1', score: 0.4 },
  ],
  statuses: [
    { name: 'service1', ok: true, skipped: false, error: '', count: 3, latencyMs: 90, baseUrl: 'https://service1.example/api' },
    { name: 'service2', ok: true, skipped: false, error: '', count: 4, latencyMs: 120, baseUrl: 'https://service2.example/api' },
  ],
};

// service1 is skipped (the user declined to supply a birth date) but still
// carries a non-empty `error` explaining why — consumers must test `skipped`
// before `error`. These slot values are deliberately distinct (skipped=1,
// ok=0, non-empty error) so a wire-format test that swapped the SKIPPED and
// ERROR slots — or any encoding that dropped one of them — would be caught.
const SKIPPED_RESPONSE = {
  recommendations: [],
  statuses: [
    { name: 'service1', ok: false, skipped: true, error: 'birth date not supplied', count: 0, latencyMs: 0, baseUrl: 'https://service1.example/api' },
    { name: 'service2', ok: true, skipped: false, error: '', count: 1, latencyMs: 120, baseUrl: 'https://service2.example/api' },
  ],
};

describe('web-proxy /api/recommendations', () => {
  it('returns ranked recommendations with provider statuses', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: 1615876858 });

    expect(res.status).to.equal(200);
    const body = stripXssi(res.body);
    const R = SLOTS.RecommendationsResponse;
    const F = SLOTS.Recommendation;
    const S = SLOTS.ProviderStatus;
    expect(body[R.RECOMMENDATIONS]).to.have.length(2);
    expect(body[R.RECOMMENDATIONS][0][F.TITLE]).to.equal('Have more workouts per day');
    expect(body[R.RECOMMENDATIONS][0][F.DETAILS]).to.equal('Workouts help.');
    expect(body[R.RECOMMENDATIONS][0][F.SOURCE]).to.equal('service2');
    expect(body[R.RECOMMENDATIONS][0][F.SCORE]).to.equal(0.75);
    expect(body[R.STATUSES]).to.have.length(2);
    expect(body[R.STATUSES][0][S.NAME]).to.equal('service1');
    expect(body[R.STATUSES][0][S.OK]).to.equal(1);
    expect(body[R.STATUSES][0][S.SKIPPED]).to.equal(0);
    expect(body[R.STATUSES][0][S.COUNT]).to.equal(3);
    expect(body[R.STATUSES][0][S.LATENCY_MS]).to.equal(90);
    expect(body[R.STATUSES][0][S.BASE_URL]).to.equal('https://service1.example/api');
  });

  it('packs a skipped provider status with SKIPPED and ERROR in their own slots', async () => {
    // Guards against inverting the skipped/error slot order — skipped
    // statuses also populate `error`, and swapping these two slots (or
    // dropping one of them) has caused defects in this project before.
    const app = buildApp({ getRecommendations: async () => SKIPPED_RESPONSE });
    const res = await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84 });

    expect(res.status).to.equal(200);
    const body = stripXssi(res.body);
    const R = SLOTS.RecommendationsResponse;
    const S = SLOTS.ProviderStatus;
    const skippedStatus = body[R.STATUSES][0];
    expect(skippedStatus[S.NAME]).to.equal('service1');
    expect(skippedStatus[S.OK]).to.equal(0);
    expect(skippedStatus[S.SKIPPED]).to.equal(1);
    expect(skippedStatus[S.ERROR]).to.equal('birth date not supplied');
    expect(skippedStatus[S.BASE_URL]).to.equal('https://service1.example/api',
        'a skipped provider still reports its configured endpoint');

    const okStatus = body[R.STATUSES][1];
    expect(okStatus[S.SKIPPED]).to.equal(0);
    expect(okStatus[S.ERROR]).to.equal('');
  });

  it('prefixes /api/* JSON responses with the anti-XSSI marker', async () => {
    // Regression guard: a future refactor that swaps res.json() for
    // res.send()/res.status().json() without going through the
    // xssiJson-patched res, or that reorders middleware so the patch
    // never applies, must fail here loudly rather than silently drop the
    // protection.
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84 });

    expect(res.body.startsWith(XSSI_PREFIX)).to.equal(true);
  });

  it('passes measurements through to app-server', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: 1615876858 });

    expect(seen.measurements.heightCm).to.equal(184);
    expect(seen.measurements.weightKg).to.equal(84);
    expect(seen.measurements.birthDateUnix).to.equal(1615876858);
  });

  it('omits birthDateUnix when the user declined to supply it', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await apiRequest(app, 'post', '/api/recommendations').send({ heightCm: 184, weightKg: 84 });

    expect(seen.measurements.birthDateUnix).to.equal(0);
  });

  it('passes through a pre-1970 birth date instead of coercing it to 0', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    // 1969-01-01T00:00:00Z — a negative unix timestamp, and a legitimate DOB.
    await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: -31536000 });

    expect(seen.measurements.birthDateUnix).to.equal(-31536000);
  });

  it('passes through a post-1970 birth date unchanged', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: 1615876858 });

    expect(seen.measurements.birthDateUnix).to.equal(1615876858);
  });

  it('treats an explicit 0 birthDateUnix as not supplied', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: 0 });

    expect(seen.measurements.birthDateUnix).to.equal(0);
  });

  it('rejects a future birth date with 400', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const oneYearFromNow = Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60;
    const res = await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: oneYearFromNow });

    expect(res.status).to.equal(400);
    expect(stripXssi(res.body).error).to.equal('invalid_measurements');
  });

  it('rejects an absurdly old birth date with 400', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    // ~200 years before epoch.
    const res = await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: -200 * 365.25 * 24 * 60 * 60 });

    expect(res.status).to.equal(400);
    expect(stripXssi(res.body).error).to.equal('invalid_measurements');
  });

  it('forwards fault modes for the demo toggle', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await apiRequest(app, 'post', '/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, faults: { service2: 'timeout' } });

    expect(seen.faults).to.deep.equal({ service2: 'timeout' });
  });

  it('rejects a non-numeric height with 400', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await apiRequest(app, 'post', '/api/recommendations').send({ heightCm: 'tall', weightKg: 84 });
    expect(res.status).to.equal(400);
    expect(stripXssi(res.body).error).to.equal('invalid_measurements');
  });

  it('returns 502 when app-server is unreachable', async () => {
    const app = buildApp({
      getRecommendations: async () => { throw new Error('upstream broken'); },
    });
    const res = await apiRequest(app, 'post', '/api/recommendations').send({ heightCm: 184, weightKg: 84 });
    expect(res.status).to.equal(502);
    expect(stripXssi(res.body)).to.deep.equal({ error: 'upstream_unavailable' });
  });

  it('returns 400 with no stack trace for malformed JSON', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await apiRequest(app, 'post', '/api/recommendations')
      .set('Content-Type', 'application/json')
      .send('{"heightCm": 184,'); // truncated / unparseable

    expect(res.status).to.equal(400);
    expect(stripXssi(res.body)).to.deep.equal({ error: 'invalid_json' });
    const raw = res.body;
    expect(raw).to.not.include('at JSON.parse');
    expect(raw).to.not.include('SyntaxError');
    expect(raw).to.not.match(/\/src\/server\.js/);
  });

  it('GET /health returns ok, unprefixed', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await request(app).get('/health');
    expect(res.status).to.equal(200);
    expect(res.body).to.deep.equal({ status: 'ok' });
  });
});
