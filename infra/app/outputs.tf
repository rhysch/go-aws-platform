output "public_ip" { value = aws_eip.app.public_ip }
output "url" { value = "https://${var.domain}" }
output "instance_id" { value = aws_instance.app.id }
output "deploy_role_arn" { value = aws_iam_role.github_deploy.arn }
output "release_bucket" { value = aws_s3_bucket.releases.id }
output "ssm_log_group" { value = aws_cloudwatch_log_group.ssm.name }
output "region" { value = var.aws_region }
