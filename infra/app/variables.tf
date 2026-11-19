variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
variable "project" {
  type    = string
  default = "go-aws-platform"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,25}$", var.project))
    error_message = "Use 3-26 lowercase letters, digits and hyphens, starting with a letter."
  }
}
variable "domain" {
  type    = string
  default = ""
  validation {
    condition     = var.domain == "" || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,}$", var.domain))
    error_message = "Use a lowercase DNS hostname without scheme, spaces or port."
  }
}
variable "acme_email" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.acme_email))
    error_message = "Provide an email address for certificate notifications."
  }
}
variable "github_repository" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use OWNER/REPOSITORY."
  }
}
variable "github_oidc_provider_arn" { type = string }
variable "instance_type" {
  type    = string
  default = "t3.small"
}
variable "alarm_email" {
  type    = string
  default = ""
}
