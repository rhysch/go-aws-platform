package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

func check(ctx context.Context, client *http.Client, base, expected string) error {
	for _, path := range []string{"/healthz", "/readyz", "/version"} {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(base, "/")+path, nil)
		if err != nil {
			return err
		}
		res, err := client.Do(req)
		if err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		body, readErr := io.ReadAll(io.LimitReader(res.Body, 4096))
		res.Body.Close()
		if readErr != nil {
			return readErr
		}
		if res.StatusCode != http.StatusOK {
			return fmt.Errorf("%s: status %d", path, res.StatusCode)
		}
		if path == "/healthz" && string(body) != "ok\n" {
			return fmt.Errorf("unexpected health response: %q", body)
		}
		if path == "/readyz" && string(body) != "ready\n" {
			return fmt.Errorf("unexpected readiness response: %q", body)
		}
		if path == "/version" {
			var data struct {
				Version string `json:"version"`
			}
			if err := json.Unmarshal(body, &data); err != nil {
				return fmt.Errorf("version JSON: %w", err)
			}
			if data.Version == "" {
				return fmt.Errorf("version is empty")
			}
			if expected != "" && data.Version != expected {
				return fmt.Errorf("version: got %s want %s", data.Version, expected)
			}
		}
	}
	return nil
}
func main() {
	base := flag.String("url", "http://localhost:8080", "application base URL")
	expected := flag.String("expect-version", "", "exact release version, optional")
	timeout := flag.Duration("timeout", 30*time.Second, "total verification deadline")
	flag.Parse()
	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()
	client := &http.Client{Timeout: 5 * time.Second}
	var err error
	for {
		err = check(ctx, client, *base, *expected)
		if err == nil {
			fmt.Println("PASS: health, readiness and release version verified")
			return
		}
		select {
		case <-ctx.Done():
			fmt.Fprintln(os.Stderr, "FAIL:", err)
			os.Exit(1)
		case <-time.After(time.Second):
		}
	}
}
