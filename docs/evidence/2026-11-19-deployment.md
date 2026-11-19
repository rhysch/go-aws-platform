# AWS deployment evidence — 2026-11-19

**Historical evidence:** the owner subsequently requested removal of the AWS environment to avoid ongoing charges. The old endpoint is retired.

## Infrastructure

- Region: Hyderabad (`ap-south-2`).
- Terraform bootstrap: six resources created, including private state storage and GitHub OIDC provider.
- Application: 35 resources created; no pre-existing resources changed or destroyed.
- Server bootstrap verified through Systems Manager: cloud-init done, Docker Compose installed, monitoring timer active.
- Production GitHub environment permits the main branch only.
- No stored AWS access key or registry password is required by the Actions workflows.

## Actual troubleshooting example

The initial infrastructure apply failed on the SNS topic policy: AWS returned `Policy statement action out of service scope!` for the owner statement using `SNS:*`. Terraform validation and mocked planning had passed, but the service rejected that action during apply.

The owner statement was changed to explicit supported SNS actions. A fresh plan showed one resource to add and no changes or destruction. The corrective apply completed successfully. Previously created infrastructure remained intact.

[Correction commit](https://github.com/rhysch/go-aws-platform/commit/135923f6750b1a51d1705614bdfd55651688882c)

[Passing CI after correction](https://github.com/rhysch/go-aws-platform/actions/runs/44492922141)

## OIDC troubleshooting

The first release reached AWS authentication but failed with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. Inspection of GitHub's OIDC customization API showed `use_immutable_subject=true`: the actual subject prefix contains immutable owner and repository IDs. The original role expected the legacy name-only format.

The trust policy was corrected to match the exact immutable repository subject and production environment, without wildcards. GitHub's production environment remains restricted to main. A diagnostic step masks the token and prints only selected non-secret claims.

[OIDC support commit](https://github.com/rhysch/go-aws-platform/commit/18aea55)

Release, monitoring and recovery evidence will be appended only after those checks complete.

## First successful release

- [Release run 44495088917](https://github.com/rhysch/go-aws-platform/actions/runs/44495088917) passed both build and deployment jobs.
- Released commit: `18aea55f45cb6c36d57bdd13e545932d26336cad`.
- OIDC role assumption and private ECR publishing succeeded.
- SSM deployment command completed successfully.
- Caddy public HTTPS and exact version were verified by the release and an independent local Go smoke test.
- Demo endpoint: https://go-platform.16-113-199-23.sslip.io

Infrastructure matched Terraform with no proposed changes after the SNS correction; the subsequent OIDC correction changed only the role trust policy.

## Runtime verification

- The Go container ran as `10001:10001`, with a read-only root filesystem and healthy Docker status.
- Its diagnostic host port bound only to `127.0.0.1:8080`; Caddy exposed the web ports.
- Temporary ECR login configuration was removed after deployment.
- Application and Caddy access log streams were observed in CloudWatch.
- All three alarms reached `OK` before the controlled outage drill.

## Controlled outage and recovery

- Go container stopped through SSM at **09:22:13 UTC**; a six-minute fallback recovery timer was scheduled first.
- Caddy stayed running and returned **HTTP 502** while its upstream was unavailable.
- `AppHealthy` changed from 1 to 0 in the 09:22–09:25 metric periods.
- Application alarm changed **OK → ALARM at 09:25:18 UTC**, approximately 185 seconds after the stop.
- CloudWatch recorded successful execution of its SNS alarm action.
- Manual restoration through SSM completed at **09:26:24 UTC**, returning the original release version; the fallback timer was cancelled.
- Independent public Go smoke verification passed after restoration.
- Alarm changed **ALARM → OK at 09:27:18 UTC**.
- Both failure and recovery notification delivery to SQS were observed; see [sanitized alarm messages](alarm-notifications.json).

This was deliberate downtime in a single-instance demo, not zero-downtime deployment or an automatic-healing guarantee.

## Infrastructure drift check

After the SNS and immutable OIDC corrections, a fresh real `terraform plan -detailed-exitcode` returned exit code 0: **No changes. Your infrastructure matches the configuration.**

## Second verified release

- [Release run 44496882207](https://github.com/rhysch/go-aws-platform/actions/runs/44496882207) passed.
- [CI run 44496882107](https://github.com/rhysch/go-aws-platform/actions/runs/44496882107) passed.
- Release commit: `7747c14a8436af879f6e49bfdaa90184d5b08fb3`.
- Independent public Go smoke test confirmed this exact version before recovery tests.

## Failed-image recovery test

A controlled candidate used the deliberately nonexistent image tag `ffffffffffffffffffffffffffffffffffffffff`. The pull failed as expected. The deployment script collected diagnostics, invoked its previous-release restoration path, and returned a failure code.

The test then verified that the `current` symlink still pointed to `7747c14a8436af879f6e49bfdaa90184d5b08fb3`, public HTTPS served that same version, and temporary registry credentials had been removed. The test harness passed.

This verifies rejection and recovery for an image-pull failure before replacing the running app; it is not proof of recovery from every possible mid-deployment or host failure.

## Manual rollback

The normal Release workflow was dispatched with `release_sha=18aea55f45cb6c36d57bdd13e545932d26336cad`. It reused the retained archive and image rather than rebuilding that commit.

An independent public Go smoke test verified the old version, health and readiness after rollback. [Rollback run 44497723380](https://github.com/rhysch/go-aws-platform/actions/runs/44497723380).

The newer release `7747c14a8436af879f6e49bfdaa90184d5b08fb3` was then restored through the same workflow. An independent public Go smoke test confirmed the newer version, health and readiness again. [Restore run 44498046441](https://github.com/rhysch/go-aws-platform/actions/runs/44498046441).

Documentation-only commits can be newer than the running application release; they deliberately do not redeploy the service.
