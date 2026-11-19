# Explain this project in an interview

Do not memorize answers you cannot demonstrate. Run the commands, change one thing, observe the result and explain it in your own words.

## A 45-second introduction

After you have actually deployed and verified it:

> I built a Go service and an automated deployment platform on AWS. Terraform provisions the network, EC2, IAM, remote state and monitoring resources. Docker packages the application, and Caddy provides HTTPS and reverse proxying. GitHub Actions tests and scans the image, publishes a commit-tagged release, and deploys through Systems Manager using short-lived OIDC credentials. The release process checks the exact application version and attempts to restore the previous release on failure. I also practiced manual rollback and investigated failures using structured logs and CloudWatch.

If AWS deployment or a drill is not complete, say so and describe only the verified work.

## Questions to practice

**Why use such a simple Go application?**
The focus is infrastructure and delivery. A small stateless service makes deployment behavior easy to test without mixing in database or business-logic problems.

**Why Terraform rather than clicking in the console?**
It makes infrastructure reviewable, repeatable and tracked in code. Plans show intended changes before apply. State connects the declared resources to real AWS objects.

**What does state locking do?**
It prevents cooperating Terraform operations from writing the same state at the same time. It does not lock every AWS resource against console changes or replace code review.

**Why separate bootstrap?**
The S3 backend must exist before Terraform can store application state there. Bootstrap initially uses local state, which needs private backup.

**Why Caddy?**
It combines reverse proxying with automatic certificate management. I still need correct DNS, reachable ports and persistent certificate storage.

**Why not Kubernetes here?**
One stateless app on a single server can use Compose with lower operational overhead. My separate Kubernetes demo demonstrates that skill. For this platform, Kubernetes would not by itself eliminate a single-server failure.

**What do multi-stage and non-root mean?**
The compiler stays in the build stage; the runtime gets only the binary. The application's numeric runtime user has fewer privileges than root. The image also uses a read-only root filesystem and drops capabilities.

**What happens when Docker says unhealthy?**
Compose can wait for health during deployment and gate startup dependencies, but the Docker restart policy alone does not restart a process solely because its health check failed. Monitoring and an operator response still matter.

**How does GitHub authenticate to AWS?**
GitHub requests an OIDC token for the job. AWS checks audience and subject against the role trust policy and returns short-lived credentials. The subject is bound to the production environment, whose deployment branches I restrict to main.

**Are there no secrets at all?**
There is no stored long-lived AWS key or registry password in GitHub. GitHub gets AWS credentials through OIDC; EC2 uses its instance role. Temporary AWS and ECR credentials exist at runtime, and Caddy stores private certificate material in its data volume.

**Why SSM instead of SSH?**
It allows administration through an outbound agent connection with IAM controls, without opening port 22 or distributing an SSH private key. Run Command is powerful because it executes as root, so I restrict its target and protect the release workflow.

**How do you know the correct release is live?**
The binary embeds the full commit SHA. Deployment checks `/version` locally and over HTTPS, then a Go smoke tool independently validates health, readiness and the expected version.

**Are SHA image tags immutable?**
Yes, this ECR repository enforces immutable tags. Rerunning a commit reuses its existing image and scans it instead of replacing that tag. An administrator could still change repository settings, so IAM restrictions remain important.

**What happens on deployment failure?**
The script collects diagnostics and attempts to restore the previous successful Compose release. First deployment has no rollback target. Recovery can also fail, so I inspect logs and verify the served version. External smoke-test failure after SSM success does not independently trigger another rollback.

**What monitoring exists?**
JSON application and access logs, a one-minute local app health metric, instance status checks, CPU alarms and SNS notifications delivered to an encrypted SQS queue. Optional email delivery requires confirmation. It does not continuously test public DNS or TLS. That requires an external probe.

**Is it highly available?**
No. One EC2 host is a single point of failure, and container replacement can interrupt requests. Multiple targets behind a load balancer, external persistent data and multi-AZ design would be needed for stronger availability.

**What gets lost when EC2 is replaced?**
The root disk and its Docker volumes are deleted. The Go service is stateless, but certificate data must be protected separately if it needs preservation. S3 release archives and Terraform state survive separately; neither is a backup of server files.

**What was a real problem you solved?**
Use your incident note. Give the symptom, evidence, root cause, fix and verified outcome. Never substitute a hypothetical story for your own experience.

## CV wording

Use this only after the relevant milestones are complete:

**Automated AWS Application Platform | Go, Terraform, Docker, Caddy, GitHub Actions, CloudWatch**

- Provisioned AWS networking, EC2, IAM, monitoring and private S3 storage using Terraform with encrypted remote state and native state locking.
- Containerized a Go HTTP service using a multi-stage build, non-root runtime and health checks; configured Caddy reverse proxying and HTTPS.
- Automated testing, vulnerability scanning, image publishing and version-verified deployment through GitHub Actions, OIDC and AWS Systems Manager.
- Implemented release recovery and manual rollback; configured structured logs, application health metrics and CloudWatch alarms.

If only local work is complete, use:

- Built and tested a containerized Go service with Caddy reverse proxying; authored Terraform infrastructure and CI/CD configuration for planned AWS deployment.

Do not claim reduced deployment time, zero downtime, production scale, a measured image size or completed recovery drills without evidence. This is personal project experience, not employment.

## Evidence to collect

- Architecture diagram and readable README.
- Green CI and release runs from your own repository.
- Public HTTPS version response matching a commit.
- Terraform plan summary with account-sensitive details redacted.
- An alarm transitioning during a controlled drill.
- Successful rollback and your incident note.
- Measured image size, release duration and recovery duration if you want numerical CV bullets.
