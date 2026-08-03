goog.provide('funwithactivity.sources.SourceDetailComponent');

goog.require('funwithactivity.app.LastStatuses');
goog.require('funwithactivity.components.sourceDetailScreen');
goog.require('funwithactivity.dto.ProviderStatus');
goog.require('funwithactivity.features.recommendations.classify');
goog.require('funwithactivity.render');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.ui.Component');


/**
 * Read-only detail screen for one source (`/sources/<name>`), styled with
 * the same shared screen header/section chrome as every other screen —
 * see ui-soy/components/source-detail-screen.soy, which calls
 * funwithactivity.components.screenSection.section (the same template
 * funwithactivity.profile.ProfileComponent's screen uses) rather than
 * inventing a second style. No row here carries the Sources list's
 * disclosure chevron — every row on this screen is read-only, not
 * navigable — see the doc on sources-screen.soy's `.list` template.
 *
 * Reads its data from funwithactivity.app.LastStatuses rather than
 * fetching: this screen exists to explain a status the presenter is
 * already looking at (typically drilled into from the Sources list), not
 * to trigger a fresh vendor call of its own. If the cache has never been
 * populated this session (e.g. a deep link straight to /sources/<name>
 * with no prior fetch), it says so plainly rather than showing an empty
 * or misleading status.
 *
 * Every source in this proof of concept is read-only — see
 * funwithactivity.sources.AddSourceComponent for why nothing can actually
 * be added at runtime — so this component never wires up any control;
 * the template renders plain label/value rows plus an explanatory
 * footer.
 * @param {string} name
 * @constructor
 * @extends {goog.ui.Component}
 */
funwithactivity.sources.SourceDetailComponent = function(name) {
  funwithactivity.sources.SourceDetailComponent.base(this, 'constructor');

  /** @private @const {string} */
  this.name_ = name;
};
goog.inherits(
    funwithactivity.sources.SourceDetailComponent, goog.ui.Component);


/** @override */
funwithactivity.sources.SourceDetailComponent.prototype.createDom =
    function() {
  const status = funwithactivity.app.LastStatuses.find(this.name_);
  const viewModel = funwithactivity.sources.SourceDetailComponent
      .buildViewModel_(this.name_, status);

  const el = goog.dom.createDom(
      goog.dom.TagName.DIV, {'class': 'fwa-screen-source-detail screen-container'});
  this.setElementInternal(el);
  funwithactivity.render.element(
      el, funwithactivity.components.sourceDetailScreen.screen,
      {source: viewModel});
};


/**
 * Both built-in providers speak the same shared Lambda+FastAPI REST
 * envelope (app-server/internal/providers/envelope.go) — there is no wire
 * field that would tell the client this, so it is a fact about this
 * deployment, stated here rather than derived from data that doesn't
 * exist on the wire.
 * @const {string}
 * @private
 */
funwithactivity.sources.SourceDetailComponent.TYPE_ = 'REST';


/**
 * Shown in the Base URL row when no cached status is available for this
 * source (e.g. a deep link straight to /sources/<name> with no prior
 * fetch this session) — there is nothing fabricated to show, so this
 * screen says so plainly instead.
 * @const {string}
 * @private
 */
funwithactivity.sources.SourceDetailComponent.BASE_URL_UNKNOWN_ =
    'Unknown — no status reported yet this session.';


/**
 * @param {string} name
 * @param {?funwithactivity.dto.ProviderStatus} status
 * @return {{name: string, type: string, baseUrl: string,
 *           statusClass: string, statusLabel: string,
 *           latencyDisplay: string, errorText: string}}
 * @private
 */
funwithactivity.sources.SourceDetailComponent.buildViewModel_ = function(
    name, status) {
  const Detail = funwithactivity.sources.SourceDetailComponent;
  if (!status) {
    return {
      name: name,
      type: Detail.TYPE_,
      baseUrl: Detail.BASE_URL_UNKNOWN_,
      statusClass: 'unknown',
      statusLabel: 'no data',
      latencyDisplay: '—',
      errorText: 'No status reported yet this session — visit ' +
          'Recommendations or Sources to fetch one.',
    };
  }

  const classification =
      funwithactivity.features.recommendations.classify(status);
  return {
    name: status.name,
    type: Detail.TYPE_,
    baseUrl: status.baseUrl || Detail.BASE_URL_UNKNOWN_,
    statusClass: classification,
    statusLabel: classification,
    // Latency renders '—' when zero, not '0 ms' — matches the Sources
    // list's own rule (stub providers return in microseconds, which
    // truncates to zero).
    latencyDisplay: status.latencyMs ? (status.latencyMs + ' ms') : '—',
    // Unlike the list, the detail screen's STATUS section shows the FULL,
    // unredacted error text — this is where an operator needs it. See
    // funwithactivity.features.recommendations.shortReason's doc.
    errorText: status.error || '—',
  };
};
