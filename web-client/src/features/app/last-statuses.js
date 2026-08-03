goog.provide('funwithactivity.app.LastStatuses');

goog.require('funwithactivity.dto.ProviderStatus');


/**
 * @fileoverview Cross-screen cache of the most recent
 * POST /api/recommendations response's `statuses[]`.
 *
 * A module-level static, not per-instance state on any one screen: every
 * screen (RecsComponent, SourcesComponent, SourceDetailComponent) is
 * disposed and reconstructed on each navigation (see
 * Shell.prototype.mountScreen_), so an instance field would forget the
 * last fetch the moment the user tabbed away from whichever screen made
 * it. This is what lets the Sources screen show "the most recent
 * response's statuses[]" (per the Task 7 brief) without a second REST
 * call when RecsComponent has already fetched this session, and lets the
 * Source detail screen find the full (unredacted) error text for whatever
 * provider the presenter drilled into — see
 * funwithactivity.features.recommendations.shortReason's doc for why the
 * LIST must never show that raw text but the detail screen must.
 */


/**
 * @private {!Array<!funwithactivity.dto.ProviderStatus>}
 */
funwithactivity.app.LastStatuses.statuses_ = [];


/**
 * @param {!Array<!funwithactivity.dto.ProviderStatus>} statuses
 */
funwithactivity.app.LastStatuses.set = function(statuses) {
  funwithactivity.app.LastStatuses.statuses_ = statuses;
};


/**
 * @return {!Array<!funwithactivity.dto.ProviderStatus>}
 */
funwithactivity.app.LastStatuses.get = function() {
  return funwithactivity.app.LastStatuses.statuses_;
};


/**
 * @param {string} name
 * @return {?funwithactivity.dto.ProviderStatus} The cached status for this
 *     provider name, or null if no cached response reported one — either
 *     because nothing has been fetched yet this session, or the name does
 *     not match any provider the last response returned.
 */
funwithactivity.app.LastStatuses.find = function(name) {
  const statuses = funwithactivity.app.LastStatuses.statuses_;
  for (let i = 0; i < statuses.length; i++) {
    if (statuses[i].name === name) return statuses[i];
  }
  return null;
};
