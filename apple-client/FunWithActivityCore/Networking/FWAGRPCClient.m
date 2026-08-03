//
//  FWAGRPCClient.m
//  FunWithActivityCore
//

#import "FWAGRPCClient.h"
#import "FWAServerConfig.h"
#import "Recommendations.pbobjc.h"
#import "Recommendations.pbrpc.h"
#import <ProtoRPC/ProtoRPC.h>
#import <GRPCClient/GRPCCallOptions.h>
#import <GRPCClient/GRPCTransport.h>
#import <os/log.h>

static os_log_t FWANetworkLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.funwithactivity.ios", "network");
    });
    return log;
}

#pragma mark - Response handler

@interface FWAUnaryResponseHandler : NSObject <GRPCProtoResponseHandler>

@property (nonatomic, copy) void (^completionBlock)(GPBMessage *_Nullable response, NSError *_Nullable error);
@property (nonatomic, strong, nullable) GPBMessage *receivedMessage;

- (instancetype)initWithCompletion:(void (^)(GPBMessage *_Nullable, NSError *_Nullable))completion;

@end

@implementation FWAUnaryResponseHandler

- (instancetype)initWithCompletion:(void (^)(GPBMessage *_Nullable, NSError *_Nullable))completion {
    self = [super init];
    if (self) {
        _completionBlock = [completion copy];
    }
    return self;
}

- (dispatch_queue_t)dispatchQueue {
    return dispatch_get_main_queue();
}

- (void)didReceiveProtoMessage:(GPBMessage *)message {
    self.receivedMessage = message;
}

- (void)didCloseWithTrailingMetadata:(NSDictionary *_Nullable)trailingMetadata error:(NSError *_Nullable)error {
    os_log(FWANetworkLog(), "GetRecommendations closed — hasResponse=%d error=%{public}@",
           self.receivedMessage != nil, error);
    if (self.completionBlock) {
        self.completionBlock(self.receivedMessage, error);
    }
}

@end

#pragma mark - FWAGRPCClient

// Client-side deadline for the whole unary call, in seconds. The server's
// own per-provider budget is 2s and providers are fanned out in parallel, so
// a healthy response is well inside this; 10s just needs to cover a cold TLS
// handshake against a cold-start vendor without ever letting the UI spin
// indefinitely. GRPCMutableCallOptions.timeout defaults to 0 (no timeout) —
// without this, a hung vendor left the loading spinner running forever. On
// expiry the call closes with kGRPCErrorDomain/GRPCErrorCodeDeadlineExceeded,
// which flows through the same -didCloseWithTrailingMetadata:error: path —
// and so the same UI failure/retry path — as any other RPC error; no
// special-casing needed here. Matches Android's GrpcClient.DEADLINE_SECONDS.
static const NSTimeInterval kFWAGRPCCallTimeoutSeconds = 10.0;

@interface FWAGRPCClient ()
@property (nonatomic, strong) RecommendationsService *service;
@end

@implementation FWAGRPCClient

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupService];
    }
    return self;
}

- (void)setupService {
    self.service = [RecommendationsService serviceWithHost:[FWAServerConfig grpcHost]
                                                 callOptions:[self callOptions]];
}

- (GRPCMutableCallOptions *)callOptions {
    GRPCMutableCallOptions *options = [[GRPCMutableCallOptions alloc] init];
    options.transport = [FWAServerConfig useTLS]
        ? GRPCDefaultTransportImplList.core_secure
        : GRPCDefaultTransportImplList.core_insecure;
    options.timeout = kFWAGRPCCallTimeoutSeconds;
    // Matches the app-server's authInterceptor, which requires this exact
    // header when INTERNAL_GRPC_TOKEN is configured. Token moves together
    // with host/transport — see FWAServerConfig.h.
    NSString *token = [FWAServerConfig grpcToken];
    if (token.length > 0) {
        options.initialMetadata = @{@"authorization": [@"Bearer " stringByAppendingString:token]};
    }
    return options;
}

- (void)getRecommendationsWithHeightCm:(double)heightCm
                               weightKg:(double)weightKg
                          birthDateUnix:(int64_t)birthDateUnix
                                 faults:(nullable NSDictionary<NSString *, NSString *> *)faults
                             completion:(FWAGetRecommendationsBlock)completion {
    Measurements *measurements = [[Measurements alloc] init];
    measurements.heightCm = heightCm;
    measurements.weightKg = weightKg;
    measurements.birthDateUnix = birthDateUnix;

    GetRecommendationsRequest *request = [[GetRecommendationsRequest alloc] init];
    request.measurements = measurements;
    if (faults.count > 0) {
        request.faults = [faults mutableCopy];
    }

    os_log(FWANetworkLog(), "GetRecommendations starting — host=%{public}@ heightCm=%.1f weightKg=%.1f hasBirthDate=%d",
           [FWAServerConfig grpcHost], heightCm, weightKg, birthDateUnix != 0);

    FWAUnaryResponseHandler *handler = [[FWAUnaryResponseHandler alloc]
        initWithCompletion:^(GPBMessage *_Nullable response, NSError *_Nullable error) {
            if (completion) {
                completion((GetRecommendationsResponse *)response, error);
            }
        }];

    GRPCUnaryProtoCall *call = [self.service getRecommendationsWithMessage:request
                                                            responseHandler:handler
                                                                callOptions:[self callOptions]];
    [call start];
}

@end
