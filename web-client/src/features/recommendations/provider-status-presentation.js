/**
 * @fileoverview Classifies a provider status for presentation.
 *
 * Extracted so the branch ORDER can be pinned by a test. iOS and Android
 * each have an equivalent; web previously had only a comment, and inverting
 * this order has caused four defects in this project.
 */

goog.provide('funwithactivity.features.recommendations.classify');

goog.require('funwithactivity.dto.ProviderStatus');


/**
 * Skipped is tested BEFORE the error text, and that order is load-bearing:
 * a skipped provider also populates `error` with an explanation, so testing
 * `error` first renders deliberate data minimisation as an outage.
 *
 * @param {!funwithactivity.dto.ProviderStatus} status
 * @return {string} 'ok' | 'skipped' | 'degraded'
 */
funwithactivity.features.recommendations.classify = function(status) {
  // `ok && skipped` cannot happen: app-server/internal/aggregator/aggregator.go:93-97
  // never sets OK on a skipped status. This invariant is server-guaranteed,
  // which is also why iOS and Android are free to order these two checks
  // differently from each other and from here.
  if (status.ok) return 'ok';
  if (status.skipped) return 'skipped';
  return 'degraded';
};
