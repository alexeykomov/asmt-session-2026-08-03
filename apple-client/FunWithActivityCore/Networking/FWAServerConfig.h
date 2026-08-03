//
//  FWAServerConfig.h
//  FunWithActivityCore
//
//  Build-time constants for the RecommendationsService gRPC endpoint: host,
//  transport, AND credential. The demo host WILL be repointed live in front
//  of a customer — when that happens, FWA_GRPC_HOST, FWA_GRPC_USE_TLS, and
//  FWA_GRPC_TOKEN (or their NSUserDefaults launch-argument overrides below)
//  MUST be changed TOGETHER. They are not independent settings: the TLS
//  edge only speaks TLS and requires the matching bearer token, while the
//  local dev server only speaks plaintext and requires its own token — so
//  pointing the host at one while the transport or credential is set for
//  the other doesn't fail loudly, it just hangs/fails (or gets rejected
//  with Unauthenticated) in a way that's confusing to debug on stage.
//
//  Defaults below are safe, non-real placeholders (localhost:50051, plain
//  TLS on) — this header ships in a public repo, so it must not bake in any
//  real infrastructure address. The real deployed edge comes from the
//  repo-root .env's GRPC_HOST, via Config/generate-xcconfig.sh (see that
//  script's header doc for the one manual Xcode step it requires). For
//  offline work against a local app-server, override all three to
//  localhost:51100 (simulator) / plaintext / that server's
//  INTERNAL_GRPC_TOKEN.
//
//  The NSUserDefaults launch-argument overrides below are compiled in for
//  DEBUG builds only. Anything able to write app defaults on a shipped
//  (Release) build must not be able to repoint it at an attacker-controlled
//  host, downgrade it off TLS, or swap its credential — so Release always
//  uses the build-time constants above, full stop.
//

#import <Foundation/Foundation.h>

#ifndef FWA_GRPC_HOST
#define FWA_GRPC_HOST "localhost:50051"
#endif

#ifndef FWA_GRPC_USE_TLS
#define FWA_GRPC_USE_TLS 1
#endif

#ifndef FWA_GRPC_TOKEN
#define FWA_GRPC_TOKEN ""
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FWAServerConfig : NSObject

/// host:port for the RecommendationsService gRPC endpoint. Defaults to the
/// placeholder localhost:50051 unless overridden at build time (see
/// Config/generate-xcconfig.sh, which fills this in from the repo-root
/// .env's GRPC_HOST). Overridable in DEBUG builds only, at demo time, via
/// the `-FWA_GRPC_HOST <host:port>` launch argument — see `+useTLS`, which
/// MUST be overridden to match whenever this is. Release builds always use
/// the build-time constant.
@property (class, nonatomic, readonly) NSString *grpcHost;

/// Whether to use TLS for the gRPC channel. Defaults to YES, matching a
/// deployed edge with a publicly-trusted certificate (no ATS exception
/// needed). Overridable in DEBUG builds only, at demo time, via
/// the `-FWA_GRPC_USE_TLS <YES|NO>` launch argument — MUST be changed
/// together with `+grpcHost` (e.g. NO + localhost:51100 for the plaintext
/// local server), or requests silently fail against a mismatched endpoint.
/// Release builds always use the build-time constant.
@property (class, nonatomic, readonly) BOOL useTLS;

/// Bearer token sent as `authorization: Bearer <token>` metadata on every
/// RecommendationsService call, matching the app-server's
/// `INTERNAL_GRPC_TOKEN` auth interceptor. Defaults to empty (no
/// `FWA_GRPC_TOKEN` build setting defined) — set `FWA_GRPC_TOKEN` at build
/// time to the deployed edge's token before shipping a build that must
/// authenticate against it. Overridable in DEBUG builds only, at demo time,
/// via the `-FWA_GRPC_TOKEN <token>` launch argument — MUST be changed
/// together with `+grpcHost` and `+useTLS` (see their docs): the three
/// describe one endpoint, not three independent knobs. Release builds
/// always use the build-time constant.
@property (class, nonatomic, readonly) NSString *grpcToken;

@end

NS_ASSUME_NONNULL_END
