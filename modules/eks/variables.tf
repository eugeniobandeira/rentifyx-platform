variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "eks_public_access_cidrs" {
  type        = list(string)
  description = <<-EOT
    CIDR blocks allowed to reach the EKS public API endpoint. Defaults to
    loopback only (127.0.0.1/32) - deliberately non-functional, so a real
    cluster is never reachable from the public endpoint until the operator
    overrides this with their actual IP(s) in terraform.tfvars. Never set
    this to 0.0.0.0/0 (CKV_AWS_38) - the default exists so static analysis
    (checkov) can prove that statically instead of treating an unset,
    default-less variable as an unknown/worst-case value.
  EOT
  default     = ["127.0.0.1/32"]
}
