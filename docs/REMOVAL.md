# AWS hosting removal

The owner requested immediate removal of the paid AWS demo on 2026-11-19.

## Application environment

- EC2 instance terminated; Elastic IP released.
- ECR repository and all release images removed.
- Versioned release bucket emptied and removed.
- CloudWatch log groups and alarms removed.
- SNS/SQS notification resources removed.
- Application IAM roles, instance profile and networking removed.
- The application Terraform state contains no managed resources.
- No project-tagged EBS volumes or snapshots were found after termination.

## Deployment safeguards

- GitHub Release workflow disabled.
- All seven AWS deployment variables removed.
- Release source changed to manual dispatch only and requires `ENABLE_AWS_DEPLOYMENT=true` in addition to separately configured AWS resources.
- CI and local Go/Docker usage do not provision AWS infrastructure.

The bootstrap state bucket (including all 30 retained object versions/delete markers) and the project-only GitHub OIDC provider were removed. Terraform destroyed all six bootstrap resources. Private local state copies were kept outside Git.

Historical deployment, monitoring and recovery evidence remains valid as a record of the completed demonstration. The old public endpoint is retired. Previously incurred AWS usage may still appear on the bill; deleting resources does not reverse earlier usage charges.
