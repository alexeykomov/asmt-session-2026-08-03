goog.provide('funwithactivity.recs.RecDetailComponent');

goog.require('funwithactivity.app.LastRecommendations');
goog.require('funwithactivity.app.LastStatuses');
goog.require('funwithactivity.components.recDetailScreen');
goog.require('funwithactivity.dto.Recommendation');
goog.require('funwithactivity.features.recommendations.classify');
goog.require('funwithactivity.render');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.ui.Component');


/**
 * Read-only detail screen for one recommendation (`/recs/<title>`).
 *
 * Reads from funwithactivity.app.LastRecommendations rather than fetching,
 * for the same reason SourceDetailComponent reads from LastStatuses:
 * drilling into a row exists to explain the row the presenter is already
 * looking at. Re-fetching here would call the vendors again and could
 * legitimately return a different set — the user would be reading an
 * explanation of a recommendation that is no longer the one they tapped.
 *
 * Everything shown is derived from data the client already has. No wire
 * field was added for this screen: title, details, source and score come
 * from the cached funwithactivity.dto.Recommendation, and each contributing
 * provider's status and latency come from the cached ProviderStatus for the
 * same fetch. That is a deliberate constraint — a detail screen is not a
 * good enough reason to widen a contract three clients depend on.
 * @param {string} title
 * @constructor
 * @extends {goog.ui.Component}
 */
funwithactivity.recs.RecDetailComponent = function(title) {
  funwithactivity.recs.RecDetailComponent.base(this, 'constructor');

  /** @private @const {string} */
  this.title_ = title;
};
goog.inherits(funwithactivity.recs.RecDetailComponent, goog.ui.Component);


/**
 * Shown when the title in the URL matches nothing in the cache — a deep
 * link straight to /recs/<title> with no fetch this session, or a stale
 * link to a recommendation the latest response no longer contains. Neither
 * is an error worth styling as one; both mean the same thing to the user.
 * @const {string}
 * @private
 */
funwithactivity.recs.RecDetailComponent.NOT_IN_LAST_RESPONSE_ =
    'This recommendation is not in the most recent response — open ' +
    'Recommendations to fetch again.';


/**
 * The server joins every contributing provider into `source` with ', '
 * (see ExactTitleDeduper, which sets Source to the joined display string
 * and keeps the winner's own provider in PrimarySource). Splitting it back
 * apart here is the only way to show per-provider status, and it is safe
 * because provider names cannot contain a comma — they are registry keys,
 * not free text.
 * @const {string}
 * @private
 */
funwithactivity.recs.RecDetailComponent.SOURCE_SEPARATOR_ = ', ';


/** @override */
funwithactivity.recs.RecDetailComponent.prototype.createDom = function() {
  const rec = funwithactivity.app.LastRecommendations.find(this.title_);
  const viewModel = funwithactivity.recs.RecDetailComponent.buildViewModel_(
      this.title_, rec,
      funwithactivity.app.LastRecommendations.rankOf(this.title_),
      funwithactivity.app.LastRecommendations.get().length);

  const el = goog.dom.createDom(
      goog.dom.TagName.DIV,
      {'class': 'fwa-screen-rec-detail screen-container'});
  this.setElementInternal(el);
  funwithactivity.render.element(
      el, funwithactivity.components.recDetailScreen.screen, {rec: viewModel});
};


/**
 * Splits the joined `source` string into the individual provider names
 * that contributed this recommendation, dropping empties so a trailing or
 * doubled separator cannot produce a blank provenance row.
 * @param {string} source
 * @return {!Array<string>}
 * @private
 */
funwithactivity.recs.RecDetailComponent.splitSources_ = function(source) {
  const parts =
      source.split(funwithactivity.recs.RecDetailComponent.SOURCE_SEPARATOR_);
  const names = [];
  for (let i = 0; i < parts.length; i++) {
    const name = parts[i].trim();
    if (name) names.push(name);
  }
  return names;
};


/**
 * @param {string} name
 * @return {{name: string, statusClass: string, statusLabel: string,
 *           latencyDisplay: string}}
 * @private
 */
funwithactivity.recs.RecDetailComponent.buildProviderRow_ = function(name) {
  const status = funwithactivity.app.LastStatuses.find(name);
  if (!status) {
    // The provider contributed this recommendation but reported no status
    // in the same response. That should not happen, so say "unknown"
    // rather than inventing an 'ok' the data does not support.
    return {
      name: name,
      statusClass: 'unknown',
      statusLabel: 'no data',
      latencyDisplay: '—',
    };
  }
  const classification =
      funwithactivity.features.recommendations.classify(status);
  return {
    name: status.name,
    statusClass: classification,
    statusLabel: classification,
    // '—' rather than '0 ms' when zero, matching the Sources list and
    // Source detail: stub providers return in microseconds and truncate.
    latencyDisplay: status.latencyMs ? (status.latencyMs + ' ms') : '—',
  };
};


/**
 * @param {string} title
 * @param {?funwithactivity.dto.Recommendation} rec
 * @param {number} rank 1-based rank in the last response, 0 when absent.
 * @param {number} total Size of the last response.
 * @return {{title: string, detailsDisplay: string, providers: !Array,
 *           provenanceNote: string, provenanceUnknown: string,
 *           scoreDisplay: string, rankDisplay: string,
 *           rankingNote: string}}
 * @private
 */
funwithactivity.recs.RecDetailComponent.buildViewModel_ = function(
    title, rec, rank, total) {
  const Detail = funwithactivity.recs.RecDetailComponent;
  if (!rec) {
    return {
      title: title,
      detailsDisplay: Detail.NOT_IN_LAST_RESPONSE_,
      providers: [],
      provenanceNote: '',
      provenanceUnknown: Detail.NOT_IN_LAST_RESPONSE_,
      scoreDisplay: '—',
      rankDisplay: '—',
      rankingNote: '',
    };
  }

  const names = Detail.splitSources_(rec.source);
  const providers = [];
  for (let i = 0; i < names.length; i++) {
    providers.push(Detail.buildProviderRow_(names[i]));
  }

  // Two providers independently returning the same title is the merge this
  // product exists to perform, so it is stated rather than left for the
  // reader to infer from a comma in the source column.
  const provenanceNote = providers.length > 1 ?
    ('Returned independently by ' + providers.length +
       ' providers and merged into one entry. The highest-scoring instance ' +
       'won; any details only the other supplied were carried across.') :
    'Returned by a single provider.';

  return {
    title: rec.title,
    // Service 1 has no details field at all, so an empty string here is
    // the vendor's data rather than a rendering failure — say so instead
    // of showing a bare dash the presenter would have to explain.
    detailsDisplay: rec.details || 'This provider supplied no detail text.',
    providers: providers,
    provenanceNote: provenanceNote,
    provenanceUnknown: Detail.NOT_IN_LAST_RESPONSE_,
    scoreDisplay: Number(rec.score).toFixed(2),
    rankDisplay: rank ? (rank + ' of ' + total) : '—',
    rankingNote: 'Final score only. Raw and normalised scores stay ' +
        'server-side by design — exposing them would make the ranker\'s ' +
        'internals part of the wire contract.',
  };
};
