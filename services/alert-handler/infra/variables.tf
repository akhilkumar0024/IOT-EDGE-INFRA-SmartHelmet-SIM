variable "region" {
  type        = string
  description = "AWS Region"
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

variable "image_tag" {
  type        = string
  description = "Docker image tag to deploy"
  default     = "latest"
}

variable "desired_count" {
  type        = number
  description = "Initial task count written at creation. Application Auto Scaling owns it afterwards (see ignore_changes in service.tf); change min_capacity to alter always-on capacity."
  default     = 2
}

variable "min_capacity" {
  type        = number
  description = "Autoscaling floor - the number of tasks guaranteed to be running"
  default     = 2
}

variable "max_capacity" {
  type        = number
  description = "Autoscaling ceiling - the most tasks the service may scale to. Only billed if actually reached."
  default     = 4
}
