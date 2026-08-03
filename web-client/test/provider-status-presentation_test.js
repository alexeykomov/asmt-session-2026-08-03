'use strict';

const {assert} = require('chai');
const {loadClassifier} = require('./helpers/load-dtos');

describe('provider status classification', () => {
  let classify, ProviderStatus;
  before(() => { ({classify, ProviderStatus} = loadClassifier()); });

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
