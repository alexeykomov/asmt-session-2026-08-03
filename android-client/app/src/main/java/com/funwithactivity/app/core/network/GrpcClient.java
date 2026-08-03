package com.funwithactivity.app.core.network;

import funwithactivity.recommendations.v1.Recommendations.GetRecommendationsRequest;
import funwithactivity.recommendations.v1.Recommendations.GetRecommendationsResponse;
import funwithactivity.recommendations.v1.RecommendationsServiceGrpc;

import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.Metadata;
import io.grpc.stub.MetadataUtils;

import java.util.concurrent.TimeUnit;

/**
 * Thin wrapper around the single gRPC channel used for the whole app.
 * All stub calls are blocking — callers must invoke them from a background
 * thread and marshal results back to the UI thread themselves.
 */
public class GrpcClient {

    private static final Metadata.Key<String> AUTHORIZATION_KEY =
        Metadata.Key.of("authorization", Metadata.ASCII_STRING_MARSHALLER);

    /**
     * Client-side deadline for the whole unary call. The server's own
     * per-provider budget is 2s and providers are fanned out in parallel, so
     * a healthy response is well inside this; 10s just needs to cover a cold
     * TLS handshake against a cold-start vendor without ever letting the UI
     * spin indefinitely. On expiry the blocking stub throws
     * StatusRuntimeException(DEADLINE_EXCEEDED), which callers already
     * handle through their normal RPC-failure path — no special-casing
     * needed here.
     */
    private static final long DEADLINE_SECONDS = 10;

    private final ManagedChannel channel;
    private final String authToken;

    /**
     * @param serverHost host:port for the RecommendationsService edge (see
     *     BuildConfig.SERVER_HOST / app/build.gradle serverHost property).
     * @param useTls whether to negotiate TLS (grpc-okhttp transport) or use
     *     a plaintext channel (see BuildConfig.SERVER_TLS / serverTls
     *     property). MUST match serverHost: the live TLS edge only speaks
     *     TLS, the local dev app-server only speaks plaintext — host and
     *     transport are one setting, not two independent knobs, and must be
     *     changed together when repointing during a demo.
     * @param authToken bearer token sent as `authorization: Bearer <token>`
     *     metadata on every call, matching the app-server's
     *     INTERNAL_GRPC_TOKEN auth interceptor (see BuildConfig.SERVER_TOKEN
     *     / serverToken property). MUST be changed together with
     *     serverHost/useTls — the three describe one endpoint, not three
     *     independent knobs. Pass null or empty to send no auth header.
     */
    public GrpcClient(String serverHost, boolean useTls, String authToken) {
        ManagedChannelBuilder<?> builder = ManagedChannelBuilder.forTarget(serverHost);
        if (useTls) {
            builder.useTransportSecurity();
        } else {
            builder.usePlaintext();
        }
        this.channel = builder.build();
        this.authToken = authToken;
    }

    /** Blocking — call from a background thread. */
    public GetRecommendationsResponse getRecommendations(GetRecommendationsRequest request) {
        RecommendationsServiceGrpc.RecommendationsServiceBlockingStub stub =
            RecommendationsServiceGrpc.newBlockingStub(channel)
                .withDeadlineAfter(DEADLINE_SECONDS, TimeUnit.SECONDS);
        if (authToken != null && !authToken.isEmpty()) {
            Metadata headers = new Metadata();
            headers.put(AUTHORIZATION_KEY, "Bearer " + authToken);
            stub = stub.withInterceptors(MetadataUtils.newAttachHeadersInterceptor(headers));
        }
        return stub.getRecommendations(request);
    }

    public ManagedChannel getChannel() {
        return channel;
    }
}
