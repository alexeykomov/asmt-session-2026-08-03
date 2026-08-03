package main

import (
	"context"
	"testing"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	"github.com/stretchr/testify/require"
)

// noopHandler is a stand-in grpc.UnaryHandler that just proves the
// interceptor let the call through to "the RPC".
func noopHandler(_ context.Context, _ any) (any, error) {
	return "ok", nil
}

func withAuthHeader(token string) context.Context {
	return metadata.NewIncomingContext(context.Background(),
		metadata.Pairs("authorization", "Bearer "+token))
}

func TestAuthInterceptor_ValidTokenSucceeds(t *testing.T) {
	interceptor := authInterceptor("secret123", false)
	info := &grpc.UnaryServerInfo{FullMethod: "/funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations"}

	resp, err := interceptor(withAuthHeader("secret123"), nil, info, noopHandler)

	require.NoError(t, err)
	require.Equal(t, "ok", resp)
}

func TestAuthInterceptor_WrongTokenRejected(t *testing.T) {
	interceptor := authInterceptor("secret123", false)
	info := &grpc.UnaryServerInfo{FullMethod: "/funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations"}

	_, err := interceptor(withAuthHeader("wrong"), nil, info, noopHandler)

	require.Error(t, err)
	require.Equal(t, codes.Unauthenticated, status.Code(err))
}

func TestAuthInterceptor_MissingCredentialsRejected(t *testing.T) {
	interceptor := authInterceptor("secret123", false)
	info := &grpc.UnaryServerInfo{FullMethod: "/funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations"}

	_, err := interceptor(context.Background(), nil, info, noopHandler)

	require.Error(t, err)
	require.Equal(t, codes.Unauthenticated, status.Code(err))
}

// CR-009: an unset token must fail closed, not silently authenticate nothing.
func TestAuthInterceptor_UnsetTokenFailsClosedByDefault(t *testing.T) {
	interceptor := authInterceptor("", false)
	info := &grpc.UnaryServerInfo{FullMethod: "/funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations"}

	_, err := interceptor(context.Background(), nil, info, noopHandler)

	require.Error(t, err)
	require.Equal(t, codes.Unauthenticated, status.Code(err))
}

// Same as above, but with credentials attached — an unset server token
// still must not serve the RPC, because there is nothing to validate
// against and silently accepting any caller is exactly the fail-open bug.
func TestAuthInterceptor_UnsetTokenFailsClosedEvenWithCredentials(t *testing.T) {
	interceptor := authInterceptor("", false)
	info := &grpc.UnaryServerInfo{FullMethod: "/funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations"}

	_, err := interceptor(withAuthHeader("anything"), nil, info, noopHandler)

	require.Error(t, err)
	require.Equal(t, codes.Unauthenticated, status.Code(err))
}

// CR-009: the explicit opt-out restores the old behaviour, for local
// dev / docker-compose only.
func TestAuthInterceptor_UnsetTokenAllowedWithExplicitOptOut(t *testing.T) {
	interceptor := authInterceptor("", true)
	info := &grpc.UnaryServerInfo{FullMethod: "/funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations"}

	resp, err := interceptor(context.Background(), nil, info, noopHandler)

	require.NoError(t, err)
	require.Equal(t, "ok", resp)
}

func TestAuthInterceptor_HealthBypassesAuthRegardlessOfTokenState(t *testing.T) {
	for _, tokenState := range []struct {
		name          string
		token         string
		allowInsecure bool
	}{
		{"token set", "secret123", false},
		{"token unset, fail-closed", "", false},
		{"token unset, opt-out", "", true},
	} {
		t.Run(tokenState.name, func(t *testing.T) {
			interceptor := authInterceptor(tokenState.token, tokenState.allowInsecure)
			info := &grpc.UnaryServerInfo{FullMethod: "/grpc.health.v1.Health/Check"}

			resp, err := interceptor(context.Background(), nil, info, noopHandler)

			require.NoError(t, err)
			require.Equal(t, "ok", resp)
		})
	}
}

func TestAuthInterceptor_ReflectionBypassesAuthRegardlessOfTokenState(t *testing.T) {
	for _, method := range []string{
		"/grpc.reflection.v1.ServerReflection/ServerReflectionInfo",
		"/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo",
	} {
		for _, tokenState := range []struct {
			name          string
			token         string
			allowInsecure bool
		}{
			{"token set", "secret123", false},
			{"token unset, fail-closed", "", false},
		} {
			t.Run(method+"/"+tokenState.name, func(t *testing.T) {
				interceptor := authInterceptor(tokenState.token, tokenState.allowInsecure)
				info := &grpc.UnaryServerInfo{FullMethod: method}

				resp, err := interceptor(context.Background(), nil, info, noopHandler)

				require.NoError(t, err)
				require.Equal(t, "ok", resp)
			})
		}
	}
}
