package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCheck(t *testing.T) {
	for _, tc := range []struct {
		name, version, expected string
		unhealthy, fail         bool
	}{
		{name: "valid", version: "abc", expected: "abc"},
		{name: "old release", version: "old", expected: "new", fail: true},
		{name: "unhealthy", version: "abc", unhealthy: true, fail: true},
		{name: "missing version", fail: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/healthz":
					if tc.unhealthy {
						http.Error(w, "unavailable", 503)
						return
					}
					fmt.Fprintln(w, "ok")
				case "/readyz":
					fmt.Fprintln(w, "ready")
				case "/version":
					fmt.Fprintf(w, `{"version":%q}`, tc.version)
				default:
					http.NotFound(w, r)
				}
			}))
			defer server.Close()
			err := check(context.Background(), server.Client(), server.URL, tc.expected)
			if (err != nil) != tc.fail {
				t.Fatalf("got error %v, want failure %v", err, tc.fail)
			}
		})
	}
}
