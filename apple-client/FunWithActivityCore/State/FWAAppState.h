//
//  FWAAppState.h
//  FunWithActivityCore
//
//  Shared, in-memory state for the three-tab shell — measurements, the
//  DEVELOPER fault toggles, and a dirty flag. Mirrors the web client's
//  AppState: the Profile tab writes here; the Recommendations tab reads on
//  every appearance and refetches only when `isDirty`, then clears it. This
//  is the object that makes "change something in Profile, come back to
//  Recommendations, see the result set change" work without either
//  refetching on every tab switch (burns a vendor call, the vendors are
//  flaky) or never refetching (the app looks like it ignored the edit).
//
//  Lives in FunWithActivityCore per house rule: models live in the shared
//  library, the app target only renders. Not persisted — this is
//  session-only state, same lifetime as the process.
//

#import <Foundation/Foundation.h>

@class GetRecommendationsResponse;
@class ProviderStatus;

NS_ASSUME_NONNULL_BEGIN

/// Posted whenever -recordResponse: updates `lastStatuses`/`providerNames`,
/// so a visible Sources screen can refresh even though it did not itself
/// trigger the fetch that produced the new data.
extern NSString *const FWAAppStateDidUpdateStatusesNotification;

/// Demo-only fault-injection modes, matching app-server's
/// internal/faults.Mode wire values exactly (see faults.go) — these strings
/// go straight into the GetRecommendationsRequest.faults map.
extern NSString *const FWAFaultModeError;
extern NSString *const FWAFaultModeTimeout;
extern NSString *const FWAFaultModeMalformed;

@interface FWAAppState : NSObject

#pragma mark - Measurements (Profile → MEASUREMENTS)

@property (nonatomic, assign) double heightCm;
@property (nonatomic, assign) double weightKg;

/// Birth date, explicitly clearable — nil means "not supplied", the wire
/// convention that routes the birth-date-requiring provider to a `skipped`
/// status rather than an error. Clearing this is the data-minimisation demo
/// beat (§7 of the tabbed UI design).
@property (nonatomic, strong, nullable) NSDate *birthDate;

#pragma mark - Developer fault injection (Profile → DEVELOPER)

/// Exactly two entries, one per configured provider, in the order the most
/// recent response reported them. Defaults to @[@"service1", @"service2"]
/// before any response has been seen (production adapter names) — a local
/// app-server run with USE_STUB_PROVIDERS=true reports "service1-stub" /
/// "service2-stub" instead, and this array is updated to match after the
/// first fetch so fault toggles always key against the name the server is
/// actually checking.
@property (nonatomic, strong, readonly) NSArray<NSString *> *providerNames;

/// Index-addressed (not name-keyed) deliberately: a switch the user has
/// already flipped must not silently reset if the resolved provider name
/// changes between when they flipped it and when a response arrives.
- (BOOL)faultEnabledAtIndex:(NSUInteger)index;
- (void)setFaultEnabled:(BOOL)enabled atIndex:(NSUInteger)index;

/// One of FWAFaultModeError / FWAFaultModeTimeout / FWAFaultModeMalformed.
/// Defaults to FWAFaultModeError. Meaningful only once the switch at the
/// same index is enabled — callers should disable the mode control
/// otherwise, matching §5.4: "Mode selectors are disabled until their
/// toggle is on."
- (NSString *)faultModeAtIndex:(NSUInteger)index;
- (void)setFaultMode:(NSString *)mode atIndex:(NSUInteger)index;

#pragma mark - Dirty flag

/// YES once any measurement or fault setting has changed since the last
/// -clearDirty call. The Recommendations screen is the only reader/clearer
/// of this — see its -viewWillAppear:.
@property (nonatomic, assign, readonly) BOOL isDirty;

- (void)clearDirty;

#pragma mark - Most recent fetch result (shared with Sources)

/// Statuses from the most recently completed GetRecommendations response,
/// or nil before the first fetch completes. `ListSources`-equivalent data
/// for tab 2 in Phase 1: the Sources screen has nothing else to read from —
/// there is no separate registry RPC yet — so it renders this.
@property (nonatomic, strong, readonly, nullable) NSArray<ProviderStatus *> *lastStatuses;

/// Called by the Recommendations screen after every completed fetch
/// (success only — a transport-level failure has no statuses to record).
/// Updates `lastStatuses` and, from the same response, `providerNames`;
/// posts FWAAppStateDidUpdateStatusesNotification. Does not touch the dirty
/// flag — that is cleared explicitly by the caller once it has finished
/// applying the response, independent of what this method does.
- (void)recordResponse:(GetRecommendationsResponse *)response;

/// Builds the `faults` map for FWAGRPCClient: provider name (from
/// `providerNames`, index-matched) → mode string, one entry per enabled
/// switch. Returns nil when nothing is enabled, matching FWAGRPCClient's
/// "pass nil in normal use" contract.
- (nullable NSDictionary<NSString *, NSString *> *)faultsForRequest;

@end

NS_ASSUME_NONNULL_END
