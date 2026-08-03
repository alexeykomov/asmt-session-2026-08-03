package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/joho/godotenv"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	recommendationsv1 "github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api"
	"github.com/funwithactivity/funwithactivity/app-server/internal/aggregator"
	"github.com/funwithactivity/funwithactivity/app-server/internal/grpcservice"
	"github.com/funwithactivity/funwithactivity/app-server/internal/providers"
	"github.com/funwithactivity/funwithactivity/app-server/internal/ranking"
)

func main() {
	_ = godotenv.Load()
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	grpcPort := envOrDefault("GRPC_PORT", "50051")
	httpPort := envOrDefault("HEALTH_HTTP_PORT", "50052")
	timeoutMs := envInt("PROVIDER_TIMEOUT_MS", 2000)
	internalToken := os.Getenv("INTERNAL_GRPC_TOKEN")
	allowInsecureGRPC := strings.EqualFold(os.Getenv("ALLOW_INSECURE_GRPC"), "true")

	if internalToken == "" {
		if allowInsecureGRPC {
			// Explicit opt-out: someone deliberately chose to run without
			// authentication (local dev / docker-compose). Loud on purpose —
			// this must never be the quiet default.
			slog.Warn("INTERNAL_GRPC_TOKEN is unset; serving all RPCs without authentication because ALLOW_INSECURE_GRPC=true. Do not use this for any customer-facing deployment.")
		} else {
			// Fail closed: a deployment that silently lost its secret must
			// not keep serving traffic wide open. Health/reflection remain
			// exempt (see authInterceptor) so probes still work.
			slog.Error("INTERNAL_GRPC_TOKEN is unset; refusing to serve non-health/reflection RPCs. Set INTERNAL_GRPC_TOKEN, or set ALLOW_INSECURE_GRPC=true to explicitly run without auth (local development only).")
		}
	}

	provs := providers.DefaultProviders()
	ranker := ranking.NewWeightedNormalized(parseWeights(os.Getenv("RANKER_WEIGHTS")))
	agg := aggregator.New(provs, time.Duration(timeoutMs)*time.Millisecond, aggregator.NoopCache{}, ranker)
	srv := grpcservice.New(agg)

	grpcSrv := grpc.NewServer(grpc.UnaryInterceptor(authInterceptor(internalToken, allowInsecureGRPC)))
	recommendationsv1.RegisterRecommendationsServiceServer(grpcSrv, srv)

	healthSrv := health.NewServer()
	healthSrv.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	healthpb.RegisterHealthServer(grpcSrv, healthSrv)

	reflection.Register(grpcSrv)

	listener, err := net.Listen("tcp", ":"+grpcPort)
	if err != nil {
		slog.Error("listen failed", "port", grpcPort, "error", err)
		os.Exit(1)
	}

	httpSrv := startHealthSidecar(httpPort)

	slog.Info("grpc server starting",
		"port", grpcPort,
		"providers", providerNames(provs),
		"provider_timeout_ms", timeoutMs,
		"auth_enabled", internalToken != "",
		"allow_insecure_grpc", allowInsecureGRPC)

	go func() {
		if err := grpcSrv.Serve(listener); err != nil {
			slog.Error("grpc serve failed", "error", err)
			os.Exit(1)
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh
	slog.Info("shutdown signal received")

	grpcSrv.GracefulStop()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(shutdownCtx)
}

// startHealthSidecar exposes an HTTP /health endpoint on a separate port.
// App Platform / Kubernetes / Docker health checks speak HTTP, not gRPC, so
// the gRPC port alone is unprobeable. Co-locating both ports in one process
// keeps the deployment unit simple.
func startHealthSidecar(port string) *http.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		slog.Info("http health sidecar starting", "port", port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("http health sidecar failed", "error", err)
		}
	}()
	return srv
}

func authInterceptor(token string, allowInsecure bool) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		// Liveness and reflection bypass auth so probes still work.
		if strings.HasPrefix(info.FullMethod, "/grpc.health.v1.") ||
			strings.HasPrefix(info.FullMethod, "/grpc.reflection.") {
			return handler(ctx, req)
		}
		if token == "" {
			// Fail closed unless explicitly opted out: a deployment that
			// silently lost its secret must not keep serving traffic wide
			// open. See the startup log for why.
			if allowInsecure {
				return handler(ctx, req)
			}
			return nil, status.Error(codes.Unauthenticated, "server auth misconfigured: INTERNAL_GRPC_TOKEN is unset and ALLOW_INSECURE_GRPC is not set")
		}
		md, ok := metadata.FromIncomingContext(ctx)
		if !ok {
			return nil, status.Error(codes.Unauthenticated, "missing metadata")
		}
		vals := md.Get("authorization")
		if len(vals) == 0 || vals[0] != "Bearer "+token {
			return nil, status.Error(codes.Unauthenticated, "invalid token")
		}
		return handler(ctx, req)
	}
}

func providerNames(ps []providers.Provider) []string {
	out := make([]string, len(ps))
	for i, p := range ps {
		out[i] = p.Name()
	}
	return out
}

func envOrDefault(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func envInt(k string, d int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return d
}

// parseWeights reads "service1=0.8,service2=1.0" into a ranker weight map.
// Malformed entries are ignored rather than fatal — a bad env var must not
// take the demo down mid-session.
func parseWeights(s string) map[string]float64 {
	out := map[string]float64{}
	for _, pair := range strings.Split(s, ",") {
		k, v, ok := strings.Cut(strings.TrimSpace(pair), "=")
		if !ok {
			continue
		}
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			out[k] = f
		}
	}
	return out
}
