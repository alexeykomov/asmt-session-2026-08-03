goog.provide('funwithactivity.sources.SourcesComponent');

goog.require('funwithactivity.app.AppState');
goog.require('funwithactivity.app.LastStatuses');
goog.require('funwithactivity.app.Router');
goog.require('funwithactivity.components.sourcesScreen');
goog.require('funwithactivity.dto.ProviderStatus');
goog.require('funwithactivity.features.recommendations.api');
goog.require('funwithactivity.features.recommendations.classify');
goog.require('funwithactivity.features.recommendations.shortReason');
goog.require('funwithactivity.render');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.dom.classlist');
goog.require('goog.events');
goog.require('goog.events.EventType');
goog.require('goog.ui.Button');
goog.require('goog.ui.Component');


/**
 * Sources screen: lists both providers with status and latency from the
 * most recent POST /api/recommendations response's `statuses[]`
 * (funwithactivity.app.LastStatuses), and a `+` control that routes to
 * the stubbed add-source form.
 *
 * Constructed fresh on every navigation to /sources (funwithactivity.app.
 * Shell disposes and rebuilds the mounted screen on each route change),
 * so it always reads whatever the LastStatuses cache holds RIGHT NOW
 * rather than assuming a prior visit populated it — see enterDocument.
 * @param {!funwithactivity.app.AppState} state
 * @param {!funwithactivity.app.Router} router
 * @constructor
 * @extends {goog.ui.Component}
 */
funwithactivity.sources.SourcesComponent = function(state, router) {
  funwithactivity.sources.SourcesComponent.base(this, 'constructor');

  /** @private @const {!funwithactivity.app.AppState} */
  this.state_ = state;

  /** @private @const {!funwithactivity.app.Router} */
  this.router_ = router;

  /** @private {?goog.ui.Button} */
  this.addButton_ = null;

  /** @private {?goog.events.Key} */
  this.addButtonKey_ = null;

  /** @private {?goog.events.Key} */
  this.rowClickKey_ = null;
};
goog.inherits(funwithactivity.sources.SourcesComponent, goog.ui.Component);


/** @override */
funwithactivity.sources.SourcesComponent.prototype.createDom = function() {
  const el = goog.dom.createDom(
      goog.dom.TagName.DIV, {'class': 'fwa-screen-sources screen-container'});
  this.setElementInternal(el);
  funwithactivity.render.element(
      el, funwithactivity.components.sourcesScreen.screen, {});
};


/** @override */
funwithactivity.sources.SourcesComponent.prototype.enterDocument = function() {
  funwithactivity.sources.SourcesComponent.base(this, 'enterDocument');

  const addEl = goog.dom.getElement('sources-add');
  if (addEl) {
    this.addButton_ = new goog.ui.Button(null);
    this.addChild(this.addButton_);
    this.addButton_.decorate(addEl);
    this.addButtonKey_ = goog.events.listen(this.addButton_,
        goog.ui.Component.EventType.ACTION, this.handleAddClick_, false,
        this);
  }

  const mount = goog.dom.getElement('sources-list-mount');
  if (mount) {
    this.rowClickKey_ = goog.events.listen(
        mount, goog.events.EventType.CLICK, this.handleRowClick_, false,
        this);
  }

  const cached = funwithactivity.app.LastStatuses.get();
  if (cached.length) {
    this.renderList_(cached);
  } else {
    // Nothing fetched yet this session (e.g. the presenter opened Sources
    // before ever visiting Recommendations) — fetch once ourselves so the
    // screen still shows real data instead of staying permanently empty.
    this.fetchAndRender_();
  }
};


/** @private */
funwithactivity.sources.SourcesComponent.prototype.handleAddClick_ =
    function() {
  this.router_.go('/sources/add');
};


/**
 * Intercepts clicks on a `.sources-row` anchor and routes through
 * router.go() instead of a full navigation, matching the same pattern
 * funwithactivity.app.Shell used for the old hand-rolled tab bar and still
 * needs here since these rows are plain anchors, not goog.ui controls —
 * each row is only ever a link to a detail screen, never itself
 * interactive beyond that.
 * @param {!goog.events.BrowserEvent} e
 * @private
 */
funwithactivity.sources.SourcesComponent.prototype.handleRowClick_ =
    function(e) {
  const anchor = goog.dom.getAncestor(/** @type {?Node} */ (e.target),
      function(node) {
        return node.nodeType == 1 &&
            goog.dom.classlist.contains(/** @type {!Element} */ (node),
                'sources-row');
      }, true);
  if (!anchor) return;
  e.preventDefault();
  this.router_.go(anchor.getAttribute('href'));
};


/**
 * Mirrors RecsComponent.prototype.hasUsableMeasurements_: height and
 * weight must both be finite and positive before a fetch is worth
 * attempting (web-proxy rejects a non-positive measurement with 400
 * invalid_measurements). Birth date is deliberately not required.
 * @return {boolean}
 * @private
 */
funwithactivity.sources.SourcesComponent.prototype.hasUsableMeasurements_ =
    function() {
  const m = this.state_.getMeasurements();
  return isFinite(m.heightCm) && m.heightCm > 0 &&
      isFinite(m.weightKg) && m.weightKg > 0;
};


/** @private */
funwithactivity.sources.SourcesComponent.prototype.fetchAndRender_ =
    function() {
  if (!this.hasUsableMeasurements_()) {
    this.renderMessage_(
        'Add your height and weight in Profile to see source status.');
    return;
  }

  const measurements = this.state_.getMeasurements();
  // Same wire shape as RecsComponent.prototype.fetch_ — every key MUST be
  // a quoted string literal here (see that method's identical note) or
  // ADVANCED renaming silently breaks web-proxy's parseMeasurements.
  const payload = {
    'heightCm': measurements.heightCm,
    'weightKg': measurements.weightKg,
    'birthDateUnix': measurements.birthDateUnix,
    'faults': this.state_.getFaults(),
  };
  funwithactivity.features.recommendations.api.fetch(payload).then(
      goog.bind(this.handleFetchSuccess_, this),
      goog.bind(this.handleFetchError_, this));
};


/**
 * @param {!funwithactivity.dto.RecommendationsResponse} response
 * @private
 */
funwithactivity.sources.SourcesComponent.prototype.handleFetchSuccess_ =
    function(response) {
  funwithactivity.app.LastStatuses.set(response.statuses);
  this.renderList_(response.statuses);
};


/**
 * @param {*} err
 * @private
 */
funwithactivity.sources.SourcesComponent.prototype.handleFetchError_ =
    function(err) {
  this.renderMessage_('Unable to load source status — please try again.');
};


/**
 * @param {!Array<!funwithactivity.dto.ProviderStatus>} statuses
 * @private
 */
funwithactivity.sources.SourcesComponent.prototype.renderList_ = function(
    statuses) {
  const mount = goog.dom.getElement('sources-list-mount');
  if (!mount) return;
  funwithactivity.render.element(
      mount, funwithactivity.components.sourcesScreen.list,
      {rows: statuses.map(
          funwithactivity.sources.SourcesComponent.toRow_)});
};


/**
 * @param {string} message
 * @private
 */
funwithactivity.sources.SourcesComponent.prototype.renderMessage_ = function(
    message) {
  const mount = goog.dom.getElement('sources-list-mount');
  if (!mount) return;
  goog.dom.setTextContent(mount, message);
};


/**
 * Builds one list-row view model from a ProviderStatus. Never carries
 * `status.error` through — see funwithactivity.features.recommendations.
 * shortReason's doc for why the list must not print it.
 * @param {!funwithactivity.dto.ProviderStatus} status
 * @return {{name: string, href: string, statusClass: string,
 *           statusLabel: string, reason: string, latencyDisplay: string}}
 * @private
 */
funwithactivity.sources.SourcesComponent.toRow_ = function(status) {
  const classification = funwithactivity.features.recommendations
      .classify(status);
  return {
    name: status.name,
    href: '/sources/' + encodeURIComponent(status.name),
    statusClass: classification,
    statusLabel: classification,
    // Latency renders '—' when zero, not '0 ms': stub providers return in
    // microseconds, which truncates to zero, and a column of '0 ms' reads
    // as broken data on the fallback path a demo may be running from.
    reason: funwithactivity.features.recommendations.shortReason(status),
    latencyDisplay: status.latencyMs ? (status.latencyMs + ' ms') : '—',
  };
};


/** @override */
funwithactivity.sources.SourcesComponent.prototype.disposeInternal =
    function() {
  if (this.addButtonKey_) {
    goog.events.unlistenByKey(this.addButtonKey_);
    this.addButtonKey_ = null;
  }
  if (this.rowClickKey_) {
    goog.events.unlistenByKey(this.rowClickKey_);
    this.rowClickKey_ = null;
  }
  this.addButton_ = null;
  // addButton_ was added as a child via addChild() above, so the base
  // class disposes the widget itself here.
  funwithactivity.sources.SourcesComponent.base(this, 'disposeInternal');
};
