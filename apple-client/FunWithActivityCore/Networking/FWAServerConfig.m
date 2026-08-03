//
//  FWAServerConfig.m
//  FunWithActivityCore
//

#import "FWAServerConfig.h"

@implementation FWAServerConfig

+ (NSString *)grpcHost {
#if DEBUG
    // Launch-argument override for demo convenience, e.g.:
    //   -FWA_GRPC_HOST 192.168.1.50:50051
    // Does not replace the build-time constant as the source of truth —
    // just a faster knob than rebuilding when repointing on stage.
    // Remember to pass -FWA_GRPC_USE_TLS / -FWA_GRPC_TOKEN to match — see
    // header doc. DEBUG-only: anything able to write app defaults on a
    // shipped build must not be able to repoint it at an attacker-controlled
    // host (a MITM vector), so this override does not exist in Release.
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"FWA_GRPC_HOST"];
    if (override.length > 0) {
        return override;
    }
#endif
    return @(FWA_GRPC_HOST);
}

+ (BOOL)useTLS {
#if DEBUG
    // Launch-argument override, e.g. -FWA_GRPC_USE_TLS NO — MUST be changed
    // together with -FWA_GRPC_HOST (see header doc): the two settings
    // describe one endpoint, not two independent knobs. DEBUG-only: leaving
    // this live in Release would let anything able to write app defaults
    // downgrade the connection to plaintext (a downgrade vector).
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"FWA_GRPC_USE_TLS"] != nil) {
        return [[NSUserDefaults standardUserDefaults] boolForKey:@"FWA_GRPC_USE_TLS"];
    }
#endif
    return FWA_GRPC_USE_TLS;
}

+ (NSString *)grpcToken {
#if DEBUG
    // Launch-argument override, e.g. -FWA_GRPC_TOKEN testtoken123 — MUST be
    // changed together with -FWA_GRPC_HOST / -FWA_GRPC_USE_TLS (see header
    // doc): the three describe one endpoint, not three independent knobs.
    // DEBUG-only, matching the other two overrides it moves together with.
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"FWA_GRPC_TOKEN"];
    if (override.length > 0) {
        return override;
    }
#endif
    return @(FWA_GRPC_TOKEN);
}

@end
