//
//  FWASourceStatusFormatting.m
//  FunWithActivity
//

#import "FWASourceStatusFormatting.h"
#import "Recommendations.pbobjc.h"

NSString *FWALatencyText(int64_t latencyMs) {
    return latencyMs > 0 ? [NSString stringWithFormat:@"%lld ms", (long long)latencyMs] : @"—";
}

NSString *FWAStatusWord(FWAProviderStatusPresentation *presentation) {
    if (presentation == nil) {
        return @"ok";
    }
    return presentation.severity == FWAProviderStatusSeverityInfo ? @"skipped" : @"degraded";
}

UIColor *FWAStatusColor(FWAProviderStatusPresentation *presentation) {
    if (presentation == nil) {
        return [UIColor colorNamed:@"StatusOK"];
    }
    return presentation.severity == FWAProviderStatusSeverityInfo
        ? [UIColor colorNamed:@"StatusSkipped"]
        : [UIColor colorNamed:@"StatusDegraded"];
}

NSString *FWAShortStatusReason(FWAProviderStatusPresentation *presentation, ProviderStatus *status) {
    if (presentation.severity == FWAProviderStatusSeverityInfo) {
        // Fixed text, not parsed out of `error`: this app has exactly one
        // input a provider can be skipped for — see FWAGRPCClient.h — so
        // there is nothing to disambiguate.
        return @"skipped — no birth date";
    }

    NSString *error = status.error ?: @"";
    BOOL looksLikeTimeout =
        [error rangeOfString:@"deadline exceeded" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [error rangeOfString:@"timed out" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [error rangeOfString:@"timeout" options:NSCaseInsensitiveSearch].location != NSNotFound;

    return looksLikeTimeout ? @"timed out" : @"unavailable";
}
