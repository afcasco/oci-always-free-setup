variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the Object Storage bucket used for Terraform state"
  type        = string
  default     = "homelab-terraform-state"
}

