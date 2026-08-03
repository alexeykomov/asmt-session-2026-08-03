// Package faults carries demo-only fault injection settings on the request
// context. Per-request rather than global so the demo needs no restart and
// two people can drive it concurrently.
package faults

import "context"

type Mode string

const (
	ModeNone      Mode = ""
	ModeError     Mode = "error"
	ModeTimeout   Mode = "timeout"
	ModeMalformed Mode = "malformed"
)

// Parse maps untrusted input onto a closed set. Anything unrecognised is
// ModeNone — never build a mode from arbitrary request bytes.
func Parse(s string) Mode {
	switch Mode(s) {
	case ModeError:
		return ModeError
	case ModeTimeout:
		return ModeTimeout
	case ModeMalformed:
		return ModeMalformed
	default:
		return ModeNone
	}
}

type ctxKey struct{}

func WithModes(ctx context.Context, modes map[string]Mode) context.Context {
	return context.WithValue(ctx, ctxKey{}, modes)
}

func For(ctx context.Context, provider string) Mode {
	modes, ok := ctx.Value(ctxKey{}).(map[string]Mode)
	if !ok {
		return ModeNone
	}
	return modes[provider]
}
