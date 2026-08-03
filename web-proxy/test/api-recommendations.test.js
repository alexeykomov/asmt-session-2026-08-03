'use strict';

const request = require('supertest');
const { expect } = require('chai');
const { buildApp } = require('../src/server');
const { SLOTS } = require('../src/dto');

const OK_RESPONSE = {
  recommendations: [
    { title: 'Have more workouts per day', details: 'Workouts help.', source: 'service2', score: 0.75 },
    { title: 'Walk more', details: '', source: 'service1', score: 0.4 },
  ],
  statuses: [
    { name: 'service1', ok: true, skipped: false, error: '', count: 3, latencyMs: 90 },
    { name: 'service2', ok: true, skipped: false, error: '', count: 4, latencyMs: 120 },
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
    { name: 'service1', ok: false, skipped: true, error: 'birth date not supplied', count: 0, latencyMs: 0 },
    { name: 'service2', ok: true, skipped: false, error: '', count: 1, latencyMs: 120 },
  ],
};

describe('web-proxy /api/recommendations', () => {
  it('returns ranked recommendations with provider statuses', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: 1615876858 });

    expect(res.status).to.equal(200);
    const R = SLOTS.RecommendationsResponse;
    const F = SLOTS.Recommendation;
    const S = SLOTS.ProviderStatus;
    expect(res.body[R.RECOMMENDATIONS]).to.have.length(2);
    expect(res.body[R.RECOMMENDATIONS][0][F.TITLE]).to.equal('Have more workouts per day');
    expect(res.body[R.RECOMMENDATIONS][0][F.DETAILS]).to.equal('Workouts help.');
    expect(res.body[R.RECOMMENDATIONS][0][F.SOURCE]).to.equal('service2');
    expect(res.body[R.RECOMMENDATIONS][0][F.SCORE]).to.equal(0.75);
    expect(res.body[R.STATUSES]).to.have.length(2);
    expect(res.body[R.STATUSES][0][S.NAME]).to.equal('service1');
    expect(res.body[R.STATUSES][0][S.OK]).to.equal(1);
    expect(res.body[R.STATUSES][0][S.SKIPPED]).to.equal(0);
    expect(res.body[R.STATUSES][0][S.COUNT]).to.equal(3);
    expect(res.body[R.STATUSES][0][S.LATENCY_MS]).to.equal(90);
  });

  it('packs a skipped provider status with SKIPPED and ERROR in their own slots', async () => {
    // Guards against inverting the skipped/error slot order — skipped
    // statuses also populate `error`, and swapping these two slots (or
    // dropping one of them) has caused defects in this project before.
    const app = buildApp({ getRecommendations: async () => SKIPPED_RESPONSE });
    const res = await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84 });

    expect(res.status).to.equal(200);
    const R = SLOTS.RecommendationsResponse;
    const S = SLOTS.ProviderStatus;
    const skippedStatus = res.body[R.STATUSES][0];
    expect(skippedStatus[S.NAME]).to.equal('service1');
    expect(skippedStatus[S.OK]).to.equal(0);
    expect(skippedStatus[S.SKIPPED]).to.equal(1);
    expect(skippedStatus[S.ERROR]).to.equal('birth date not supplied');

    const okStatus = res.body[R.STATUSES][1];
    expect(okStatus[S.SKIPPED]).to.equal(0);
    expect(okStatus[S.ERROR]).to.equal('');
  });

  it('passes measurements through to app-server', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await request(app)
      .post('/api/recommendations')
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
    await request(app).post('/api/recommendations').send({ heightCm: 184, weightKg: 84 });

    expect(seen.measurements.birthDateUnix).to.equal(0);
  });

  it('passes through a pre-1970 birth date instead of coercing it to 0', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    // 1969-01-01T00:00:00Z — a negative unix timestamp, and a legitimate DOB.
    await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: -31536000 });

    expect(seen.measurements.birthDateUnix).to.equal(-31536000);
  });

  it('passes through a post-1970 birth date unchanged', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: 1615876858 });

    expect(seen.measurements.birthDateUnix).to.equal(1615876858);
  });

  it('treats an explicit 0 birthDateUnix as not supplied', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: 0 });

    expect(seen.measurements.birthDateUnix).to.equal(0);
  });

  it('rejects a future birth date with 400', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const oneYearFromNow = Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60;
    const res = await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: oneYearFromNow });

    expect(res.status).to.equal(400);
    expect(res.body.error).to.equal('invalid_measurements');
  });

  it('rejects an absurdly old birth date with 400', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    // ~200 years before epoch.
    const res = await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, birthDateUnix: -200 * 365.25 * 24 * 60 * 60 });

    expect(res.status).to.equal(400);
    expect(res.body.error).to.equal('invalid_measurements');
  });

  it('forwards fault modes for the demo toggle', async () => {
    let seen = null;
    const app = buildApp({
      getRecommendations: async (payload) => { seen = payload; return OK_RESPONSE; },
    });
    await request(app)
      .post('/api/recommendations')
      .send({ heightCm: 184, weightKg: 84, faults: { service2: 'timeout' } });

    expect(seen.faults).to.deep.equal({ service2: 'timeout' });
  });

  it('rejects a non-numeric height with 400', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await request(app).post('/api/recommendations').send({ heightCm: 'tall', weightKg: 84 });
    expect(res.status).to.equal(400);
    expect(res.body.error).to.equal('invalid_measurements');
  });

  it('returns 502 when app-server is unreachable', async () => {
    const app = buildApp({
      getRecommendations: async () => { throw new Error('upstream broken'); },
    });
    const res = await request(app).post('/api/recommendations').send({ heightCm: 184, weightKg: 84 });
    expect(res.status).to.equal(502);
    expect(res.body).to.deep.equal({ error: 'upstream_unavailable' });
  });

  it('returns 400 with no stack trace for malformed JSON', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await request(app)
      .post('/api/recommendations')
      .set('Content-Type', 'application/json')
      .send('{"heightCm": 184,'); // truncated / unparseable

    expect(res.status).to.equal(400);
    expect(res.body).to.deep.equal({ error: 'invalid_json' });
    const raw = JSON.stringify(res.body) + (res.text || '');
    expect(raw).to.not.include('at JSON.parse');
    expect(raw).to.not.include('SyntaxError');
    expect(raw).to.not.match(/\/src\/server\.js/);
  });

  it('GET /health returns ok', async () => {
    const app = buildApp({ getRecommendations: async () => OK_RESPONSE });
    const res = await request(app).get('/health');
    expect(res.status).to.equal(200);
    expect(res.body).to.deep.equal({ status: 'ok' });
  });
});
