variable "tenancy_ocid" {
  description = "OCI tenancy OCID / root compartment OCID"
  type        = string
}


variable "region" {
  description = "OCI region"
  type        = string
}

variable "instance_name" {
  type = string
}

variable "instance_shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  type    = number
  default = 2
}

variable "instance_memory_gb" {
  type    = number
  default = 12
}

variable "instance_private_ip" {
  type    = string
  default = "10.0.0.137"
}

variable "ssh_public_key" {
  description = "SSH public key content for the instance"
  type        = string
}

variable "instance_image_ocid" {
  description = "OCI image OCID used to create gizmo"
  type        = string
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "data_volume_size_gb" {
  type    = number
  default = 150
}

variable "data_volume_vpus_per_gb" {
  type    = number
  default = 10
}

variable "compartment_name" {
  description = "Name of the OCI compartment"
  type        = string
}

variable "compartment_description" {
  description = "Description of the OCI compartment"
  type        = string
}

variable "bootstrap_ssh_cidr" {
  description = "CIDR temporarily allowed to access SSH during bootstrap or recovery. Null disables public SSH."
  type        = string
  default     = null
}