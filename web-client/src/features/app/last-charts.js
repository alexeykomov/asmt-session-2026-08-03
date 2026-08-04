goog.provide('funwithactivity.app.LastCharts');

goog.require('funwithactivity.dto.Chart');


/**
 * @fileoverview Cross-screen cache of the most recent POST /api/charts
 * response.
 *
 * The counterpart of funwithactivity.app.LastStatuses and
 * funwithactivity.app.LastRecommendations, and a module-level static for the
 * same reason: Shell.prototype.mountScreen_ disposes and reconstructs every
 * screen on navigation, so an instance field would forget the last response
 * the moment the user tabbed away.
 *
 * This exists to answer a question separate from "should we fetch?". The
 * refetch policy correctly declines to call the server again for an unchanged
 * profile, but the screen it returns to has just been rebuilt from scratch and
 * has nothing drawn on it. Without a cache to repaint from, declining to fetch
 * and losing the data look identical to the user — which is exactly the defect
 * that shipped on the Recommendations tab and had to be fixed there.
 */


/**
 * @private {!Array<!funwithactivity.dto.Chart>}
 */
funwithactivity.app.LastCharts.charts_ = [];


/**
 * @param {!Array<!funwithactivity.dto.Chart>} charts
 */
funwithactivity.app.LastCharts.set = function(charts) {
  funwithactivity.app.LastCharts.charts_ = charts;
};


/**
 * @return {!Array<!funwithactivity.dto.Chart>}
 */
funwithactivity.app.LastCharts.get = function() {
  return funwithactivity.app.LastCharts.charts_;
};
