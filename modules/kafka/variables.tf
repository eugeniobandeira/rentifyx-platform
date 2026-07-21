variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block - allows any resource inside this VPC (including rentifyx-identity-api/rentifyx-communications-api's EC2 instances, provisioned by their own Terraform state) to reach the broker port."
}
