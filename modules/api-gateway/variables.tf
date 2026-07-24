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

variable "subnet_ids" {
  type = list(string)
}

variable "identity_api_uri" {
  description = "Base URL (scheme + host + port, e.g. http://ec2-x.compute.amazonaws.com:8080) of identity-api. Empty string disables its route/integration."
  type        = string
  default     = ""
}

variable "communications_api_uri" {
  description = "Base URL (scheme + host + port) of communications-api. Empty string disables its route/integration."
  type        = string
  default     = ""
}

variable "asset_registry_api_uri" {
  description = "Base URL (scheme + host + port) of asset-registry-api. Empty string disables its route/integration - no default until the service has a real deploy."
  type        = string
  default     = ""
}
