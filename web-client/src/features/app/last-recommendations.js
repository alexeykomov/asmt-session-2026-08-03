goog.provide('funwithactivity.app.LastRecommendations');

goog.require('funwithactivity.dto.Recommendation');


/**
 * @fileoverview Cross-screen cache of the most recent
 * POST /api/recommendations response's `recommendations[]`.
 *
 * The exact counterpart of funwithactivity.app.LastStatuses, and a
 * module-level static for the same reason: Shell.prototype.mountScreen_
 * disposes and reconstructs every screen on navigation, so an instance
 * field would forget the last fetch the moment the user drilled into a
 * row. This is what lets RecDetailComponent explain a recommendation the
 * presenter is already looking at without issuing a second vendor call —
 * drilling into a row must never change the data being explained.
 *
 * Keyed by title, which is safe precisely because of dedupe: the server's
 * ExactTitleDeduper (app-server/internal/ranking/dedupe.go) collapses the
 * merged cross-provider set to one entry per distinct title, so within a
 * single response a title identifies exactly one recommendation. Routing
 * by title rather than by list index also survives the table being
 * re-sorted by goog.ui.TableSorter, which an index would not.
 */


/**
 * @private {!Array<!funwithactivity.dto.Recommendation>}
 */
funwithactivity.app.LastRecommendations.recommendations_ = [];


/**
 * @param {!Array<!funwithactivity.dto.Recommendation>} recommendations
 */
funwithactivity.app.LastRecommendations.set = function(recommendations) {
  funwithactivity.app.LastRecommendations.recommendations_ = recommendations;
};


/**
 * @return {!Array<!funwithactivity.dto.Recommendation>}
 */
funwithactivity.app.LastRecommendations.get = function() {
  return funwithactivity.app.LastRecommendations.recommendations_;
};


/**
 * @param {string} title
 * @return {?funwithactivity.dto.Recommendation} The cached recommendation
 *     with this exact title, or null when nothing has been fetched yet
 *     this session or the title matches no row of the last response.
 */
funwithactivity.app.LastRecommendations.find = function(title) {
  const recs = funwithactivity.app.LastRecommendations.recommendations_;
  for (let i = 0; i < recs.length; i++) {
    if (recs[i].title === title) return recs[i];
  }
  return null;
};


/**
 * The recommendation's 1-based position in the last response, in the
 * server's ranked order — deliberately not the order currently displayed,
 * which the user may have re-sorted by clicking a column header. "Rank 3
 * of 7" means third by score as the ranker returned it.
 * @param {string} title
 * @return {number} 1-based rank, or 0 when the title is not in the cache.
 */
funwithactivity.app.LastRecommendations.rankOf = function(title) {
  const recs = funwithactivity.app.LastRecommendations.recommendations_;
  for (let i = 0; i < recs.length; i++) {
    if (recs[i].title === title) return i + 1;
  }
  return 0;
};
