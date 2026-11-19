# How the platform works

## Two paths to remember

**Request path:** DNS resolves your domain to an Elastic IP. AWS routes the request to the EC2 instance. Its security group allows TCP 443. Docker forwards that traffic to Caddy. Caddy terminates TLS and reverse-proxies to `api:8080` on the private Compose network. The Go handler returns a response through Caddy.

**Delivery path:** A main-branch commit is tested and built. GitHub publishes its image to private Amazon ECR and its deployment bundle to S3. GitHub's temporary AWS role calls Systems Manager. The SSM agent on EC2 downloads the bundle using the instance role, validates its checksum, and runs the release script. The script pulls containers, starts the stack, checks versions and records success.

## Go code

`cmd/api/main.go` starts an HTTP server with bounded read and write timeouts. It uses JSON `slog` logging, so fields can be searched rather than scraped from free-form text. On SIGTERM or Ctrl+C, it stops accepting new work and allows active requests up to 15 seconds to finish. Compose allows 20 seconds before forcibly killing it.

`internal/web/handler.go` owns the router. A wrapper records method, path, response status and elapsed time. It does not log request bodies, authorization headers or query strings. This avoids accidentally turning application logs into a credential store.

`/healthz` asks whether the process can answer. `/readyz` asks whether it is ready for traffic. They both succeed here because there is no database or dependency. In a database application, readiness could check a short database ping while liveness remains independent of it.

`/version` reports the build-time version set through `-ldflags -X main.version=...`. Checking 200 alone cannot tell whether a new release was installed; comparing the full commit SHA can.

`cmd/smoke` uses `net/http` to verify actual endpoints. Unit tests are cheap and specific, but cannot prove DNS, TLS or routing. The public smoke test covers those paths after deployment.

## Docker

A multi-stage build separates compilation from execution. `CGO_ENABLED=0` produces a static Go binary suitable for a scratch runtime. The image runs as numeric user 10001; the API does not need root. A read-only root filesystem, dropped Linux capabilities and no-new-privileges reduce what a compromised process can change. They do not make software invulnerable.

The Docker health check executes `/api healthcheck`; it does not need a shell. Compose waits for the application to become healthy before starting Caddy. `restart: unless-stopped` restarts an exited process, but a Docker health check marking a still-running process unhealthy does **not** by itself restart it.

Compose service names act as DNS names on its network. Caddy reaches `api:8080`. The API's host diagnostic port binds to 127.0.0.1, and AWS does not permit inbound 8080. Caddy is the public entry point.

CPU and memory limits constrain resource use. If the container exceeds its memory limit it can be killed; logs, container state and restart counts help diagnose that.

## Caddy

Caddy is a reverse proxy: it accepts client requests and forwards them to an upstream application. With a real hostname, working DNS, and reachable ports 80/443 it manages public TLS certificates automatically. Its `/data` volume preserves certificate and account data across container recreation on the same machine.

Local development uses HTTP on port 8088 to avoid needing a domain. Cloud deployment uses a different Caddyfile with HTTPS. Local success does not establish that public DNS or certificate issuance works.

Caddy stays root inside its container to bind standard web ports. The Go container runs non-root. Container isolation still shares the host kernel.

## AWS networking

A **VPC** is your AWS network boundary. A **subnet** is an address range within an availability zone. This subnet is public because its route table sends default outbound traffic to an internet gateway and the instance has a public address.

A **security group** is a stateful network filter. Inbound access is limited to 80 and 443. Outbound access supports package installation, image pulls, SSM, S3 and CloudWatch. Stateful means return traffic for an allowed connection is permitted.

If no domain is supplied, a temporary sslip.io hostname is derived from the Elastic IP. It is convenient for a demo but depends on a third-party public DNS service; use your own domain for long-term hosting.

An **Elastic IP** provides a stable public address so routine stop/start operations do not require DNS changes. Public IPv4 addresses are billable. Terraform manages the EIP association when the instance is replaced.

There is no load balancer, NAT gateway, private subnet tier or multi-AZ deployment. Those can be appropriate later, but would change cost and complexity.

## Terraform and state

Terraform declares desired resources, calculates a plan against state and real infrastructure, and applies the reviewed changes. A plan can include replacement or deletion; read those changes before approving them.

State maps Terraform resource addresses to AWS objects. It is not a server backup and may contain sensitive values. The application state is stored in a private, encrypted, versioned S3 bucket. Native S3 lockfiles coordinate cooperating Terraform users so they do not apply simultaneously. Versioning can help recover accidental state edits; it is not an excuse to edit state casually.

The bootstrap configuration creates the state bucket before the application backend can use it. Bootstrap itself initially has local state: preserve that state privately. The state bucket has `prevent_destroy`, which protects against ordinary Terraform destruction but not every out-of-band deletion.

The application uses the latest matching Canonical Ubuntu AMI at plan time. A later plan can propose instance replacement when a new AMI appears. Inspect it; for repeatable long-lived releases, pin a reviewed AMI ID rather than blindly applying every new match.

Cloud-init installs Docker and AWS CLI, ensures SSM is active, writes non-secret host configuration and installs a health metric timer. It is a bootstrap process, not a continuous configuration management system. Updating user-data replaces this instance because that behavior is explicit in Terraform.

## IAM, OIDC and SSM

The **instance role** lets EC2 read release bundles, pull from this private ECR repository, send logs, publish health metrics and communicate with SSM. The release script obtains an expiring ECR token and keeps its Docker login configuration in a temporary root-only directory, removed on exit. Applications do not need AWS permissions. IMDSv2 is required and the metadata hop limit is one; the host can retrieve credentials while typical bridged containers cannot.

The **GitHub deployment role** can publish/pull this ECR repository, upload release bundles and send the permitted SSM command to this instance. It cannot create infrastructure or access Terraform state. Its trust policy accepts the specific repository and `production` environment, with audience `sts.amazonaws.com`.

The GitHub job requests an OIDC identity token; AWS validates it and issues short-lived credentials. No long-lived AWS access key is stored in GitHub. ECR publishing also uses this temporary AWS role; no separate registry publishing token is required.

Because the OIDC subject names an environment, branch restrictions belong in the GitHub environment settings. Configure `production` to permit only main; the workflow also checks main. Protect main and require CI checks.

SSM's agent makes outbound connections, so there is no inbound SSH port or SSH private key. `AWS-RunShellScript` runs commands as root: the narrowly targeted deployment role is still a powerful privilege and should only be usable by trusted releases. A checksum catches corruption; a checksum stored beside an archive is **not** a signature against an attacker who can replace both.

## Release and recovery

Every release uses an ECR-enforced immutable full commit-SHA image tag and an S3 archive under `releases/SHA/`. Retain the archive and image for rollback. A shell lock prevents concurrent mutation on the server; GitHub concurrency prevents simultaneous production jobs in this workflow.

`deploy.sh` validates Caddy configuration, waits for containers, checks the local and public version, then atomically updates the `current` symlink. On failure, it attempts to run the last successful release again. Image pulls, registry outages and a failed host can also prevent rollback.

Redeploying a previous SHA through workflow dispatch is the manual rollback route. The server-side failure handler is a best-effort automatic recovery attempt, not a guarantee of zero downtime. The separate external Go smoke test reports failures but does not trigger an additional automatic rollback after a successful SSM release.

Compose replaces a single application's container; this is not blue/green deployment. Expect brief interruption. Better availability would need multiple healthy targets and a load balancer or orchestrator.

## Monitoring

Docker's `awslogs` driver sends application and Caddy stdout/stderr to pre-created CloudWatch groups. Each release has distinct streams and seven-day retention. SSM command output has a separate group.

A systemd timer checks the loopback health endpoint every minute and publishes `AppHealthy` (1 or 0). Three unhealthy or missing periods trigger an alarm. This detects local application failure or stopped reporting, but cannot prove public DNS, Caddy TLS or external network availability. The release smoke test checks the public path at deployment time; continuous external probing is a future extension.

EC2 status-check and CPU alarms cover host health and sustained load. SNS delivers alarms to an encrypted SQS queue, which makes notification delivery verifiable without email. An optional email subscription requires the recipient to confirm it. No default EC2 memory metric is claimed. CPU credits on burstable instances also need attention for sustained workloads.

## Persistence and rebuilding

The Go application is stateless, so it has no business data to restore. Terraform can recreate the server and the workflow can redeploy a retained image. Caddy certificate volumes and local Docker data are on the EC2 root disk, which is deleted on instance termination. Export certificate data privately before a deliberate rebuild if it needs preserving. Frequent reissuance can encounter certificate authority limits.

The project demonstrates rebuild and rollback, not database backup/restore. If you later add persistent business data, design and test a separate backup strategy before claiming recovery.
