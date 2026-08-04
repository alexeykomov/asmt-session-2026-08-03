'use strict';

const {assert} = require('chai');
const {loadBannerMessages} = require('./helpers/load-banner-messages');

describe('recommendations banner messages', () => {
  let bannerMessages, ProviderStatus;
  before(() => {
    ({bannerMessages, ProviderStatus} = loadBannerMessages());
  });

  const ok = (name) => new ProviderStatus(name, true, false, '', 3, 40);
  const degraded = (name) =>
    new ProviderStatus(name, false, false, 'boom', 0, 2001);
  const skipped = (name) => new ProviderStatus(
      name, false, true, 'required measurements not supplied', 0, 0);

  it('some results survive: unchanged per-provider "partial results" text', () => {
    const messages = bannerMessages([degraded('service1'), ok('service2')], true);
    assert.deepEqual(messages, [{
      text: 'service1 unavailable — showing partial results',
      className: 'recs-banner-degraded',
    }]);
  });

  it('some results survive: unchanged per-provider skipped text', () => {
    const messages = bannerMessages([skipped('service2'), ok('service1')], true);
    assert.deepEqual(messages, [{
      text: 'service2 skipped — required measurements not supplied',
      className: 'recs-banner-skipped',
    }]);
  });

  it('all degraded, zero results: one failure message, never "partial results"', () => {
    const messages =
        bannerMessages([degraded('service1'), degraded('service2')], false);
    assert.deepEqual(messages, [{
      text: 'No recommendations available — all providers are unavailable',
      className: 'recs-banner-degraded',
    }]);
    assert.notInclude(messages[0].text, 'partial results');
  });

  it('all skipped, zero results: one informational message, styled blue', () => {
    const messages =
        bannerMessages([skipped('service1'), skipped('service2')], false);
    assert.deepEqual(messages, [{
      text: 'No recommendations — no provider had the data it needs',
      className: 'recs-banner-skipped',
    }]);
  });

  it('mixed skipped + degraded, zero results: states both, never claims partial results, skipped stays blue', () => {
    const messages =
        bannerMessages([degraded('service1'), skipped('service2')], false);
    assert.lengthOf(messages, 2);

    const forFailed = messages.find((m) => m.text.indexOf('service1') === 0);
    assert.equal(forFailed.text, 'service1 unavailable');
    assert.equal(forFailed.className, 'recs-banner-degraded');
    assert.notInclude(forFailed.text, 'partial results');

    const forSkipped = messages.find((m) => m.text.indexOf('service2') === 0);
    assert.equal(
        forSkipped.text,
        'service2 skipped — required measurements not supplied');
    // Load-bearing: the skipped provider's own message must stay styled
    // as informational, never folded into the degraded/red styling — see
    // the doc on funwithactivity.recs.bannerMessages.
    assert.equal(forSkipped.className, 'recs-banner-skipped');
  });

  it('everything ok: no banner at all', () => {
    assert.deepEqual(bannerMessages([ok('service1'), ok('service2')], true), []);
  });
});
