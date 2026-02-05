variable "environment" {
  type        = string
  description = "Environment name (dev/staging/prod) supplied by Jenkins from workspace"
  default     = "dev"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-west-2"
}

variable "subnet_id" {
  type        = string
  description = "The VPC Subnet ID to launch the EC2 instance in"
  default     = "subnet-04f014a664f51b81a"
}