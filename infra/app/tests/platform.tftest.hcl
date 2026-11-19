# Mocked plans exercise configuration and template rendering without AWS credentials.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-south-1a"] }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0" }
  }
}
variables {
  domain                   = "app.example.com"
  acme_email               = "riya@example.com"
  github_repository        = "rhysch/go-aws-platform"
  github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}
run "platform_security_and_bootstrap" {
  command = plan
  assert {
    condition     = aws_instance.app.metadata_options[0].http_tokens == "required"
    error_message = "EC2 must require IMDSv2."
  }
  assert {
    condition     = aws_instance.app.root_block_device[0].encrypted
    error_message = "EC2 root storage must be encrypted."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.http.from_port == 80 && aws_vpc_security_group_ingress_rule.https.from_port == 443
    error_message = "Public traffic must enter on the web ports."
  }
  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 7
    error_message = "Application log retention must be bounded."
  }
}
