# Operations and failure drills

Perform controlled failure drills only on your own demo environment. Record expected behavior, actual behavior, evidence and recovery. Do not represent unperformed drills as completed work.

## Inspect the running release

Open a Session Manager session, then become root:

```bash
sudo -i
source /etc/go-aws-platform/host.env
release=$(readlink -f /opt/go-aws-platform/current)
docker compose --project-name go-aws-platform --env-file /etc/go-aws-platform/host.env \
  --env-file "$release/release.env" -f "$release/compose.aws.yaml" ps
curl -fsS http://127.0.0.1:8080/version
curl -fsS "https://$DOMAIN/version"
```

The current symlink changes only after the script's local and public checks pass. A healthy container, valid TLS and a correct release version are distinct checks.

## Application is unreachable

1. Does DNS resolve to the current Elastic IP?
2. Are inbound TCP 80 and 443 allowed by the security group?
3. Is the instance online and registered in SSM?
4. Did cloud-init complete? Inspect `/var/log/cloud-init-output.log`.
5. Is Caddy running? Inspect `/go-aws-platform/caddy` logs.
6. Does the loopback `/healthz` respond on EC2?
7. Are both containers in the same Compose project/network?
8. Is the correct commit SHA running?

Do not open SSH or expose the application port just to make a failed health check pass.

## Release failed

Inspect Actions → Release → SSM command ID, then AWS Systems Manager Run Command history and `/go-aws-platform/ssm` logs. Common causes:

| Symptom | Investigation |
|---|---|
| OIDC access denied | Exact repository, production environment, audience, ARN and permitted main branch |
| SSM node offline | Instance role, agent, networking, bootstrap status |
| Docker pull denied | Repository is public; SHA tag exists; registry availability/rate limits |
| Log driver cannot initialize | Log group exists; instance role permits log stream creation and writes |
| Caddy certificate fails | DNS A/AAAA records, ports 80/443, ACME rate limits and Caddy logs |
| Version mismatch | Expected image tag, running container image, stale/replaced release |
| Deployment lock busy | Inspect the existing SSM command before starting another release |
| Public smoke fails after SSM success | External network/DNS/TLS may have changed; inspect before deciding rollback |

## Manual rollback

Keep a full SHA from a previously successful release. Actions → Release → Run workflow → main → enter that SHA into `release_sha`.

The workflow downloads the retained S3 bundle and redeploys the previous image. It does not rebuild the old commit. Missing archives or deleted registry images prevent this path.

Verify the public `/version` and run the Go smoke tool with the old SHA. Record how long recovery took. Do not label it zero downtime.

## Drill 1: Stop the application and observe monitoring

Using the running-release variables from above:

```bash
docker compose --project-name go-aws-platform --env-file /etc/go-aws-platform/host.env \
  --env-file "$release/release.env" -f "$release/compose.aws.yaml" stop api
```

Expect the next local health metric to become zero and the alarm to trigger after three bad periods. A manual stop is not undone by `restart: unless-stopped`. Restore it:

```bash
docker compose --project-name go-aws-platform --env-file /etc/go-aws-platform/host.env \
  --env-file "$release/release.env" -f "$release/compose.aws.yaml" up -d --wait
```

Check HTTPS health and alarm recovery. Confirm SNS delivery if configured. This tests local app monitoring, not continuous public availability monitoring.

## Drill 2: Reject a bad configuration

Create a temporary branch with an invalid Caddy directive in `deploy/Caddyfile`. Locally, run Caddy configuration validation with an appropriate test environment. It must fail. Restore valid configuration before merging.

If you choose to test server-side recovery, do it only after you have a known good archived release. A deliberately bad release should fail the Caddy validation step and attempt restoration. Inspect both the workflow failure and the served version, then revert the deliberate change. A pipeline reporting failure is correct behavior.

## Drill 3: Version-aware rollback

Deploy a harmless welcome-text change. Record the new SHA. Manually redeploy the previous successful SHA through workflow dispatch. Confirm both the welcome response and `/version` reverted.

This is the simplest recovery exercise and does not require intentionally breaking the application.

## Drill 4: Rebuild

After preserving certificate data if needed, review a Terraform plan that replaces the EC2 instance. This destroys instance-local Docker volumes; do not do it if you have added persistent data without a backup strategy.

After apply, verify bootstrap, update the GitHub instance ID variable, redeploy a retained release and verify public HTTPS. Record manual steps and actual recovery time. Recreating infrastructure alone is not application recovery.

## Disk and certificates

Inspect `df -h`, Docker disk usage and image inventory. Release images and archives accumulate; a cleanup policy must retain the current and rollback releases. Avoid indiscriminate image/volume pruning.

Caddy certificate state resides in the named `go-aws-platform_caddy_data` volume. Protect it privately before destroying the host if it must be retained. Never commit certificate private keys. The Go application itself stores no business data.

## Incident note template

- Date and environment:
- Trigger and user-visible effect:
- Expected detection:
- Observed log/metric evidence:
- Root cause:
- Recovery action:
- Verified version and smoke result:
- Detection/recovery duration measured:
- Improvement to prevent recurrence:
