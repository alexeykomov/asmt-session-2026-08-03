//
//  FWAGRPCClient.h
//  FunWithActivityCore
//
//  Thin wrapper around the generated RecommendationsService gRPC stub.
//

#import <Foundation/Foundation.h>

@class GetRecommendationsResponse;
@class HealthChartsResponse;

NS_ASSUME_NONNULL_BEGIN

typedef void (^FWAGetRecommendationsBlock)(GetRecommendationsResponse *_Nullable response,
                                            NSError *_Nullable error);

typedef void (^FWAGetHealthChartsBlock)(HealthChartsResponse *_Nullable response,
                                         NSError *_Nullable error);

@interface FWAGRPCClient : NSObject

/// Calls RecommendationsService.GetRecommendations. Pass 0 for
/// birthDateUnix when the user declined to supply it — that is the wire
/// convention "not supplied" (see recommendations.proto), and the server
/// routes around providers that require it, returning a `skipped` status
/// for those rather than treating it as an error.
///
/// `faults` is optional demo-only fault injection (provider name ->
/// "error" | "timeout" | "malformed"); pass nil in normal use.
- (void)getRecommendationsWithHeightCm:(double)heightCm
                               weightKg:(double)weightKg
                          birthDateUnix:(int64_t)birthDateUnix
                                 faults:(nullable NSDictionary<NSString *, NSString *> *)faults
                             completion:(FWAGetRecommendationsBlock)completion;

/// Calls RecommendationsService.GetHealthCharts for the Charts tab.
///
/// Separate call rather than a field on the recommendations response: charts
/// call no vendor and cannot be degraded by one, so bundling them would tie a
/// drawing feature's latency to two cold third-party Lambdas and make a
/// vendor outage look like a chart failure.
///
/// Pass 0 for birthDateUnix when the user declined it — the charts are
/// seeded from whatever is supplied and degrade to a baseline profile.
- (void)getHealthChartsWithHeightCm:(double)heightCm
                            weightKg:(double)weightKg
                       birthDateUnix:(int64_t)birthDateUnix
                          completion:(FWAGetHealthChartsBlock)completion;

@end

NS_ASSUME_NONNULL_END
