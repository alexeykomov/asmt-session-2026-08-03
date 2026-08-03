goog.provide('funwithactivity.recs.RecsComponent');
goog.provide('funwithactivity.recs.bannerMessages');
goog.provide('funwithactivity.recs.shouldFetch');

goog.require('funwithactivity.app.AppState');
goog.require('funwithactivity.app.LastRecommendations');
goog.require('funwithactivity.app.LastStatuses');
goog.require('funwithactivity.components.recommendationsTable');
goog.require('funwithactivity.components.recsScreen');
goog.require('funwithactivity.dto.ProviderStatus');
goog.require('funwithactivity.dto.Recommendation');
goog.require('funwithactivity.dto.RecommendationsResponse');
goog.require('funwithactivity.features.recommendations.api');
goog.require('funwithactivity.features.recommendations.classify');
goog.require('funwithactivity.render');
goog.require('goog.dom');
goog.require('goog.dom.classlist');
goog.require('goog.dom.TagName');
goog.require('goog.events');
goog.require('goog.events.EventType');
goog.require('goog.ui.Component');
goog.require('goog.ui.TableSorter');


/**
 * Fetch on first visit, and on any revisit where state changed. Extracted
 * as a pure function so the policy is tested without a DOM — the branch
 * itself is the demo's cause-and-effect, and a silent failure here makes
 * the app look like it ignored the user.
 *
 * Both failure directions are real: always returning true burns a vendor
 * call on every tab switch (these vendors are flaky cold-start Lambdas);
 * always returning `!hasFetched` means the presenter edits Profile,
 * returns to Recs, and the screen does not move, with nothing in any log.
 * @param {boolean} hasFetched
 * @param {boolean} isDirty
 * @return {boolean}
 */
funwithactivity.recs.shouldFetch = function(hasFetched, isDirty) {
  return !hasFetched || isDirty;
};


/**
 * Recommendations screen: fetches funwithactivity.features.recommendations
 * .api against the shared AppState's measurements/faults, renders the
 * ranked table and the degradation banner, and refetches on becoming
 * visible again only when shouldFetch() says to.
 * @param {!funwithactivity.app.AppState} state
 * @constructor
 * @extends {goog.ui.Component}
 */
funwithactivity.recs.RecsComponent = function(state, router) {
  funwithactivity.recs.RecsComponent.base(this, 'constructor');

  /** @private @const {!funwithactivity.app.AppState} */
  this.state_ = state;

  /** @private @const {!funwithactivity.app.Router} */
  this.router_ = router;

  /** @private {?goog.events.Key} */
  this.rowClickKey_ = null;

  /**
   * The goog.ui.TableSorter currently decorating the results table, or
   * null before the first render. The table is replaced wholesale on
   * every fetch (see renderTable_), so this is torn down and rebuilt
   * against the new table each time rather than bound once — a sorter
   * bound to the very first table would end up decorating a detached
   * element after the first re-render and silently stop responding to
   * header clicks. Carried over from the pre-shell
   * funwithactivity.features.recommendations.Controller, where this exact
   * defect shipped once already.
   * @private {?goog.ui.TableSorter}
   */
  this.tableSorter_ = null;

  /** @private {?goog.events.Key} */
  this.refreshKey_ = null;
};
goog.inherits(funwithactivity.recs.RecsComponent, goog.ui.Component);


/**
 * Whether a fetch has completed at least once THIS PAGE SESSION. Static on
 * the constructor, not an instance field: funwithactivity.app.Shell
 * disposes and reconstructs the mounted screen on every navigation (see
 * Shell.prototype.mountScreen_) — a fresh RecsComponent is built each time
 * the user tabs back to Recs. An instance field would therefore read false
 * on every single revisit, shouldFetch(false, isDirty) would always be
 * true regardless of isDirty, and the whole point of this policy (skip the
 * refetch when nothing changed) would silently never trigger outside unit
 * tests. A full page reload legitimately resets this to false, which
 * matches "first visit" semantics for a fresh session.
 * @private {boolean}
 */
funwithactivity.recs.RecsComponent.hasFetched_ = false;


/**
 * Column indices of the results table (ui-soy/components/
 * recommendations-table.soy), used to target goog.ui.TableSorter's
 * per-column sort functions by position rather than by (unstable,
 * ADVANCED-renamed) name.
 * @enum {number}
 * @private
 */
funwithactivity.recs.RecsComponent.Column_ = {
  RECOMMENDATION: 0,
  DETAILS: 1,
  SOURCE: 2,
  SCORE: 3,
};


/** @override */
funwithactivity.recs.RecsComponent.prototype.createDom = function() {
  const el = goog.dom.createDom(
      goog.dom.TagName.DIV, {'class': 'fwa-screen-recs screen-container'});
  this.setElementInternal(el);
  funwithactivity.render.element(
      el, funwithactivity.components.recsScreen.screen, {});
};


/** @override */
funwithactivity.recs.RecsComponent.prototype.enterDocument = function() {
  funwithactivity.recs.RecsComponent.base(this, 'enterDocument');

  const refreshBtn = goog.dom.getElement('recs-refresh');
  if (refreshBtn) {
    this.refreshKey_ = goog.events.listen(refreshBtn,
        goog.events.EventType.CLICK, this.handleRefreshClick_, false, this);
  }

  // Row clicks are intercepted and routed in-app rather than left to the
  // browser. Letting the anchor navigate normally would work — web-proxy
  // serves index.html for /recs/<title> — but it is a full page load, and
  // funwithactivity.app.LastRecommendations is in-memory, so the detail
  // screen would come up having forgotten the very response it exists to
  // explain. Delegated from the mount rather than bound per row because
  // renderTable_ replaces the whole table on every fetch.
  const mount = goog.dom.getElement('recs-table-mount');
  if (mount) {
    this.rowClickKey_ = goog.events.listen(mount,
        goog.events.EventType.CLICK, this.handleRowClick_, false, this);
  }

  // Also (re)builds the table/sorter for whatever is currently in the DOM
  // (the empty-state table from recs-screen.soy) so a header click never
  // fires against an undecorated table even before the first fetch lands.
  this.attachTableSorter_();

  this.maybeFetch_(false);
};


/**
 * Mirrors funwithactivity.sources.SourcesComponent.prototype.handleRowClick_:
 * the row's title cell is a plain anchor, not a goog.ui control, so the
 * click is caught by delegation and handed to the router.
 * @param {!goog.events.BrowserEvent} e
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.handleRowClick_ = function(e) {
  const anchor = goog.dom.getAncestor(/** @type {?Node} */ (e.target),
      function(node) {
        return node.nodeType == 1 &&
            goog.dom.classlist.contains(/** @type {!Element} */ (node),
                'recs-title-link');
      }, true);
  if (!anchor) return;
  e.preventDefault();
  this.router_.go(anchor.getAttribute('href'));
};


/** @private */
funwithactivity.recs.RecsComponent.prototype.handleRefreshClick_ = function() {
  // The refresh button forces a fetch regardless of AppState's dirty flag
  // — see recs-screen.soy's doc comment on why that is the whole point of
  // this control.
  this.maybeFetch_(true);
};


/**
 * @param {boolean} force When true, fetches unconditionally (the Refresh
 *     button); otherwise defers to shouldFetch().
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.maybeFetch_ = function(force) {
  // Nothing to ask for until height and weight exist. AppState starts at
  // zero, web-proxy rejects a non-positive measurement with 400
  // invalid_measurements, and the old behaviour was therefore to open the
  // app on a red "unable to fetch" banner — reporting a user error as a
  // system failure, on the very first screen anyone sees.
  //
  // Deliberately checked before shouldFetch(): an invalid state must not
  // consume the first-visit fetch, or a later visit with real measurements
  // would look like a revisit and skip the fetch entirely.
  if (!this.hasUsableMeasurements_()) {
    this.renderNeedsMeasurements_();
    return;
  }

  if (!force && !funwithactivity.recs.shouldFetch(
      funwithactivity.recs.RecsComponent.hasFetched_, this.state_.isDirty())) {
    return;
  }
  this.fetch_();
};


/**
 * Mirrors web-proxy's parseMeasurements guard: height and weight must both
 * be finite and positive. Birth date is deliberately NOT required — leaving
 * it out is the data-minimisation choice the product exists to demonstrate.
 * @return {boolean}
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.hasUsableMeasurements_ =
    function() {
  const m = this.state_.getMeasurements();
  return isFinite(m.heightCm) && m.heightCm > 0 &&
      isFinite(m.weightKg) && m.weightKg > 0;
};


/**
 * Informational prompt shown instead of a fetch when no measurements have
 * been entered yet. Styled as guidance, not as an error: nothing has gone
 * wrong, the app simply has nothing to ask about yet.
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.renderNeedsMeasurements_ =
    function() {
  const banner = goog.dom.getElement('degradation-banner');
  if (!banner) return;
  goog.dom.removeChildren(banner);
  goog.dom.appendChild(banner, goog.dom.createDom(
      goog.dom.TagName.P, {'class': 'recs-banner-skipped'},
      'Add your height and weight in Profile to get recommendations.'));
};


/** @private */
funwithactivity.recs.RecsComponent.prototype.fetch_ = function() {
  const measurements = this.state_.getMeasurements();
  // The object below is passed straight to JSON.stringify by api.fetch(),
  // so every key MUST be a quoted string literal — see the identical note
  // on the pre-shell Controller.readPayload_, which this replaces. An
  // object literal with unquoted (dotted-style) keys gets those keys
  // renamed by ADVANCED just like any other property, silently breaking
  // web-proxy's parseMeasurements.
  const payload = {
    'heightCm': measurements.heightCm,
    'weightKg': measurements.weightKg,
    'birthDateUnix': measurements.birthDateUnix,
    'faults': this.state_.getFaults(),
  };
  funwithactivity.features.recommendations.api.fetch(payload).then(
      goog.bind(this.renderSuccess_, this),
      goog.bind(this.renderError_, this));
};


/**
 * @param {!funwithactivity.dto.RecommendationsResponse} response
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.renderSuccess_ = function(
    response) {
  funwithactivity.recs.RecsComponent.hasFetched_ = true;
  this.state_.markClean();

  // response is a DTO instance, unpacked from the wire's packed array by
  // api.js. Its fields are real, typed class fields, so the compiler
  // renames the definition and every access below together — plain
  // dotted property access is correct here.
  //
  // Cached for the Sources/Source-detail screens (funwithactivity.app.
  // LastStatuses) so they can show "the most recent response's statuses[]"
  // without spending a second vendor call for data this fetch already has.
  funwithactivity.app.LastStatuses.set(response.statuses);
  // Published for the detail screen (RecDetailComponent), which explains a
  // row rather than re-fetching it — see LastRecommendations' fileoverview.
  funwithactivity.app.LastRecommendations.set(response.recommendations);
  this.renderTable_(response.recommendations);
  this.renderBanner_(response.statuses, response.recommendations.length > 0);
};


/**
 * Renders the results table through the compiled Soy template
 * (funwithactivity.components.recommendationsTable.table), replacing the
 * whole `#recs-table-mount` contents each fetch. A full replace — rather
 * than an incremental DOM patch — is the right call here because the
 * table has no per-row identity across fetches.
 * @param {!Array<!funwithactivity.dto.Recommendation>} recommendations
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.renderTable_ = function(
    recommendations) {
  const mount = goog.dom.getElement('recs-table-mount');
  if (!mount) return;
  funwithactivity.render.element(
      mount, funwithactivity.components.recommendationsTable.table,
      {recommendations: recommendations.map(
          funwithactivity.recs.RecsComponent.withFormattedScore_)});
  this.attachTableSorter_();
};


/**
 * (Re)decorates whatever table is currently in `#recs-table-mount` with a
 * fresh goog.ui.TableSorter. Called after every renderTable_ (and once
 * from enterDocument for the pre-fetch empty-state table), since the
 * table is replaced wholesale each fetch — a sorter instance can only ever
 * decorate one table element, so the old one (now decorating a detached,
 * about-to-be-garbage-collected table) is disposed first rather than left
 * to leak one TableSorter — and its header click listener — per fetch.
 *
 * Recommendation and Source sort alphabetically
 * (goog.ui.TableSorter.alphaSort); Score sorts numerically
 * (goog.ui.TableSorter.numericSort) so e.g. 0.9 correctly sorts above
 * 0.88. Details carries no meaningful sort order, so it is set to
 * goog.ui.TableSorter.noSort explicitly.
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.attachTableSorter_ = function() {
  if (this.tableSorter_) {
    this.tableSorter_.dispose();
    this.tableSorter_ = null;
  }

  const mount = goog.dom.getElement('recs-table-mount');
  const table = mount && goog.dom.getElementByClass('recs-table', mount);
  if (!table) return;

  const Column = funwithactivity.recs.RecsComponent.Column_;
  const sorter = new goog.ui.TableSorter();
  sorter.setSortFunction(
      Column.RECOMMENDATION, goog.ui.TableSorter.alphaSort);
  sorter.setSortFunction(Column.DETAILS, goog.ui.TableSorter.noSort);
  sorter.setSortFunction(Column.SOURCE, goog.ui.TableSorter.alphaSort);
  sorter.setSortFunction(Column.SCORE, goog.ui.TableSorter.numericSort);
  sorter.decorate(/** @type {!HTMLTableElement} */ (table));
  this.tableSorter_ = sorter;
};


/**
 * Shape consumed by ui-soy/components/recommendations-table.soy: the
 * Recommendation DTO's display fields plus the client-computed
 * `scoreDisplay` string. Kept as a separate typedef, rather than adding
 * `scoreDisplay` onto `funwithactivity.dto.Recommendation` itself, because
 * that DTO's shape is owned by api/dto/ (the wire contract) and
 * `scoreDisplay` never crosses the wire.
 * @typedef {{
 *   title: string,
 *   details: string,
 *   source: string,
 *   scoreDisplay: string
 * }}
 * @private
 */
funwithactivity.recs.RecsComponent.TableRow_;


/**
 * The server sends `score` as a raw float with whatever precision the
 * ranking math happens to produce. iOS (`%.2f`) and Android
 * (`R.string.score_format`, "%1$.2f") both already normalise to exactly
 * two decimal places; this builds a plain display row carrying a
 * `scoreDisplay` string so the web client matches them, without changing
 * the DTO's `score` field itself.
 * @param {!funwithactivity.dto.Recommendation} r
 * @return {!funwithactivity.recs.RecsComponent.TableRow_}
 * @private
 */
funwithactivity.recs.RecsComponent.withFormattedScore_ = function(r) {
  return {
    title: r.title,
    details: r.details,
    source: r.source,
    scoreDisplay: Number(r.score).toFixed(2),
    // Drill-down target. Encoded because a title is vendor prose, not an
    // identifier: "Don't eat carbs!" carries an apostrophe, punctuation
    // and spaces, and would otherwise not survive the round trip.
    href: '/recs/' + encodeURIComponent(r.title),
  };
};


/**
 * Pure, DOM-free banner content decision — extracted (like
 * funwithactivity.recs.shouldFetch above) so it is unit-testable without a
 * browser. Classifies every status through funwithactivity.features.
 * recommendations.classify() — the single place that decides skipped vs.
 * degraded — rather than re-deriving that branch here; `error` itself is
 * never consulted directly for the same reason classify() exists at all: a
 * skipped provider also carries explanatory text in `error`, so branching
 * on it before classify() has done so would risk rendering deliberate
 * data-minimisation as a provider outage. That exact ordering mistake has
 * caused four defects in this project.
 *
 * "<name> unavailable — showing partial results" is only true when some
 * recommendation survived; with zero, it promises a table the screen is
 * not showing and reads as a broken app — realistic on stage, since these
 * vendors fail roughly one call in three and both can fail together. When
 * `hasResults` is false, the aggregate cases below replace that per-
 * provider claim rather than just deleting it, so the screen still says
 * *something* about why the table is empty:
 *  - every non-ok provider is 'degraded' (no 'skipped') → one failure
 *    message, styled as a real outage (red/danger).
 *  - every non-ok provider is 'skipped' (no 'degraded') → one
 *    data-minimisation message, styled informational (blue) — never as a
 *    failure; that inversion is exactly the four-defects mistake above.
 *  - a genuine mix of both, zero results → state both plainly, one line
 *    per provider in its own correct colour, and never claim partial
 *    results; this is deliberately NOT collapsed into a single sentence,
 *    since any one sentence mentioning both would have to put "skipped"
 *    inside whatever single colour it picked.
 * @param {!Array<!funwithactivity.dto.ProviderStatus>} statuses
 * @param {boolean} hasResults Whether this fetch produced at least one
 *     recommendation.
 * @return {!Array<{text: string, className: string}>}
 */
funwithactivity.recs.bannerMessages = function(statuses, hasResults) {
  const classify = funwithactivity.features.recommendations.classify;
  const classifications = statuses.map(classify);
  const anySkipped = classifications.indexOf('skipped') !== -1;
  const anyDegraded = classifications.indexOf('degraded') !== -1;

  if (!hasResults && anyDegraded && !anySkipped) {
    return [{
      text: 'No recommendations available — all providers are unavailable',
      className: 'recs-banner-degraded',
    }];
  }
  if (!hasResults && anySkipped && !anyDegraded) {
    return [{
      text: 'No recommendations — no provider had the data it needs',
      className: 'recs-banner-skipped',
    }];
  }

  // Every other case: some results survived, nothing failed, or a genuine
  // mix of skipped + degraded with zero results. One line per non-ok
  // provider, in status order, exactly as before this change — except the
  // degraded wording drops "— showing partial results" whenever there are
  // zero results, since that phrase must never sit next to an empty table.
  const messages = [];
  for (let i = 0; i < statuses.length; i++) {
    const status = statuses[i];
    if (classifications[i] == 'skipped') {
      messages.push({
        text: status.name + ' skipped — ' + status.error,
        className: 'recs-banner-skipped',
      });
    } else if (classifications[i] == 'degraded') {
      messages.push({
        text: hasResults ?
            status.name + ' unavailable — showing partial results' :
            status.name + ' unavailable',
        className: 'recs-banner-degraded',
      });
    }
  }
  return messages;
};


/**
 * Renders funwithactivity.recs.bannerMessages's output into the
 * degradation banner. All decision-making lives in that pure function;
 * this is DOM plumbing only.
 * @param {!Array<!funwithactivity.dto.ProviderStatus>} statuses
 * @param {boolean} hasResults Whether this fetch produced at least one
 *     recommendation — see bannerMessages.
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.renderBanner_ = function(
    statuses, hasResults) {
  const banner = goog.dom.getElement('degradation-banner');
  if (!banner) return;
  goog.dom.removeChildren(banner);
  funwithactivity.recs.bannerMessages(statuses, hasResults).forEach(
      function(message) {
        goog.dom.appendChild(banner, goog.dom.createDom(
            goog.dom.TagName.P, {'class': message.className}, message.text));
      });
};


/**
 * @param {*} err
 * @private
 */
funwithactivity.recs.RecsComponent.prototype.renderError_ = function(err) {
  const banner = goog.dom.getElement('degradation-banner');
  if (!banner) return;
  goog.dom.removeChildren(banner);
  goog.dom.appendChild(banner, goog.dom.createDom(
      goog.dom.TagName.P, {'class': 'recs-banner-error'},
      'Unable to fetch recommendations — please try again.'));
};


/** @override */
funwithactivity.recs.RecsComponent.prototype.disposeInternal = function() {
  if (this.refreshKey_) {
    goog.events.unlistenByKey(this.refreshKey_);
    this.refreshKey_ = null;
  }
  if (this.rowClickKey_) {
    goog.events.unlistenByKey(this.rowClickKey_);
    this.rowClickKey_ = null;
  }
  if (this.tableSorter_) {
    this.tableSorter_.dispose();
    this.tableSorter_ = null;
  }
  funwithactivity.recs.RecsComponent.base(this, 'disposeInternal');
};
