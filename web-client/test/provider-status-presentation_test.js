'use strict';

const {assert} = require('chai');
const {loadClassifier} = require('./helpers/load-dtos');

describe('provider status classification', () => {
  let classify, shortReason, ProviderStatus;
  before(() => { ({classify, shortReason, ProviderStatus} = loadClassifier()); });

  it('ok status classifies as ok', () => {
    assert.equal(
        classify(new ProviderStatus('service1', true, false, '', 3, 40)),
        'ok');
  });

  it('genuine failure classifies as degraded', () => {
    assert.equal(
        classify(new ProviderStatus('service1', false, false, 'boom', 0, 2001)),
        'degraded');
  });

  it('skipped classifies as skipped even though error is populated', () => {
    // This is the case that regresses. Skipped statuses carry explanatory text
    // in `error`, so any implementation that tests error before skipped will
    // return 'degraded' here and render data minimisation as an outage.
    assert.equal(
        classify(new ProviderStatus(
            'service2', false, true, 'required measurements not supplied', 0, 0)),
        'skipped');
  });

  it('skipped wins over failure when both flags could apply', () => {
    assert.equal(
        classify(new ProviderStatus('service2', false, true, 'anything', 0, 0)),
        'skipped');
  });
});

describe('provider status shortReason', () => {
  let shortReason, ProviderStatus;
  before(() => { ({shortReason, ProviderStatus} = loadClassifier()); });

  it('ok status has no reason to show', () => {
    assert.equal(
        shortReason(new ProviderStatus('service1', true, false, '', 3, 40)), '');
  });

  it('skipped never surfaces the raw "required measurements" text', () => {
    assert.equal(
        shortReason(new ProviderStatus(
            'service2', false, true, 'required measurements not supplied', 0, 0)),
        'skipped — no birth date');
  });

  it('a deadline-exceeded failure never leaks the raw vendor URL', () => {
    const raw = 'service1: [0] Post "https://a2da22.lambda-url.eu-central-1' +
        '.on.aws/services/service1": context deadline exceeded (transient)';
    assert.equal(
        shortReason(new ProviderStatus('service1', false, false, raw, 0, 2001)),
        'timed out');
  });

  it('the fault-injected timeout mode (bare ctx.Err() text) also reads as timed out', () => {
    assert.equal(
        shortReason(new ProviderStatus(
            'service1', false, false, 'context deadline exceeded', 0, 2001)),
        'timed out');
  });

  it('any other genuine failure text falls back to a generic reason', () => {
    assert.equal(
        shortReason(new ProviderStatus(
            'service1', false, false,
            'service1: [503] simulated provider outage (transient)', 0, 0)),
        'unavailable');
  });
});
