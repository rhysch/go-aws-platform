# CV project description

Use this under **Projects**, with a link to your repository. This is personal project experience, not employment.

**Automated AWS Application Platform**

Go · Terraform · AWS EC2/ECR/IAM/S3 · Docker · Caddy · GitHub Actions · CloudWatch

[github.com/rhysch/go-aws-platform](https://github.com/rhysch/go-aws-platform)

- Provisioned AWS networking, EC2, IAM, private release storage and monitoring using Terraform with encrypted, versioned S3 state and native state locking.
- Containerized a Go HTTP service using a multi-stage build, non-root runtime and health checks; configured Caddy reverse proxying and public HTTPS.
- Automated tests, vulnerability scanning, immutable ECR image publishing and version-verified deployment through GitHub Actions, OIDC and AWS Systems Manager.
- Configured CloudWatch logs, health metrics and SNS-to-SQS alarms; verified outage recovery, failed-release handling and rollback between retained versions.

Deployment, alarm delivery, outage recovery and rollback were demonstrated; see [the recorded evidence](evidence/2026-11-19-deployment.md). Do not claim high availability, zero downtime, production traffic, years of employment, or time/cost savings that were not measured.

## Explain before applying

Be able to draw the request path and release path, explain Terraform state versus server backups, distinguish the GitHub and EC2 roles, and demonstrate an exact-version check and rollback. Read INTERVIEW.md, then practice the commands yourself.
