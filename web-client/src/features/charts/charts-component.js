goog.provide('funwithactivity.charts.ChartsComponent');

goog.require('funwithactivity.app.AppState');
goog.require('funwithactivity.app.LastCharts');
goog.require('funwithactivity.charts.render');
goog.require('funwithactivity.components.chartsScreen');
goog.require('funwithactivity.dto.Chart');
goog.require('funwithactivity.dto.HealthChartsResponse');
goog.require('funwithactivity.features.recommendations.api');
goog.require('funwithactivity.recs.shouldFetch');
goog.require('funwithactivity.render');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.events');
goog.require('goog.events.EventType');
goog.require('goog.ui.Component');


/**
 * Charts screen: fetches health charts for the profile in AppState and draws
 * them, using the same visit policy the Recommendations screen uses.
 *
 * This component owns fetching, caching and mounting. It owns no drawing —
 * funwithactivity.charts.render turns a Chart into an element, and
 * funwithactivity.charts.geometry does the arithmetic. That split is what
 * makes the geometry assertable without a browser, which matters because a
 * mis-scaled chart still looks like a chart and will not announce itself the
 * way a blank screen does.
 * @param {!funwithactivity.app.AppState} state
 * @constructor
 * @extends {goog.ui.Component}
 */
funwithactivity.charts.ChartsComponent = function(state) {
  funwithactivity.charts.ChartsComponent.base(this, 'constructor');

  /** @private @const {!funwithactivity.app.AppState} */
  this.state_ = state;

  /** @private {?goog.events.Key} */
  this.refreshKey_ = null;
};
goog.inherits(funwithactivity.charts.ChartsComponent, goog.ui.Component);


/**
 * Whether a fetch has completed at least once this page session. Static for
 * the same reason funwithactivity.recs.RecsComponent.hasFetched_ is: Shell
 * disposes and rebuilds the screen on every navigation, so an instance field
 * would read false on every revisit and the visit policy would never trigger
 * outside unit tests.
 * @private {boolean}
 */
funwithactivity.charts.ChartsComponent.hasFetched_ = false;


/** @override */
funwithactivity.charts.ChartsComponent.prototype.createDom = function() {
  const el = goog.dom.createDom(
      goog.dom.TagName.DIV, {'class': 'fwa-screen-charts screen-container'});
  this.setElementInternal(el);
  funwithactivity.render.element(
      el, funwithactivity.components.chartsScreen.screen, {});
};


/** @override */
funwithactivity.charts.ChartsComponent.prototype.enterDocument = function() {
  funwithactivity.charts.ChartsComponent.base(this, 'enterDocument');

  const refreshBtn = goog.dom.getElement('charts-refresh');
  if (refreshBtn) {
    this.refreshKey_ = goog.events.listen(refreshBtn,
        goog.events.EventType.CLICK, this.handleRefreshClick_, false, this);
  }

  this.maybeFetch_(false);
};


/** @private */
funwithactivity.charts.ChartsComponent.prototype.handleRefreshClick_ =
    function() {
  this.maybeFetch_(true);
};


/**
 * @param {boolean} force When true, fetches regardless of the visit policy.
 * @private
 */
funwithactivity.charts.ChartsComponent.prototype.maybeFetch_ = function(force) {
  // Charts are seeded from the measurements, so the same guard the
  // Recommendations screen applies holds here: without height and weight,
  // web-proxy answers 400 and the screen would open on an error banner
  // describing a user's unfinished profile as a system failure.
  if (!this.hasUsableMeasurements_()) {
    this.renderNeedsMeasurements_();
    return;
  }

  if (!force && !funwithactivity.recs.shouldFetch(
      funwithactivity.charts.ChartsComponent.hasFetched_,
      this.state_.isDirty())) {
    this.renderFromCache_();
    return;
  }
  this.fetch_();
};


/**
 * Mirrors RecsComponent.prototype.hasUsableMeasurements_ and web-proxy's
 * parseMeasurements: height and weight must both be finite and positive.
 * Birth date is deliberately not required.
 * @return {boolean}
 * @private
 */
funwithactivity.charts.ChartsComponent.prototype.hasUsableMeasurements_ =
    function() {
  const m = this.state_.getMeasurements();
  return isFinite(m.heightCm) && m.heightCm > 0 &&
      isFinite(m.weightKg) && m.weightKg > 0;
};


/** @private */
funwithactivity.charts.ChartsComponent.prototype.fetch_ = function() {
  const m = this.state_.getMeasurements();
  // Every key is a quoted string literal: this object goes straight to
  // JSON.stringify, and ADVANCED compilation renames unquoted keys, which
  // would silently produce a body web-proxy rejects as invalid measurements.
  funwithactivity.features.recommendations.api.fetchCharts({
    'heightCm': m.heightCm,
    'weightKg': m.weightKg,
    'birthDateUnix': m.birthDateUnix,
  }).then(
      goog.bind(this.renderSuccess_, this),
      goog.bind(this.renderError_, this));
};


/**
 * @param {!funwithactivity.dto.HealthChartsResponse} response
 * @private
 */
funwithactivity.charts.ChartsComponent.prototype.renderSuccess_ = function(
    response) {
  funwithactivity.charts.ChartsComponent.hasFetched_ = true;
  // Deliberately does NOT call state_.markClean(). The dirty flag means "the
  // profile changed since the last recommendations fetch", and the
  // Recommendations screen owns clearing it. Clearing it here would let a
  // visit to Charts silently consume the refetch that Recommendations was
  // going to perform, so editing the profile and returning to Recs would
  // show stale results.
  funwithactivity.app.LastCharts.set(response.charts);
  this.renderCharts_(response.charts);
  this.clearBanner_();
};


/** @private */
funwithactivity.charts.ChartsComponent.prototype.renderFromCache_ = function() {
  const cached = funwithactivity.app.LastCharts.get();
  if (cached.length === 0) return;
  this.renderCharts_(cached);
  this.clearBanner_();
};


/**
 * @param {!Array<!funwithactivity.dto.Chart>} charts
 * @private
 */
funwithactivity.charts.ChartsComponent.prototype.renderCharts_ = function(
    charts) {
  const mount = goog.dom.getElement('charts-mount');
  if (!mount) return;
  goog.dom.removeChildren(mount);

  if (charts.length === 0) {
    mount.appendChild(goog.dom.createDom(
        goog.dom.TagName.P, 'chart-empty', 'No charts returned.'));
    return;
  }
  for (let i = 0; i < charts.length; i++) {
    mount.appendChild(funwithactivity.charts.render.chart(charts[i]));
  }
};


/**
 * A transport failure must not look like an empty chart set: an empty chart
 * and a failed request mean entirely different things to whoever is looking
 * at the screen, and rendering both as "nothing here" hides an outage.
 * @private
 */
funwithactivity.charts.ChartsComponent.prototype.renderError_ = function() {
  const banner = goog.dom.getElement('charts-banner');
  if (banner) {
    goog.dom.removeChildren(banner);
    banner.appendChild(goog.dom.createDom(
        goog.dom.TagName.DIV, 'banner banner-error',
        'Unable to load charts — please try again.'));
  }
  const mount = goog.dom.getElement('charts-mount');
  if (mount) goog.dom.removeChildren(mount);
};


/** @private */
funwithactivity.charts.ChartsComponent.prototype.renderNeedsMeasurements_ =
    function() {
  this.clearBanner_();
  const mount = goog.dom.getElement('charts-mount');
  if (!mount) return;
  goog.dom.removeChildren(mount);
  mount.appendChild(goog.dom.createDom(
      goog.dom.TagName.P, 'chart-empty',
      'Add your height and weight in Profile to see charts.'));
};


/** @private */
funwithactivity.charts.ChartsComponent.prototype.clearBanner_ = function() {
  const banner = goog.dom.getElement('charts-banner');
  if (banner) goog.dom.removeChildren(banner);
};


/** @override */
funwithactivity.charts.ChartsComponent.prototype.disposeInternal = function() {
  if (this.refreshKey_) {
    goog.events.unlistenByKey(this.refreshKey_);
    this.refreshKey_ = null;
  }
  funwithactivity.charts.ChartsComponent.base(this, 'disposeInternal');
};
