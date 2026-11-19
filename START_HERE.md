# Learn this project one checkpoint at a time

The files are already in their intended locations. You do not need to keep moving or restructuring them. Complete one checkpoint, explain it in your own words, then continue. Do not start with AWS.

## 1. Run the Go application

From the repository root:

```bash
go version
go test -v ./...
go run ./cmd/api
```

In a second terminal:

```bash
curl -i http://localhost:8080/
curl -i http://localhost:8080/healthz
curl -i http://localhost:8080/version
curl -i -X POST http://localhost:8080/healthz
```

Expect 200 for the first three and 405 for the last. `/version` reports `dev` because this is a local build. If port 8080 is occupied, stop the existing process you started before running this server. You can inspect the listener with `ss -ltnp 'sport = :8080'`; do not kill an unidentified process.

Read `internal/web/handler.go`, then `cmd/api/main.go`. `newHandler` from the earlier TaskShip lesson is now the exported `web.NewHandler`, isolated in a package so tests can exercise routing without starting the server.

**Explain:** What is a handler? Why is a health endpoint useful? What does `Allow: GET` mean?

## 2. Understand the tests and logs

```bash
go test -race -cover ./...
go vet ./...
```

Read `internal/web/handler_test.go`. Each table entry describes a request and expected result. Read `cmd/smoke/main_test.go` to see verification reject an old release and an unhealthy response.

**Exercise:** Temporarily change the welcome message without changing its test, run the tests, observe failure, then restore it. Do not deploy that deliberate mistake.

**Explain:** Unit tests inspect handlers directly; smoke tests make real HTTP requests against a running deployment. Race detection checks exercised concurrent memory access; it does not prove all possible concurrency is safe.

## 3. Run the Go smoke tool

With the server still running:

```bash
go run ./cmd/smoke -url http://localhost:8080 -expect-version dev
```

It checks health, readiness and version, uses HTTP timeouts, retries until its deadline, and exits with a nonzero code on failure.

**Exercise:** Pass `-expect-version wrong -timeout 3s`. It should fail even though the server is healthy. That catches a pipeline that accidentally left the old application running.

## 4. Run Docker and Caddy locally

Stop the standalone server with Ctrl+C. Read `Dockerfile`, `compose.yaml` and `Caddyfile.local` before running:

```bash
docker compose up -d --build --wait
docker compose ps
go run ./cmd/smoke -url http://localhost:8088 -expect-version local
docker compose logs --tail=20 api caddy
```

Request path: your browser → host port 8088 → Caddy port 80 → Docker network → API port 8080. The host's direct API port is loopback-only.

The image is built in a Go compiler image, but runs in `scratch`. The final image has no shell, package manager or curl. The Go binary's `healthcheck` command replaces curl inside that container. Do not claim an image size until you measure it.

**Explain:** What is the difference between an image and a container? Why can Caddy use `api:8080`? Why does `localhost` inside Caddy not mean the API container?

Stop the stack when finished:

```bash
docker compose down
```

## 5. Read the AWS design before paying for resources

Read [EXPLAINED.md](docs/EXPLAINED.md), then [DEPLOYMENT.md](docs/DEPLOYMENT.md). Draw the browser request path and GitHub deployment path yourself. They are different paths.

Only continue once you understand VPC, subnet, route table, security group, instance role, S3 state, OIDC, and Systems Manager at the level described in the guide.

## 6. Provision and deploy

Follow the deployment guide exactly: bootstrap → reviewed infrastructure plan → DNS → environment protection and GitHub variables → release.

There is no automatic `terraform apply` workflow. You review and apply infrastructure changes yourself.

**Explain:** How does the pipeline get AWS credentials? Which permissions belong to EC2 and which belong to GitHub? Why does the security group not allow SSH or port 8080?

## 7. Practice operations, then update your CV

Complete the drills in [RUNBOOK.md](docs/RUNBOOK.md). Save evidence in your own `docs/evidence/` directory: successful workflow, version response, alarms, and incident notes. Do not publish tokens, state files, saved plans or private credentials.

Read [INTERVIEW.md](docs/INTERVIEW.md) and answer questions out loud without reading. Use CV wording only for milestones you have actually completed.
