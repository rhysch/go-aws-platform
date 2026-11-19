# Verification status

**Current hosting status: retired at the owner’s request to avoid ongoing AWS costs.** The results below are historical deployment/test evidence, not a claim that the endpoint remains live. See [removal status](REMOVAL.md).

Verified locally and in AWS on 2026-11-19. See [deployment evidence](evidence/2026-11-19-deployment.md).

| Check | Result |
|---|---|
| Go tests, race detection, vet and formatting | Passed locally and in GitHub Actions |
| Application image vulnerability gate | Passed in CI and the AWS release |
| Local Go/Caddy Compose smoke verification | Passed |
| Terraform validation and mocked security plan | Passed |
| AWS bootstrap and application infrastructure | Applied in Hyderabad; 6 bootstrap and 35 application resources |
| Final real Terraform drift check | Passed with exit code 0; no proposed changes |
| GitHub production environment | Restricted to main |
| OIDC and private ECR publishing | Verified; immutable repository subject and immutable image tags |
| SSM application deployment | Passed |
| Caddy public HTTPS and exact release version | Verified by workflow and independent Go smoke test |
| Runtime user, read-only filesystem and health | Verified: 10001:10001, read-only, healthy |
| Temporary ECR credential cleanup | Verified |
| Application, Caddy and SSM CloudWatch logs | Observed |
| Controlled application outage | HTTP 502 observed; real health metric became zero |
| CloudWatch alarm | OK → ALARM after approximately 185 seconds; returned to OK after recovery |
| Manual outage recovery | Passed; public smoke test passed after restoration |
| SNS/SQS notifications | Both failure and recovery notifications observed in the encrypted SQS queue |
| Failed-image deployment recovery | Passed: prior version preserved and temporary credentials removed |
| Manual rollback and restore | Passed: older release verified, then newer release restored and verified |

## Limits

This is a single-instance personal project. Updates can interrupt traffic; it is not highly available. The continuous custom metric checks the local application, not public DNS/TLS. Public HTTPS is checked during release. No business database exists, and Terraform state is not a backup of instance-local certificate files. No zero-downtime, production-scale or unmeasured performance claim is made.
