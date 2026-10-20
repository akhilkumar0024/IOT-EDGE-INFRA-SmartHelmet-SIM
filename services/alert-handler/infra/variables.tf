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
  description = "Image tag baked into the Terraform-managed task definition only. CI always overrides it by rendering a new task definition carrying the <sha>-<run_number> tag, so this value is never what runs once a pipeline has deployed. It exists so that `terraform apply` needs no input; 'bootstrap' is used deliberately because no such tag is ever pushed."
  default     = "bootstrap"
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
