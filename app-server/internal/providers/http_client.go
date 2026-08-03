package providers

import (
	"net/http"
	"time"
)

// Hard cap on any provider response. Guards against a misbehaving upstream
// OOMing the server.
const maxResponseBytes = 8 * 1024 * 1024

// The per-call context.WithTimeout in the aggregator is the authoritative
// deadline; this transport timeout is a safety net set well above it.
// Built once at package init — never per call.
var sharedHTTPClient = &http.Client{
	Timeout: 30 * time.Second,
	Transport: &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 32,
		IdleConnTimeout:     90 * time.Second,
	},
}
