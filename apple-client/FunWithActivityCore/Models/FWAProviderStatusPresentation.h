//
//  FWAProviderStatusPresentation.h
//  FunWithActivityCore
//
//  Turns a ProviderStatus into UI-ready banner text/severity. Kept in Core
//  (models live in the shared library; the app target only renders) so the
//  one rule that matters is defined exactly once:
//
//  ALWAYS branch on `skipped` before `error`. A skipped status also carries
//  text in `error` (it reuses the field for the human-readable reason), so
//  checking `error` first renders privacy-preserving GDPR data-minimisation
//  ("user declined to supply birth date") as if it were a service outage.
//  That exact inversion has already caused three defects on this project —
//  do not "simplify" this by checking error.length first.
//

#import <Foundation/Foundation.h>

@class ProviderStatus;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FWAProviderStatusSeverity) {
    /// ok == true. Never produced by
    /// +presentationsForStatuses: — normal statuses need no banner.
    FWAProviderStatusSeverityOK = 0,
    /// ok == false, skipped == true. Not a failure — the user declined an
    /// input this provider needs. Render informationally, not as an error.
    FWAProviderStatusSeverityInfo,
    /// ok == false, skipped == false. A genuine outage.
    FWAProviderStatusSeverityDegraded,
};

@interface FWAProviderStatusPresentation : NSObject

@property (nonatomic, copy, readonly) NSString *providerName;
@property (nonatomic, assign, readonly) FWAProviderStatusSeverity severity;
@property (nonatomic, copy, readonly) NSString *message;

/// Builds one presentation per non-ok status. `ok == true` statuses are
/// omitted — they need no banner.
+ (NSArray<FWAProviderStatusPresentation *> *)presentationsForStatuses:(NSArray<ProviderStatus *> *)statuses;

/// Builds a presentation that is NOT derived from a wire `ProviderStatus` —
/// for callers (FWARecommendationsViewController) that need to show a
/// combined banner once they know the empty-results condition
/// (recommendations.count == 0) that this class deliberately has no opinion
/// on. Does not participate in, and must never be used to re-derive, the
/// skipped-vs-degraded classification above — callers must obtain `severity`
/// from a presentation this class already classified via
/// +presentationsForStatuses:, never invent one.
+ (instancetype)presentationWithProviderName:(NSString *)providerName
                                     severity:(FWAProviderStatusSeverity)severity
                                      message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
