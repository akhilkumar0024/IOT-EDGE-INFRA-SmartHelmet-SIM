variable "hot-storage-name" {
  description = "name for hot storage"
  type        = string
  default     = "smart-helmet-hot-storage"
}
variable "cold-storage-name" {
  description = "name for cold storage"
  type        = string
  default     = "smart-helmet-cold-storage"
}
variable "execution-registry-name" {
  description = "name for the execution registry"
  type        = string
  default     = "smart-helmet-execution-registry"
}

variable "device-status-db-table-name" {
  description = "name for the device status database table"
  type        = string
}
