# Verification status

Checked locally on 2026-11-19. No AWS resources were provisioned.

| Check | Result |
|---|---|
| Go formatting and `go vet ./...` | Passed |
| `go test -race -cover ./...` | Passed; handler package 92.9% statement coverage, smoke package 47.6%; server entry point not covered |
| Docker multi-stage application build | Passed |
| Local Docker Compose startup | Passed; application healthy and Caddy running |
| Go smoke test through Caddy at port 8088 | Passed; health, readiness, exact `local` version |
| JSON application and Caddy access logs | Observed |
| Local and AWS Compose configuration parsing | Passed |
| Terraform formatting | Passed |
| Bootstrap and application Terraform validation | Passed with AWS provider 6.73.0 |
| Mocked Terraform plan / security assertions | Passed; no real AWS API calls |
| Release bundle archive creation and contents | Checked |
| Shell syntax and workflow YAML parsing | Passed |

## Still requires your accounts and deployment

- Actual GitHub Actions execution, including its vulnerability scanner and shellcheck jobs.
- AWS resource provisioning, IAM/OIDC authorization, and cloud-init on EC2.
- DNS and Caddy public certificate issuance.
- SSM release execution and rollback on an actual AWS host.
- CloudWatch log/metric delivery, alarms, and confirmed SNS notifications.
- Controlled recovery drills and evidence for CV claims.

Validation and mocked plans prove configuration consistency, not cloud deployment success. Local HTTP proxy testing does not verify public HTTPS.
