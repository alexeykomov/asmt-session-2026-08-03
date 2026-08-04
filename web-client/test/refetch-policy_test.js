'use strict';

const {assert} = require('chai');
const {loadRefetchPolicy} = require('./helpers/load-refetch-policy');

describe('refetch policy', () => {
  let shouldFetch;
  before(() => {
    shouldFetch = loadRefetchPolicy();
  });

  it('fetches on first visit even when clean', () => {
    assert.isTrue(shouldFetch(false, false));
  });

  it('does not refetch on a revisit with no changes', () => {
    assert.isFalse(shouldFetch(true, false),
        'refetching on every tab switch burns a vendor call');
  });

  it('refetches on a revisit after a change', () => {
    assert.isTrue(shouldFetch(true, true),
        'this is the demo beat: change profile, return, see the effect');
  });

  it('fetches on first visit when already dirty', () => {
    assert.isTrue(shouldFetch(false, true));
  });
});
