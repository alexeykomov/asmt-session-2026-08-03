package com.funwithactivity.app;

import android.app.Application;

import com.funwithactivity.app.core.network.GrpcClient;

/**
 * Single place for manual dependency construction (no DI framework, per house
 * convention). Holds the one long-lived gRPC channel for the process.
 */
public class FunWithActivityApplication extends Application {

    private GrpcClient grpcClient;

    @Override
    public void onCreate() {
        super.onCreate();
        // BuildConfig.SERVER_HOST / BuildConfig.SERVER_TLS / BuildConfig.SERVER_TOKEN
        // are the easily repointed trio for the demo server address (see
        // app/build.gradle serverHost / serverTls / serverToken properties).
        // They describe one endpoint — always change them together.
        grpcClient = new GrpcClient(BuildConfig.SERVER_HOST, BuildConfig.SERVER_TLS, BuildConfig.SERVER_TOKEN);
    }

    public GrpcClient getGrpcClient() {
        return grpcClient;
    }
}
