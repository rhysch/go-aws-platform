# Deploy to AWS

Complete local checkpoints in START_HERE.md first. These commands are instructions, not a record of an existing deployment. They create billable resources when you apply Terraform. Review current pricing and set an AWS Budget yourself before proceeding.

## 1. Accounts and tools

You need:

- A GitHub repository containing this code, default branch `main`.
- A public Docker Hub repository, e.g. `YOURUSER/go-aws-platform`.
- A Docker Hub publishing token scoped to the repository where available.
- An AWS account and a local identity allowed to provision the resources in `infra/` (including IAM).
- Terraform 1.10+, AWS CLI v2, Go, Docker with Compose, Git, and a domain/subdomain you control.

Use a local AWS profile with short-lived credentials where possible. For example, configure AWS IAM Identity Center using your organization's values:

```bash
aws configure sso --profile portfolio
aws sso login --profile portfolio
export AWS_PROFILE=portfolio
aws sts get-caller-identity
```

If your account does not use Identity Center, use its approved authentication method. Do not create root access keys or put AWS keys into this repository. Never use administrator permissions for the application's EC2 role or GitHub deployment role.

## 2. Bootstrap remote state

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
```

Edit the copy: choose a globally unique state bucket name and your region. The default region is `ap-south-1`. GitHub's OIDC provider is account-wide; if `token.actions.githubusercontent.com` already exists in IAM, set `create_github_oidc = false` and reuse that provider's ARN.

```bash
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/bootstrap output
```

The bootstrap state is local at `infra/bootstrap/terraform.tfstate`: back it up to private encrypted storage. Do not commit it. The bucket's `prevent_destroy` intentionally blocks an ordinary destroy. This step cannot initially store its own state in a bucket that does not yet exist.

## 3. Configure the application infrastructure

```bash
cp infra/app/backend.hcl.example infra/app/backend.hcl
cp infra/app/terraform.tfvars.example infra/app/terraform.tfvars
```

Edit both files. Replace every placeholder. Use a lowercase DNS hostname such as `app.yourdomain.com`. `image_repository` must match your public Docker Hub repository exactly, prefixed with `docker.io/`. Copy the OIDC provider ARN from bootstrap or IAM.

The backend region is the bucket's region; the application region is where EC2 runs. Keep them the same for this first deployment.

```bash
terraform -chdir=infra/app init -backend-config=backend.hcl
terraform -chdir=infra/app validate
terraform -chdir=infra/app test
terraform -chdir=infra/app plan -out=production.tfplan
```

Read the plan. It includes a VPC, subnet and routing, security groups, an EC2 instance and EIP, IAM roles, a private release bucket, log groups, alarms and SNS. Saved plans and state can contain sensitive information: keep them private.

If the plan matches your intent:

```bash
terraform -chdir=infra/app apply production.tfplan
terraform -chdir=infra/app output
```

No application runs yet. The local health alarm may enter ALARM before the first release; that is expected.

## 4. Point DNS at the instance

Create an A record for your chosen hostname using Terraform's `public_ip` output. DNS is deliberately managed outside this repository so it works with different DNS providers.

```bash
nslookup app.yourdomain.com
```

It must resolve to the Elastic IP. Do not add an AAAA record unless you have actually configured IPv6. If your DNS provider offers an HTTP proxy, use DNS-only mode for the first deployment so the request path is easy to understand.

Verify port 80 and 443 are reachable. Port 22 and 8080 should not be publicly open. Caddy needs reachable DNS and web ports to obtain its certificate.

## 5. Verify bootstrap through Systems Manager

AWS Console → Systems Manager → Fleet Manager / managed nodes. Wait for the instance to appear online. Open a Session Manager session (your own local/console identity needs permission).

On the instance:

```bash
sudo cloud-init status --wait
sudo test -f /opt/go-aws-platform/bootstrap-complete && echo bootstrap-complete
sudo docker version
sudo docker compose version
sudo systemctl status go-aws-platform-health.timer --no-pager
```

If cloud-init failed, inspect `/var/log/cloud-init-output.log`. Do not proceed by rerunning the entire bootstrap script blindly. Identify the failed step first.

## 6. Configure GitHub

Create an environment named **production**. Restrict its deployment branches to **main**. Where your GitHub plan supports it, add required reviewers. The OIDC trust policy binds to the environment; these settings are part of the intended trust boundary.

Set these **repository Actions secrets** (the build job does not use the production environment):

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub account name |
| `DOCKERHUB_TOKEN` | Publishing token |

Set these **repository Actions variables**:

| Variable | Value |
|---|---|
| `IMAGE_REPOSITORY` | Exactly `docker.io/YOURUSER/go-aws-platform`, matching Terraform |
| `AWS_REGION` | Terraform `region` output |
| `AWS_DEPLOY_ROLE_ARN` | Terraform `deploy_role_arn` output |
| `RELEASE_BUCKET` | Terraform `release_bucket` output |
| `INSTANCE_ID` | Terraform `instance_id` output |
| `SSM_LOG_GROUP` | Terraform `ssm_log_group` output |
| `APP_URL` | Terraform `url` output, including `https://` |

Protect main and require the CI checks before merge. Review action dependencies before publishing; third-party actions are referenced by version tags in this starter. Pin reviewed full action commit SHAs when hardening the repository.

Confirm the SNS subscription email if you supplied `alarm_email`. Without confirmation, email alarms will not be delivered.

## 7. Run the first release

Push the code to main after configuring the variables/secrets, or open Actions → Release → Run workflow, select main, and leave `release_sha` blank.

Release build is skipped until `IMAGE_REPOSITORY` is configured. Deployment is skipped until all six AWS/deployment variables are configured. This keeps the initial source upload from attempting an unconfigured deployment. Configure secrets and variables before running a release.

Watch:

1. Go tests and vet.
2. Image build and high/critical fixable vulnerability scan.
3. Publishing the scanned image under the full Git commit SHA.
4. Deployment bundle upload.
5. OIDC role assumption.
6. SSM command and server rollout.
7. Public Go smoke verification.

A scan failure should be investigated, not bypassed just to obtain a green run. Fix or upgrade the affected dependency/image. `ignore-unfixed` is explicit: the gate only fails on selected vulnerabilities with an available fix; inspect the full security context before production use.

The first image pull and certificate issuance can take time. If release fails, inspect its SSM command output and CloudWatch. A public Docker Hub repository is required because the server does not store registry credentials.

## 8. Verify independently

From your own machine:

```bash
curl -i https://app.yourdomain.com/healthz
curl -i https://app.yourdomain.com/version
go run ./cmd/smoke -url https://app.yourdomain.com -expect-version FULL_40_CHARACTER_SHA
```

Do not use `-k`: TLS validation is part of the test. Confirm the exact SHA rather than accepting any successful response.

In CloudWatch, inspect application and Caddy log groups, then the `GoAWSPlatform / AppHealthy` metric. The custom metric needs a few minutes; EC2 basic metrics use longer intervals. Complete the runbook exercises before claiming recovery experience.

## 9. Infrastructure updates

Make a small Terraform change, then:

```bash
terraform -chdir=infra/app plan -out=production.tfplan
terraform -chdir=infra/app apply production.tfplan
```

Read replacement actions closely. New AMIs or cloud-init changes can replace EC2 and erase its local volumes. If the instance ID or other outputs change, update the corresponding GitHub variables and redeploy a retained release. The EIP should remain associated through Terraform, but verify it and DNS after replacement.

The bootstrap bucket, release bucket, retained Docker images and DNS are separate concerns. A successful `terraform apply` does not mean the application has been deployed.

## 10. Cleanup

Plan destruction first:

```bash
terraform -chdir=infra/app plan -destroy -out=destroy.tfplan
```

The versioned release bucket has `force_destroy = false`. Terraform will refuse to delete it while it contains objects/versions. Preserve needed evidence and releases, then explicitly remove the bucket's object versions and delete markers using the S3 console if you choose to destroy the environment. After removing versions, regenerate the destroy plan and review it before applying.

```bash
terraform -chdir=infra/app apply destroy.tfplan
```

Remove stale DNS records. Verify EC2, EBS volumes, EIP, alarms, logs and SNS resources were actually removed. The protected bootstrap state bucket and account-wide OIDC provider intentionally remain; do not delete a shared provider or state bucket used by other projects. Retained state versions and any other resources can still incur charges.
