provider "aws" {
  region = var.aws_region
  default_tags { tags = { Project = var.project, ManagedBy = "Terraform" } }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
locals {
  prefix = "arn:${data.aws_partition.current.partition}"
  bucket = "${var.project}-releases-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  domain = var.domain != "" ? var.domain : "go-platform.${replace(aws_eip.app.public_ip, ".", "-")}.sslip.io"
}
resource "aws_vpc" "main" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.project }
}
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}
resource "aws_internet_gateway" "main" { vpc_id = aws_vpc.main.id }
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "web" {
  name_prefix = "${var.project}-"
  description = "Public HTTP/HTTPS only; administration uses SSM"
  vpc_id      = aws_vpc.main.id
}
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/app"
  retention_in_days = 7
}
resource "aws_cloudwatch_log_group" "caddy" {
  name              = "/${var.project}/caddy"
  retention_in_days = 7
}
resource "aws_cloudwatch_log_group" "ssm" {
  name              = "/${var.project}/ssm"
  retention_in_days = 7
}
resource "aws_s3_bucket" "releases" {
  bucket        = local.bucket
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "releases" {
  bucket                  = aws_s3_bucket.releases.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "releases" {
  bucket = aws_s3_bucket.releases.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "releases" {
  bucket = aws_s3_bucket.releases.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "releases" {
  bucket = aws_s3_bucket.releases.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*",
    Resource  = [aws_s3_bucket.releases.arn, "${aws_s3_bucket.releases.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
}
resource "aws_iam_role" "instance" {
  name_prefix = "${var.project}-ec2-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "${local.prefix}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "instance" {
  role = aws_iam_role.instance.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.releases.arn}/releases/*" },
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"], Resource = aws_ecr_repository.app.arn },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"],
    Resource = ["${aws_cloudwatch_log_group.app.arn}:*", "${aws_cloudwatch_log_group.caddy.arn}:*", "${aws_cloudwatch_log_group.ssm.arn}:*"] },
    { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*" },
    { Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*",
    Condition = { StringEquals = { "cloudwatch:namespace" = "GoAWSPlatform" } } }
  ] })
}
resource "aws_iam_instance_profile" "main" {
  name_prefix = "${var.project}-"
  role        = aws_iam_role.instance.name
}
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.main.name
  monitoring             = false
  credit_specification { cpu_credits = "standard" }
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_size           = 16
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  user_data = templatefile("${path.module}/cloud-init.sh.tftpl", {
    aws_region      = var.aws_region
    project         = var.project
    domain          = local.domain
    acme_email      = var.acme_email
    image_repo      = aws_ecr_repository.app.repository_url
    app_log_group   = aws_cloudwatch_log_group.app.name
    caddy_log_group = aws_cloudwatch_log_group.caddy.name
    health_script   = file("${path.module}/../../scripts/health-metric.sh")
  })
  tags       = { Name = var.project }
  depends_on = [aws_route_table_association.public, aws_iam_role_policy.instance, aws_iam_role_policy_attachment.ssm]
}
resource "aws_eip" "app" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
}
resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

resource "aws_iam_role" "github_deploy" {
  name_prefix = "${var.project}-deploy-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Federated = var.github_oidc_provider_arn },
    Action = "sts:AssumeRoleWithWebIdentity",
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = var.github_oidc_subject != "" ? var.github_oidc_subject : "repo:${var.github_repository}:environment:production"
    } }
  }] })
}
resource "aws_iam_role_policy" "github_deploy" {
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${aws_s3_bucket.releases.arn}/releases/*" },
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:DescribeImages"], Resource = aws_ecr_repository.app.arn },
    { Effect = "Allow", Action = ["ssm:SendCommand"], Resource = [
      "${local.prefix}:ssm:${var.aws_region}::document/AWS-RunShellScript",
      aws_instance.app.arn
    ] },
    { Effect = "Allow", Action = ["ssm:GetCommandInvocation"], Resource = "*" }
  ] })
}

resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  encryption_configuration { encryption_type = "AES256" }
  image_scanning_configuration { scan_on_push = true }
}
