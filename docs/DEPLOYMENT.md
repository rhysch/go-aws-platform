# Deploy to AWS

**Paid hosting is disabled for this repository. The previous demo was removed at the owner’s request.** Use the local Compose setup in START_HERE.md to learn without AWS charges. This guide describes an optional paid deployment, not a currently running service.

Complete START_HERE.md first. Local tests do not prove an AWS deployment. These steps create billable resources.

## 1. Tools and identity

Use Go, Docker with Compose, Terraform 1.10+, AWS CLI v2, and GitHub CLI. Authenticate AWS with an approved local profile; do not put credentials into this repository. GitHub authentication must allow repository configuration and workflow dispatch.

```bash
export AWS_PROFILE=YOUR_WORKING_PROFILE
export AWS_REGION=ap-south-2
aws sts get-caller-identity
```

The implementation uses private Amazon ECR. No Docker Hub account or publishing token is required. GitHub uses OIDC, and EC2 uses its instance role.

## 2. Bootstrap

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
```

Edit the copy: choose your region and a globally unique private state bucket. If your AWS account already has GitHub's OIDC provider, set `create_github_oidc=false` and reuse its ARN.

```bash
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/bootstrap output
```

Bootstrap initially uses local state. Keep a private encrypted backup of that state; never commit it. The bucket has versioning, encryption, blocked public access, a TLS-only policy and `prevent_destroy`.

## 3. Plan application infrastructure

```bash
cp infra/app/backend.hcl.example infra/app/backend.hcl
cp infra/app/terraform.tfvars.example infra/app/terraform.tfvars
```

Edit both files. Copy the state bucket and OIDC ARN from bootstrap. Set region, repository, ACME email and instance size. Leave `domain=""` for a temporary Elastic-IP-based sslip.io hostname, or supply a hostname you control. ECR's private repository URL is generated automatically. Keep `alarm_email=""` unless you explicitly want an email subscription. Alarm delivery to SQS works without email.

Check GitHub's exact OIDC subject format before applying the role trust policy:

```bash
gh api repos/OWNER/REPO/actions/oidc/customization/sub
```

If `use_immutable_subject` is true, set Terraform's `github_oidc_subject` to the returned `sub_claim_prefix` plus `:environment:production`. It includes immutable owner/repository IDs. Leaving the variable empty uses the legacy name-only subject, suitable only for repositories actually issuing that format. The release logs selected non-secret claims to help diagnose a mismatch; it never logs the OIDC token.

```bash
terraform -chdir=infra/app init -backend-config=backend.hcl
terraform -chdir=infra/app validate
terraform -chdir=infra/app test
terraform -chdir=infra/app plan -out=production.tfplan
```

Review the plan before applying. It includes networking, one EC2 instance, an Elastic IP, encrypted storage, IAM, ECR, private release storage, logs, alarms and SNS/SQS. Burstable CPU credits use standard mode to avoid surplus-credit charges. Read replacement actions closely: new AMIs or user-data changes can replace the server and delete local Docker volumes.

```bash
terraform -chdir=infra/app apply production.tfplan
terraform -chdir=infra/app output
```

The app is not running yet. The health alarm may initially enter ALARM.

## 4. DNS and bootstrap

With your own domain, create an A record pointing to `public_ip`. With the temporary hostname, public DNS resolves the embedded IP automatically. Check the `domain` output using `nslookup`. Do not create an AAAA record without IPv6 support. Public web traffic uses ports 80/443; SSH and 8080 remain closed.

Open AWS Systems Manager → managed nodes → Session Manager. Wait for the new instance to appear online. On the host:

```bash
sudo cloud-init status --wait
sudo test -f /opt/go-aws-platform/bootstrap-complete && echo bootstrap-complete
sudo docker compose version
sudo systemctl status go-aws-platform-health.timer --no-pager
```

For errors inspect `/var/log/cloud-init-output.log`. Caddy needs working DNS and reachable ports 80/443 before certificate issuance succeeds.

## 5. Configure GitHub

Create an environment named `production`, permit deployments only from `main`, and protect main with required CI checks. Where supported, add required reviewers. Both image publishing and deployment use this environment's OIDC identity.

Set these repository Actions variables from Terraform outputs:

| Variable | Output |
|---|---|
| `IMAGE_REPOSITORY` | `image_repository` |
| `AWS_REGION` | `region` |
| `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arn` |
| `RELEASE_BUCKET` | `release_bucket` |
| `INSTANCE_ID` | `instance_id` |
| `SSM_LOG_GROUP` | `ssm_log_group` |
| `APP_URL` | `url` |

No AWS or registry Actions secrets are required. Build/deployment jobs skip when their required variables are missing. Terraform apply remains a separate, reviewed operation outside the application workflow.

## 6. Release

Only if you explicitly choose paid hosting again: provision the infrastructure, restore the required variables, set the additional repository variable `ENABLE_AWS_DEPLOYMENT=true`, re-enable the disabled Release workflow, then select Actions → Release → Run workflow → main. Pushes never trigger cloud release. Leave `release_sha` blank for a new build. Documentation-only pushes skip automatic release; CI still runs.

The workflow tests Go, authenticates using OIDC, builds or reuses an immutable ECR image, scans that exact image, publishes it if new, uploads the deployment bundle, invokes SSM and verifies the public version using the Go smoke tool. Investigate vulnerability-scan failures rather than bypassing them. The scan gate covers selected high/critical vulnerabilities with an available fix; it does not establish that every possible security issue is absent.

On EC2, the script obtains a short-lived ECR login, pulls the image, validates Caddy, starts the stack and checks local/public versions. It removes its temporary registry configuration on exit. Failed rollout attempts restore the last successful release. First deployment has no previous release.

## 7. Verify and practice recovery

```bash
curl -i https://YOUR_HOSTNAME/healthz
curl -i https://YOUR_HOSTNAME/version
go run ./cmd/smoke -url https://YOUR_HOSTNAME -expect-version FULL_COMMIT_SHA
```

Do not disable TLS validation. Inspect CloudWatch logs, custom `AppHealthy` metrics and the alarm state. SNS routes alarm notifications to the encrypted SQS queue; its URL is a Terraform output. An optional email subscription requires manual confirmation.

Follow RUNBOOK.md to perform a controlled stop/recovery and manual rollback to a retained release. Record actual results in docs/evidence. Do not claim them from configuration alone.

## 8. Update infrastructure

Generate a fresh saved plan, review it and apply it. If EC2 is replaced, update GitHub's `INSTANCE_ID`, verify bootstrap and redeploy a retained release. Check EIP and DNS. Terraform state is not a backup of server files or certificates.

## 9. Costs and cleanup

EC2, EBS, public IPv4, ECR, S3, CloudWatch, SNS and SQS can incur charges. For this Hyderabad demo, the AWS Price List API returned $0.0224/hour for Linux on-demand t3.small on 2026-11-19: approximately $16.35 for 730 compute hours, before storage, IPv4, monitoring, other services and taxes. This is an observed price, not a budget cap or a promise of future pricing. Check regional pricing and set an AWS Budget. There is no free-tier assumption. Stop EC2 when not demonstrating it if suitable; storage, EIP and other retained resources can still cost money.

To remove the application, generate and review a destroy plan:

```bash
terraform -chdir=infra/app plan -destroy -out=destroy.tfplan
```

ECR has `force_delete=false` and the versioned release bucket has `force_destroy=false`. Preserve what you need, then explicitly remove retained ECR images and S3 object versions/delete markers if you intend to delete those resources. Regenerate the destroy plan after cleanup and review it before applying. The protected bootstrap bucket and account-wide OIDC provider remain separate. Do not delete resources shared with other projects.
