package aggregator

import "context"

// Cache is where Redis plugs in. The default is NoopCache, so the swap is a
// constructor argument and nothing in Aggregate() changes — this is the most
// likely live-coding request ("now add caching").
//
// Implementations must be safe for concurrent use: Aggregate may call Get
// and Set from multiple in-flight requests at once.
type Cache interface {
	Get(ctx context.Context, key string) (Result, bool)
	Set(ctx context.Context, key string, val Result)
}

type NoopCache struct{}

func (NoopCache) Get(context.Context, string) (Result, bool) { return Result{}, false }
func (NoopCache) Set(context.Context, string, Result)        {}
