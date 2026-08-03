goog.provide('funwithactivity.features.recommendations.Controller');

goog.require('funwithactivity.components.recommendationsTable');
goog.require('funwithactivity.dto.ProviderStatus');
goog.require('funwithactivity.dto.Recommendation');
goog.require('funwithactivity.dto.RecommendationsResponse');
goog.require('funwithactivity.features.recommendations.api');
goog.require('funwithactivity.features.recommendations.classify');
goog.require('funwithactivity.render');
goog.require('goog.Disposable');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.events');
goog.require('goog.events.EventType');
goog.require('goog.ui.TableSorter');


/**
 * Drives the measurements + fault-injection form: submits to
 * POST /api/recommendations and re-renders the results table and
 * degradation banner in place, without a full-page reload.
 * @constructor
 * @extends {goog.Disposable}
 */
funwithactivity.features.recommendations.Controller = function() {
  funwithactivity.features.recommendations.Controller.base(
      this, 'constructor');

  /**
   * Listener key for the form submit handler, kept so it can be unlistened
   * in disposeInternal per Closure convention.
   * @private {?goog.events.Key}
   */
  this.submitKey_ = null;

  /**
   * Provider name for each fault-toggle slot — index 0 is the "Service 1"
   * checkbox/select pair, index 1 is "Service 2". Refreshed from the
   * `statuses[]` of every successful response (see updateProviderNames_)
   * so the fault map sent on the *next* submit always targets whatever
   * the backend actually calls its providers this session: real-vendor
   * names (`service1`, `service2`) or stub names (`service1-stub`,
   * `service2-stub`) when `USE_STUB_PROVIDERS=true` — without this file
   * ever hardcoding either. Hardcoding the real names here is exactly
   * the bug this field fixes: with stub providers registered as
   * `service1-stub`/`service2-stub`, a fault keyed `service1` never
   * matches anything server-side and the checkbox silently no-ops.
   *
   * Seeded with the real-vendor names before any response has arrived,
   * since that's this deployment's default runtime mode (see
   * providers.DefaultProviders on the server) and, more importantly,
   * because the real vendors are cold-start Lambdas that need a warm-up
   * call before a demo anyway (the first couple of calls can return
   * partial/empty results regardless of faults) — that warm-up response
   * populates this array with whichever names are actually in play
   * (real or stub) before a presenter would ever need to check a fault
   * box. So this seed only matters for the edge case of ticking a fault
   * box on the very first submit of a fresh session, before any prior
   * response — a case a presenter can trivially avoid by doing one
   * fault-free warm-up submit first, which they need to do anyway.
   * @private {!Array<string>}
   */
  this.providerNames_ = ['service1', 'service2'];

  /**
   * The goog.ui.TableSorter currently decorating the results table, or
   * null before the first render. The table is replaced wholesale on
   * every submit (see renderTable_), so this is torn down and rebuilt
   * against the new table each time rather than bound once at startup —
   * a sorter bound to the very first table would end up decorating a
   * detached element after the first re-render and silently stop
   * responding to header clicks.
   * @private {?goog.ui.TableSorter}
   */
  this.tableSorter_ = null;
};
goog.inherits(
    funwithactivity.features.recommendations.Controller, goog.Disposable);


/**
 * Column indices of the results table (ui-soy/components/
 * recommendations-table.soy), used to target goog.ui.TableSorter's
 * per-column sort functions by position rather than by (unstable,
 * ADVANCED-renamed) name.
 * @enum {number}
 * @private
 */
funwithactivity.features.recommendations.Controller.Column_ = {
  RECOMMENDATION: 0,
  DETAILS: 1,
  SOURCE: 2,
  SCORE: 3
};


/** Binds the form submit handler. */
funwithactivity.features.recommendations.Controller.prototype.decorate =
    function() {
  const form = goog.dom.getElement('recs-form');
  if (!form) return;
  this.submitKey_ = goog.events.listen(
      form, goog.events.EventType.SUBMIT, this.handleSubmit_, false, this);
  this.bindFaultToggle_('fault-service1', 'fault-service1-mode');
  this.bindFaultToggle_('fault-service2', 'fault-service2-mode');
};


/**
 * Wires a fault checkbox to its paired mode `<select>`. Both selects ship
 * `disabled` in the markup (ui-soy/pages/recommendations.soy) so a mode
 * can't be picked while its fault is off; checking the box is what makes
 * the mode selectable, and unchecking it disables the select again.
 * @param {string} checkboxId
 * @param {string} selectId
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype
    .bindFaultToggle_ = function(checkboxId, selectId) {
  const checkbox = /** @type {?HTMLInputElement} */ (
      goog.dom.getElement(checkboxId));
  const select = /** @type {?HTMLSelectElement} */ (
      goog.dom.getElement(selectId));
  if (!checkbox || !select) return;
  goog.events.listen(checkbox, goog.events.EventType.CHANGE, function() {
    select.disabled = !checkbox.checked;
  });
};


/**
 * @param {!goog.events.Event} e
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype.handleSubmit_ =
    function(e) {
  e.preventDefault();

  const payload = this.readPayload_();
  funwithactivity.features.recommendations.api.fetch(payload).then(
      goog.bind(this.renderSuccess_, this),
      goog.bind(this.renderError_, this));
};


/**
 * The returned object is passed straight to `JSON.stringify` by
 * api.fetch(), so every key MUST be a quoted string literal here. An
 * object literal with unquoted (dotted-style) keys — `{heightCm: ...}` —
 * gets those keys renamed by ADVANCED just like any other property, and
 * since JSON.stringify has no idea renaming happened, the wire body would
 * silently ship as e.g. `{"C":180}` instead of `{"heightCm":180}`,
 * breaking web-proxy's `parseMeasurements`. Quoting the keys —
 * `{'heightCm': ...}` — tells Closure they're reflected/serialized data,
 * not renameable identifiers, so they survive verbatim.
 * @return {{heightCm: number, weightKg: number, birthDateUnix: number,
 *           faults: !Object<string,string>}}
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype.readPayload_ =
    function() {
  const heightEl =
      /** @type {!HTMLInputElement} */ (goog.dom.getElement('height-cm'));
  const weightEl =
      /** @type {!HTMLInputElement} */ (goog.dom.getElement('weight-kg'));
  const birthEl =
      /** @type {!HTMLInputElement} */ (goog.dom.getElement('birth-date'));

  // Empty birth date is a deliberate GDPR Art. 5(1)(c) data-minimisation
  // choice, not missing data — the proto/API convention for "not supplied"
  // is 0, matching how web-proxy already treats an absent birthDateUnix.
  const birthDateUnix = birthEl.value ?
      Math.floor(new Date(birthEl.value).getTime() / 1000) : 0;

  return {
    'heightCm': Number(heightEl.value),
    'weightKg': Number(weightEl.value),
    'birthDateUnix': birthDateUnix,
    'faults': this.readFaults_(),
  };
};


/**
 * @return {!Object<string,string>}
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype.readFaults_ =
    function() {
  const faults = {};
  this.readFault_(faults, 0, 'fault-service1', 'fault-service1-mode');
  this.readFault_(faults, 1, 'fault-service2', 'fault-service2-mode');
  return faults;
};


/**
 * Reads one fault checkbox/select pair, keying the fault by the *actual*
 * provider name at this slot (this.providerNames_[index] — see the field
 * doc in the constructor), never a hardcoded string. This is what lets
 * the toggle keep working whether the backend is running real providers
 * (`service1`/`service2`) or stubs (`service1-stub`/`service2-stub`), and
 * for any provider swapped into this slot later, without a code change
 * here.
 * @param {!Object<string,string>} faults
 * @param {number} index Fault-toggle slot — see this.providerNames_.
 * @param {string} checkboxId
 * @param {string} selectId
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype.readFault_ =
    function(faults, index, checkboxId, selectId) {
  const checkbox = /** @type {?HTMLInputElement} */ (
      goog.dom.getElement(checkboxId));
  const select = /** @type {?HTMLSelectElement} */ (
      goog.dom.getElement(selectId));
  const providerName = this.providerNames_[index];
  if (checkbox && checkbox.checked && select && providerName) {
    faults[providerName] = select.value;
  }
};


/**
 * Refreshes this.providerNames_ from the `statuses[]` of a successful
 * response — the server is the sole source of truth for what its
 * providers are actually named this session. Only overwrites slots the
 * response actually reports, so a short (or momentarily empty) statuses
 * array can never erase a name already learned from an earlier response
 * in the same session.
 * @param {!Array<!funwithactivity.dto.ProviderStatus>} statuses
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype
    .updateProviderNames_ = function(statuses) {
  for (let i = 0; i < statuses.length; i++) {
    const name = statuses[i].name;
    if (name) this.providerNames_[i] = name;
  }
};


/**
 * @param {!funwithactivity.dto.RecommendationsResponse} response
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype
    .renderSuccess_ = function(response) {
  // response is a DTO instance (funwithactivity.dto.RecommendationsResponse),
  // unpacked from the wire's packed array by api.js. Its fields are real,
  // typed class fields, so the compiler renames the definition and every
  // access below together — plain dotted property access is correct here.
  const statuses = response.statuses;
  this.updateProviderNames_(statuses);
  this.renderTable_(response.recommendations);
  this.renderBanner_(statuses);
};


/**
 * Renders the results table through the compiled Soy template
 * (funwithactivity.components.recommendationsTable.table), replacing the
 * whole `#recs-table-mount` contents each submit. A full replace — rather
 * than an incremental DOM patch — is the right call here because the table
 * has no per-row identity across submits; targeted hand-written DOM
 * updates remain correct for high-frequency streams (e.g. a later task's
 * live vitals strip), just not for this table.
 * @param {!Array<!funwithactivity.dto.Recommendation>} recommendations
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype.renderTable_ =
    function(recommendations) {
  const mount = goog.dom.getElement('recs-table-mount');
  if (!mount) return;
  funwithactivity.render.element(
      mount, funwithactivity.components.recommendationsTable.table,
      {recommendations: recommendations.map(
          funwithactivity.features.recommendations.Controller
              .withFormattedScore_)});
  this.attachTableSorter_(mount);
};


/**
 * (Re)decorates the table just written into `mount` with a fresh
 * goog.ui.TableSorter. Called after every renderTable_, since the table
 * is replaced wholesale each submit — a sorter instance can only ever
 * decorate one table element, so the old one (now decorating a detached,
 * about-to-be-garbage-collected table) is disposed first rather than
 * left to leak one TableSorter — and its header click listener — per
 * submit.
 *
 * Recommendation and Source sort alphabetically
 * (goog.ui.TableSorter.alphaSort); Score sorts numerically
 * (goog.ui.TableSorter.numericSort) so e.g. 0.9 correctly sorts above
 * 0.88 instead of a lexical sort putting 0.88 first. Details carries no
 * meaningful sort order, so it is set to goog.ui.TableSorter.noSort
 * explicitly rather than left to inherit whatever the default sort
 * function happens to be.
 *
 * decorate() only wires up click handling — it never sorts on its own —
 * so the table keeps the server's ranked (descending score) order until
 * a user opts in by clicking a header.
 * @param {!Element} mount
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype
    .attachTableSorter_ = function(mount) {
  if (this.tableSorter_) {
    this.tableSorter_.dispose();
    this.tableSorter_ = null;
  }

  const table = goog.dom.getElementByClass('recs-table', mount);
  if (!table) return;

  const Column = funwithactivity.features.recommendations.Controller.Column_;
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
 * `scoreDisplay` string (see below). Kept as a separate typedef, rather
 * than adding `scoreDisplay` onto `funwithactivity.dto.Recommendation`
 * itself, because that DTO's shape is owned by api/dto/ (the wire
 * contract) and `scoreDisplay` never crosses the wire.
 * @typedef {{
 *   title: string,
 *   details: string,
 *   source: string,
 *   scoreDisplay: string
 * }}
 * @private
 */
funwithactivity.features.recommendations.Controller.TableRow_;


/**
 * The server sends `score` as a raw float with whatever precision the
 * ranking math happens to produce (observed on the wire: 0.95, 0.398,
 * 0.6, 0.04, ...). iOS (`%.2f` in FWAResultsViewController) and Android
 * (`R.string.score_format`, "%1$.2f") both already normalise to exactly
 * two decimal places; this builds a plain display row carrying a
 * `scoreDisplay` string so the web client matches them, without changing
 * the DTO's `score` field itself (it stays the raw wire number on `r`).
 *
 * `r` is a `funwithactivity.dto.Recommendation` DTO instance, so its
 * fields are read via plain dotted access — the compiler renames the
 * class fields and these reads together. The returned object is a fresh
 * literal (not itself wire data), so its properties are ordinary
 * ADVANCED-renameable identifiers too, and the Soy-compiled template that
 * reads `scoreDisplay` gets renamed in lockstep with this literal.
 * @param {!funwithactivity.dto.Recommendation} r
 * @return {!funwithactivity.features.recommendations.Controller.TableRow_}
 * @private
 */
funwithactivity.features.recommendations.Controller.withFormattedScore_ =
    function(r) {
  return {
    title: r.title,
    details: r.details,
    source: r.source,
    scoreDisplay: Number(r.score).toFixed(2),
  };
};


/**
 * Renders the degradation banner from provider statuses, one row per
 * non-ok status, classifying each through
 * funwithactivity.features.recommendations.classify() — the single place
 * that decides skipped vs. degraded (see that file: `ok` is tested first,
 * then `skipped` before the degraded fallback; `error` itself is never
 * consulted by classify() at all — a skipped provider also carries
 * explanatory text in `error`, so branching on it would risk rendering
 * deliberate data-minimisation as a provider outage). Rows are built with
 * goog.dom.createDom rather than through a Soy template precisely so this
 * classification has exactly one implementation on the real render path.
 * A degradation-banner Soy template used to exist and re-derived the same
 * skipped-before-error branch from raw DTO fields; it was deleted rather
 * than left dead, because a second copy of this decision is what caused
 * the earlier defects. Do not reintroduce one.
 * @param {!Array<!funwithactivity.dto.ProviderStatus>} statuses
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype.renderBanner_ =
    function(statuses) {
  const banner = goog.dom.getElement('degradation-banner');
  if (!banner) return;
  goog.dom.removeChildren(banner);
  for (let i = 0; i < statuses.length; i++) {
    const status = statuses[i];
    const classification =
        funwithactivity.features.recommendations.classify(status);
    if (classification == 'skipped') {
      goog.dom.appendChild(banner, goog.dom.createDom(
          goog.dom.TagName.P, {'class': 'recs-banner-skipped'},
          status.name + ' skipped — ' + status.error));
    } else if (classification == 'degraded') {
      goog.dom.appendChild(banner, goog.dom.createDom(
          goog.dom.TagName.P, {'class': 'recs-banner-degraded'},
          status.name + ' unavailable — showing partial results'));
    }
  }
};


/**
 * @param {*} err
 * @private
 */
funwithactivity.features.recommendations.Controller.prototype.renderError_ =
    function(err) {
  const banner = goog.dom.getElement('degradation-banner');
  if (!banner) return;
  goog.dom.removeChildren(banner);
  goog.dom.appendChild(banner, goog.dom.createDom(
      goog.dom.TagName.P, {'class': 'recs-banner-error'},
      'Unable to fetch recommendations — please try again.'));
};


/** @override */
funwithactivity.features.recommendations.Controller.prototype
    .disposeInternal = function() {
  if (this.submitKey_) {
    goog.events.unlistenByKey(this.submitKey_);
    this.submitKey_ = null;
  }
  if (this.tableSorter_) {
    this.tableSorter_.dispose();
    this.tableSorter_ = null;
  }
  funwithactivity.features.recommendations.Controller.base(
      this, 'disposeInternal');
};
