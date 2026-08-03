'use strict';

const {assert} = require('chai');
const {loadClosureDtos} = require('./helpers/load-dtos');

describe('DTOs', () => {
  let dto;
  before(() => { dto = loadClosureDtos(); });

  it('Recommendation round-trips through the wire format', () => {
    const r = new dto.Recommendation('Walk more', 'Do it daily', 'service1', 0.42);
    const back = dto.Recommendation.fromJSON(r.toJSON());
    assert.equal(back.title, 'Walk more');
    assert.equal(back.details, 'Do it daily');
    assert.equal(back.source, 'service1');
    assert.equal(back.score, 0.42);
  });

  it('Recommendation packs to a positional array in slot order', () => {
    const r = new dto.Recommendation('T', 'D', 'S', 0.5);
    assert.deepEqual(r.toJSON(), ['T', 'D', 'S', 0.5]);
  });

  it('Recommendation.fromJSON tolerates a truncated array', () => {
    const back = dto.Recommendation.fromJSON(['T']);
    assert.equal(back.title, 'T');
    assert.equal(back.details, '');
    assert.equal(back.source, '');
    assert.equal(back.score, 0);
  });

  it('ProviderStatus packs to a positional array in slot order', () => {
    // Every slot gets a distinct, non-interchangeable value so that
    // swapping any two fields in the toJSON() array literal fails this
    // assertion. count and latencyMs in particular must differ from each
    // other and from everything else, or a swap between them is
    // undetectable. error is non-empty while skipped is true — that is
    // the exact combination this project has shipped four defects on.
    const s = new dto.ProviderStatus('service2', false, true, 'no birth date', 3, 77);
    assert.deepEqual(s.toJSON(), ['service2', 0, 1, 'no birth date', 3, 77]);
  });

  it('ProviderStatus round-trips all six fields', () => {
    const s = new dto.ProviderStatus('service2', false, true, 'no birth date', 3, 77);
    const back = dto.ProviderStatus.fromJSON(s.toJSON());
    assert.equal(back.name, 'service2');
    assert.strictEqual(back.ok, false);
    assert.strictEqual(back.skipped, true);
    assert.equal(back.error, 'no birth date');
    assert.equal(back.count, 3);
    assert.equal(back.latencyMs, 77);
  });

  it('ProviderStatus.fromJSON tolerates a truncated array', () => {
    const back = dto.ProviderStatus.fromJSON(['service2']);
    assert.equal(back.name, 'service2');
    assert.strictEqual(back.ok, false);
    assert.strictEqual(back.skipped, false);
    assert.equal(back.error, '');
    assert.equal(back.count, 0);
    assert.equal(back.latencyMs, 0);
  });

  it('slot indices are the documented ones — reordering must fail here', () => {
    assert.deepEqual(dto.Recommendation.Fields,
        {TITLE: 0, DETAILS: 1, SOURCE: 2, SCORE: 3});
    assert.deepEqual(dto.ProviderStatus.Fields,
        {NAME: 0, OK: 1, SKIPPED: 2, ERROR: 3, COUNT: 4, LATENCY_MS: 5});
    assert.deepEqual(dto.RecommendationsResponse.Fields,
        {RECOMMENDATIONS: 0, STATUSES: 1});
  });

  it('RecommendationsResponse packs to a positional array in slot order', () => {
    // Full deepEqual of the whole envelope, not just a spot-check of one
    // nested field: a RECOMMENDATIONS/STATUSES slot swap would put a
    // 6-slot ProviderStatus array where a 4-slot Recommendation array is
    // expected (and vice versa), which this catches on shape alone.
    const resp = new dto.RecommendationsResponse(
        [new dto.Recommendation('T', '', 'service1', 0.9)],
        [new dto.ProviderStatus('service1', true, false, 'why', 1, 30)]);
    assert.deepEqual(resp.toJSON(), [
      [['T', '', 'service1', 0.9]],
      [['service1', 1, 0, 'why', 1, 30]],
    ]);
  });

  it('RecommendationsResponse.fromJSON tolerates a truncated array', () => {
    const back = dto.RecommendationsResponse.fromJSON([]);
    assert.deepEqual(back.recommendations, []);
    assert.deepEqual(back.statuses, []);
  });

  it('RecommendationsResponse round-trips to real DTO instances', () => {
    const resp = new dto.RecommendationsResponse(
        [new dto.Recommendation('T', '', 'service1', 0.9)],
        [new dto.ProviderStatus('service1', true, false, '', 1, 30)]);
    const back = dto.RecommendationsResponse.fromJSON(resp.toJSON());
    assert.instanceOf(back.recommendations[0], dto.Recommendation);
    assert.equal(back.recommendations[0].title, 'T');
    assert.strictEqual(back.statuses[0].ok, true);
  });
});
