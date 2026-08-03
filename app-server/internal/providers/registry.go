package providers

import (
	"log/slog"
	"os"
)

// DefaultProviders builds the runtime provider list from environment.
//
// To add a provider: implement Provider in a new file, then append one line
// here wrapped in WithFaults so it participates in the resilience demo.
// See docs/integrations/_template.md.
//
// Stub providers are opt-in only, via USE_STUB_PROVIDERS=true. They never
// engage automatically — not when PROVIDER1_URL/PROVIDER2_URL are empty,
// not when a real provider errors. Silently substituting fake data for a
// failed or unconfigured real call is exactly how someone ends up demoing
// fiction believing it is real.
func DefaultProviders() []Provider {
	if os.Getenv("USE_STUB_PROVIDERS") == "true" {
		slog.Warn("USE_STUB_PROVIDERS=true: serving canned recommendations, not live vendor data",
			"providers", []string{"service1-stub", "service2-stub"})
		return []Provider{
			WithFaults(NewService1Stub()),
			WithFaults(NewService2Stub()),
		}
	}

	return []Provider{
		WithFaults(NewService1("service1", os.Getenv("PROVIDER1_URL"))),
		WithFaults(NewService2("service2", os.Getenv("PROVIDER2_URL"))),
	}
}
