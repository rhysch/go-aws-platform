package web

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRoutes(t *testing.T) {
	cases := []struct {
		name, method, path, body string
		status                   int
	}{
		{"home", "GET", "/", "Go AWS Platform: deployed with Terraform, Docker, Caddy and GitHub Actions.\n", 200},
		{"health", "GET", "/healthz", "ok\n", 200},
		{"ready", "GET", "/readyz", "ready\n", 200},
		{"missing", "GET", "/missing", "404 page not found\n", 404},
		{"health rejects POST", "POST", "/healthz", "method not allowed\n", 405},
		{"version rejects DELETE", "DELETE", "/version", "method not allowed\n", 405},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var logs bytes.Buffer
			h := NewHandler("abc123", slog.New(slog.NewJSONHandler(&logs, nil)))
			res := httptest.NewRecorder()
			h.ServeHTTP(res, httptest.NewRequest(tc.method, tc.path, nil))
			if res.Code != tc.status {
				t.Fatalf("status: got %d want %d", res.Code, tc.status)
			}
			if res.Body.String() != tc.body {
				t.Errorf("body: got %q want %q", res.Body.String(), tc.body)
			}
			if tc.status == 405 && res.Header().Get("Allow") != "GET" {
				t.Error("missing Allow: GET")
			}
			var entry struct {
				Status int    `json:"status"`
				Path   string `json:"path"`
			}
			if err := json.Unmarshal(logs.Bytes(), &entry); err != nil {
				t.Fatal(err)
			}
			if entry.Status != tc.status || entry.Path != tc.path {
				t.Errorf("incorrect request log: %+v", entry)
			}
		})
	}
}

func TestVersion(t *testing.T) {
	var logs bytes.Buffer
	h := NewHandler("release-123", slog.New(slog.NewJSONHandler(&logs, nil)))
	res := httptest.NewRecorder()
	h.ServeHTTP(res, httptest.NewRequest(http.MethodGet, "/version", nil))
	if res.Code != http.StatusOK {
		t.Fatalf("status: %d", res.Code)
	}
	if res.Header().Get("Content-Type") != "application/json" {
		t.Fatal("expected JSON content type")
	}
	var body struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Version != "release-123" {
		t.Fatalf("wrong version: %q", body.Version)
	}
}
