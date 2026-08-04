'use strict';

const {assert} = require('chai');
const {loadAppState} = require('./helpers/load-app-state');

describe('AppState', () => {
  let AppState;
  before(() => {
    AppState = loadAppState();
  });

  it('starts clean', () => {
    assert.isFalse(new AppState().isDirty());
  });

  it('becomes dirty when measurements change', () => {
    const s = new AppState();
    s.setMeasurements(184, 84, 668995200);
    assert.isTrue(s.isDirty());
  });

  it('becomes dirty when a fault is set', () => {
    const s = new AppState();
    s.setFault('service1', 'error');
    assert.isTrue(s.isDirty());
  });

  it('markClean clears the flag', () => {
    const s = new AppState();
    s.setMeasurements(184, 84, 0);
    s.markClean();
    assert.isFalse(s.isDirty());
  });

  it('setting the same measurements twice does not re-dirty', () => {
    const s = new AppState();
    s.setMeasurements(184, 84, 0);
    s.markClean();
    s.setMeasurements(184, 84, 0);
    assert.isFalse(s.isDirty(),
        'an unchanged write must not trigger a refetch');
  });

  it('clearFault removes the entry entirely', () => {
    const s = new AppState();
    s.setFault('service1', 'error');
    s.clearFault('service1');
    assert.deepEqual(s.getFaults(), {});
  });

  it('birthDateUnix 0 means not supplied and round-trips', () => {
    const s = new AppState();
    s.setMeasurements(184, 84, 0);
    assert.equal(s.getMeasurements().birthDateUnix, 0);
  });
});
