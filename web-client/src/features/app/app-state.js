goog.provide('funwithactivity.app.AppState');

goog.require('goog.events.EventTarget');


/**
 * Shared client state: the measurements the Profile screen edits and the
 * fault settings its DEVELOPER section toggles.
 *
 * The dirty flag exists so the Recs screen can refetch on becoming visible
 * ONLY when something actually changed. Refetching unconditionally would
 * spend a vendor call on every tab switch, and these vendors are flaky
 * cold-start Lambdas; never refetching would make the demo silently lie —
 * the presenter changes a value, returns, and the screen does not move.
 * @constructor
 * @extends {goog.events.EventTarget}
 */
funwithactivity.app.AppState = function() {
  funwithactivity.app.AppState.base(this, 'constructor');

  /**
   * Height and weight start at plausible defaults — matching iOS
   * (FWAAppState.m) and Android (AppState.java) — so the app opens on real
   * recommendations rather than an empty state. Birth date deliberately
   * does NOT: see below.
   * @private {number}
   */
  this.heightCm_ = funwithactivity.app.AppState.DEFAULT_HEIGHT_CM;
  /** @private {number} */
  this.weightKg_ = funwithactivity.app.AppState.DEFAULT_WEIGHT_KG;
  /**
   * Unix seconds, or 0 for "not supplied" — a deliberate GDPR Art. 5(1)(c)
   * data-minimisation choice, matching the wire convention web-proxy uses.
   *
   * Unset by default, and that default is load-bearing rather than
   * incidental: the app opens with service2 already skipped, so supplying
   * an age visibly UNLOCKS a provider instead of withholding one. Stating
   * the minimisation rule that way round — you get more by sharing more,
   * and the product works either way — reads as a product decision rather
   * than as a degraded mode.
   * @private {number}
   */
  this.birthDateUnix_ = 0;
  /** @private {!Object<string,string>} */
  this.faults_ = {};
  /** @private {boolean} */
  this.dirty_ = false;
};
goog.inherits(funwithactivity.app.AppState, goog.events.EventTarget);


/**
 * Default measurements, kept identical to iOS FWAAppState.m and Android
 * AppState.java so all three clients open on the same result set.
 * @const {number}
 */
funwithactivity.app.AppState.DEFAULT_HEIGHT_CM = 175;


/** @const {number} */
funwithactivity.app.AppState.DEFAULT_WEIGHT_KG = 70;


/**
 * Where the birth-date picker opens when nothing is set. The field itself
 * stays unset — this only positions the wheel somewhere plausible instead
 * of at an arbitrary epoch, so picking a date on stage is one gesture
 * rather than thirty years of scrolling.
 * @const {string}
 */
funwithactivity.app.AppState.PICKER_DEFAULT_DATE = '1983-05-29';


/** @const {string} */
funwithactivity.app.AppState.CHANGE = 'app-state-change';


/** @return {{heightCm: number, weightKg: number, birthDateUnix: number}} */
funwithactivity.app.AppState.prototype.getMeasurements = function() {
  return {
    heightCm: this.heightCm_,
    weightKg: this.weightKg_,
    birthDateUnix: this.birthDateUnix_
  };
};


/**
 * Writes measurements, marking state dirty only if a value actually
 * changed. An unchanged write must not schedule a refetch — otherwise
 * merely visiting Profile and leaving would burn a vendor call.
 * @param {number} heightCm
 * @param {number} weightKg
 * @param {number} birthDateUnix
 */
funwithactivity.app.AppState.prototype.setMeasurements = function(
    heightCm, weightKg, birthDateUnix) {
  if (this.heightCm_ === heightCm && this.weightKg_ === weightKg &&
      this.birthDateUnix_ === birthDateUnix) {
    return;
  }
  this.heightCm_ = heightCm;
  this.weightKg_ = weightKg;
  this.birthDateUnix_ = birthDateUnix;
  this.touch_();
};


/** @return {!Object<string,string>} */
funwithactivity.app.AppState.prototype.getFaults = function() {
  const copy = {};
  for (const k in this.faults_) copy[k] = this.faults_[k];
  return copy;
};


/**
 * @param {string} provider
 * @param {string} mode
 */
funwithactivity.app.AppState.prototype.setFault = function(provider, mode) {
  if (this.faults_[provider] === mode) return;
  this.faults_[provider] = mode;
  this.touch_();
};


/** @param {string} provider */
funwithactivity.app.AppState.prototype.clearFault = function(provider) {
  if (!(provider in this.faults_)) return;
  delete this.faults_[provider];
  this.touch_();
};


/** @return {boolean} */
funwithactivity.app.AppState.prototype.isDirty = function() {
  return this.dirty_;
};


/** Called by the Recs screen once it has fetched against current state. */
funwithactivity.app.AppState.prototype.markClean = function() {
  this.dirty_ = false;
};


/** @private */
funwithactivity.app.AppState.prototype.touch_ = function() {
  this.dirty_ = true;
  this.dispatchEvent(funwithactivity.app.AppState.CHANGE);
};
