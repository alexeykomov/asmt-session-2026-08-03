//
//  FWASourceStatusFormatting.h
//  FunWithActivity
//
//  Small shared rendering helpers for FWASourcesViewController (the list)
//  and FWASourceDetailViewController (the detail screen it pushes), so the
//  two screens cannot drift on latency formatting or status colour the way
//  they would if each hand-rolled its own. None of this re-derives the
//  skipped-vs-degraded decision — that is made exactly once, by
//  FWAProviderStatusPresentation (see its header doc) — these functions only
//  take its answer (a nil-for-ok / non-nil-for-not-ok presentation) and turn
//  it into UI text/colour.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FWAProviderStatusPresentation.h"

@class ProviderStatus;

NS_ASSUME_NONNULL_BEGIN

/// "123 ms", or "—" for latencyMs <= 0 — the stub fallback returns in
/// microseconds and a column of "0 ms" reads as broken.
NSString *FWALatencyText(int64_t latencyMs);

/// "ok" / "skipped" / "degraded". Pass nil for the ok case —
/// FWAProviderStatusPresentation produces no entry for ok statuses.
NSString *FWAStatusWord(FWAProviderStatusPresentation *_Nullable presentation);

/// The named Assets.xcassets colour for the status word/dot — StatusOK /
/// StatusSkipped / StatusDegraded — the single source of truth for these
/// three colours across the app (list, detail, and the Recommendations
/// banner). Pass nil for the ok case.
UIColor *FWAStatusColor(FWAProviderStatusPresentation *_Nullable presentation);

/// Short, list-safe reason text: "timed out", "unavailable", or
/// "skipped — no birth date". Never the full `error`, which can embed an
/// entire vendor URL — see FWASourcesViewController's header doc for why
/// that must not land in the list. `presentation` must be non-nil (ok has
/// nothing to summarise; callers already skip this for ok). Does not
/// re-derive skipped-vs-degraded — it only sub-classifies the severity
/// FWAProviderStatusPresentation already decided, by sniffing `error` for a
/// timeout signal on the degraded path.
NSString *FWAShortStatusReason(FWAProviderStatusPresentation *presentation, ProviderStatus *status);

NS_ASSUME_NONNULL_END
