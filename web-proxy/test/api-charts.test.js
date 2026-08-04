'use strict';

const request = require('supertest');
const { expect } = require('chai');
const { buildApp } = require('../src/server');
const { SLOTS } = require('../src/dto');
const { XSSI_PREFIX } = require('../src/xssi');

// Same raw-text parsing as api-recommendations.test.js: the XSSI prefix is
// deliberately invalid JSON until stripped, so superagent's automatic JSON
// parsing would throw on every /api response.
function rawTextParser(res, cb) {
  res.setEncoding('utf8');
  let data = '';
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => cb(null, data));
}

function apiPost(app, path) {
  return request(app).post(path).buffer(true).parse(rawTextParser);
}

function stripXssi(rawText) {
  expect(rawText.startsWith(XSSI_PREFIX),
    'response did not carry the XSSI prefix').to.equal(true);
  return JSON.parse(rawText.slice(XSSI_PREFIX.length));
}

const VALID_BODY = { heightCm: 175, weightKg: 70, birthDateUnix: 423097200 };

// One chart of each shape, so packing is exercised across all three.
const FAKE_CHARTS = {
  charts: [
    {
      id: 'steps',
      title: 'Steps, last 7 days',
      // Enum NAMES, not numbers: grpc-client loads the proto with
      // `enums: String`, so this is the shape the route really receives.
      type: 'CHART_TYPE_BAR',
      categories: ['Mon', 'Tue'],
      series: [{ key: 'steps', label: 'Steps', values: [9000, 8000] }],
    },
    {
      id: 'sleep',
      title: 'Sleep stages, last night',
      type: 'CHART_TYPE_PIE',
      categories: ['Deep', 'Light'],
      series: [
        { key: 'deep', label: 'Deep', values: [40] },
        { key: 'light', label: 'Light', values: [60] },
      ],
    },
  ],
};

function appWith(getHealthCharts) {
  return buildApp({
    getRecommendations: async () => ({ recommendations: [], statuses: [] }),
    getHealthCharts,
  });
}

describe('POST /api/charts', () => {
  it('returns charts packed positionally, XSSI-prefixed', async () => {
    const app = appWith(async () => FAKE_CHARTS);
    const res = await apiPost(app, '/api/charts').send(VALID_BODY);

    expect(res.status).to.equal(200);
    const body = stripXssi(res.body);

    const charts = body[SLOTS.HealthChartsResponse.CHARTS];
    expect(charts).to.have.length(2);

    const steps = charts[0];
    expect(steps[SLOTS.Chart.ID]).to.equal('steps');
    expect(steps[SLOTS.Chart.TITLE]).to.equal('Steps, last 7 days');
    expect(steps[SLOTS.Chart.TYPE]).to.equal(1);
    expect(steps[SLOTS.Chart.CATEGORIES]).to.deep.equal(['Mon', 'Tue']);

    const series = steps[SLOTS.Chart.SERIES][0];
    expect(series[SLOTS.Series.KEY]).to.equal('steps');
    expect(series[SLOTS.Series.LABEL]).to.equal('Steps');
    expect(series[SLOTS.Series.VALUES]).to.deep.equal([9000, 8000]);
  });

  it('maps enum names to numbers, whichever form the loader yields', () => {
    const { chartTypeNumber } = require('../src/dto');
    expect(chartTypeNumber('CHART_TYPE_BAR')).to.equal(1);
    expect(chartTypeNumber('CHART_TYPE_PIE')).to.equal(2);
    expect(chartTypeNumber('CHART_TYPE_GROUPED_BAR')).to.equal(3);
    expect(chartTypeNumber(3)).to.equal(3);
    // Anything unrecognised is UNSPECIFIED, never NaN — NaN serialises to
    // null and reaches the client as a chart with no type at all.
    expect(chartTypeNumber('CHART_TYPE_FUTURE')).to.equal(0);
    expect(chartTypeNumber(undefined)).to.equal(0);
  });

  // No object keys may reach the browser: ADVANCED compilation renames
  // property accesses but leaves JSON string keys untouched, which is the
  // whole reason this wire format is positional.
  it('sends no property names on the wire', async () => {
    const app = appWith(async () => FAKE_CHARTS);
    const res = await apiPost(app, '/api/charts').send(VALID_BODY);
    const raw = res.body.slice(XSSI_PREFIX.length);

    for (const name of ['"id"', '"title"', '"categories"', '"series"', '"key"', '"values"']) {
      expect(raw, `wire carried the property name ${name}`).to.not.contain(name);
    }
  });

  it('rejects measurements the recommendations route would also reject', async () => {
    const app = appWith(async () => FAKE_CHARTS);
    for (const body of [
      {},
      { heightCm: 0, weightKg: 70 },
      { heightCm: 175, weightKg: -5 },
      { heightCm: 'tall', weightKg: 70 },
    ]) {
      const res = await apiPost(app, '/api/charts').send(body);
      expect(res.status, JSON.stringify(body)).to.equal(400);
      expect(stripXssi(res.body).error).to.equal('invalid_measurements');
    }
  });

  it('returns 502 when app-server is unreachable', async () => {
    const app = appWith(async () => { throw new Error('upstream down'); });
    const res = await apiPost(app, '/api/charts').send(VALID_BODY);

    expect(res.status).to.equal(502);
    expect(stripXssi(res.body).error).to.equal('upstream_unavailable');
    // The failure must not leak the message or a stack.
    expect(res.body).to.not.contain('upstream down');
  });

  it('serves the SPA shell for GET /charts so a reload or bookmark works', async () => {
    const app = appWith(async () => FAKE_CHARTS);
    const res = await request(app).get('/charts');
    expect(res.status).to.equal(200);
  });

  // The real wiring, not a stub of it. buildApp is what production calls,
  // and an earlier revision passed getRecommendations without
  // getHealthCharts — the route then called undefined at runtime while every
  // stub-based test still passed.
  it('is wired into the app that production actually builds', () => {
    const { getRecommendations, getHealthCharts } = require('../src/grpc-client');
    expect(getRecommendations, 'grpc-client exports getRecommendations').to.be.a('function');
    expect(getHealthCharts, 'grpc-client exports getHealthCharts').to.be.a('function');

    const src = require('fs').readFileSync(
      require('path').join(__dirname, '../src/server.js'), 'utf8');
    const call = src.match(/buildApp\(\{([^}]*)\}\)/g) || [];
    for (const c of call) {
      expect(c, 'buildApp call site omits getHealthCharts').to.contain('getHealthCharts');
    }
  });
});
