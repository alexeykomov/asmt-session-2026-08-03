/**
 * @fileoverview Classifies a provider status for presentation.
 *
 * Extracted so the branch ORDER can be pinned by a test. iOS and Android
 * each have an equivalent; web previously had only a comment, and inverting
 * this order has caused four defects in this project.
 */

goog.provide('funwithactivity.features.recommendations.classify');
goog.provide('funwithactivity.features.recommendations.shortReason');

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


/**
 * A short, presenter-safe reason for a non-ok provider status — for the
 * Sources LIST, which must never print `status.error` verbatim: a real
 * provider failure's `error` field is the raw text
 * `%s: [%d] %s (%s)`-formatted server-side (app-server/internal/domain/
 * errors.go), and for a genuine timeout that raw text embeds the full
 * vendor URL (e.g. `service1: [0] Post "https://…lambda-url…": context
 * deadline exceeded (transient)`) — exactly what got projected during a
 * prior presentation and must not happen again. The full text still
 * belongs on the Source detail screen's STATUS section, where an operator
 * needs it; see funwithactivity.sources.SourceDetailComponent.
 *
 * Calls classify() rather than re-deriving skipped-vs-degraded — that
 * branch has exactly one implementation in this project, by design.
 * @param {!funwithactivity.dto.ProviderStatus} status
 * @return {string} '' for ok (nothing to explain); otherwise a short
 *     phrase such as 'timed out', 'unavailable', or
 *     'skipped — no birth date'.
 */
funwithactivity.features.recommendations.shortReason = function(status) {
  const classification =
      funwithactivity.features.recommendations.classify(status);
  if (classification === 'ok') return '';
  if (classification === 'skipped') return 'skipped — no birth date';
  // 'degraded': never surface status.error itself here — see the fileoverview
  // note above. `faults.ModeTimeout` (app-server/internal/providers/
  // fault.go) returns ctx.Err() verbatim ("context deadline exceeded"), and
  // a genuinely slow real vendor call fails the same way once the
  // aggregator's per-provider context.WithTimeout fires, so this phrase
  // check is deliberately on the *message text*, not a status code the wire
  // doesn't carry.
  return /deadline exceeded/i.test(status.error) ? 'timed out' : 'unavailable';
};
