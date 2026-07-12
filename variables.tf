variable "aws_region" {
  type        = string
  description = "AWS region where resources will be created."
}

variable "project" {
  type        = string
  description = "Project name used for tags and naming."
}

variable "environment" {
  type        = string
  description = "Environment name (prod)."
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform state."
}

variable "dynamodb_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking."
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig for Kubernetes/Helm providers."
  default     = "~/.kube/config"
}
