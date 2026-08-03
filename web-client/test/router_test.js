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
});
