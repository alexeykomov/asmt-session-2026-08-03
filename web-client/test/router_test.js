'use strict';

const {assert} = require('chai');
const {loadRouter} = require('./helpers/load-router');

describe('Router.normalize', () => {
  let normalize;
  before(() => { normalize = loadRouter().normalize; });

  it('maps / to recs', () => assert.equal(normalize('/'), 'recs'));
  it('maps /recs to recs', () => assert.equal(normalize('/recs'), 'recs'));
  it('maps /sources to sources', () => assert.equal(normalize('/sources'), 'sources'));
  it('maps /profile to profile', () => assert.equal(normalize('/profile'), 'profile'));
  it('maps /sources/add to add-source', () => assert.equal(normalize('/sources/add'), 'add-source'));
  it('tolerates a trailing slash', () => assert.equal(normalize('/profile/'), 'profile'));
  it('falls back to recs for an unknown path', () => assert.equal(normalize('/nope'), 'recs'));
  it('falls back to recs for the empty string', () => assert.equal(normalize(''), 'recs'));

  it('maps /sources/service1 to sources/service1', () =>
      assert.equal(normalize('/sources/service1'), 'sources/service1'));
  it('maps /sources/service2-stub to sources/service2-stub', () =>
      assert.equal(normalize('/sources/service2-stub'), 'sources/service2-stub'));
  it('tolerates a trailing slash on a source detail path', () =>
      assert.equal(normalize('/sources/service1/'), 'sources/service1'));
  it('still maps /sources/add to add-source, not a source named "add"', () =>
      assert.equal(normalize('/sources/add'), 'add-source'));
  it('falls back to recs for a source detail path with an extra segment', () =>
      assert.equal(normalize('/sources/service1/extra'), 'recs'));
});
