terraform {
  required_version = ">= 1.12.0"

  backend "oci" {
    bucket    = "homelab-terraform-state"
    namespace = "axaw5lxlnkxt"
    key       = "oci/terraform.tfstate"
    region    = "eu-madrid-1"
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}
provider "oci" {
  region = var.region
}

data "oci_identity_availability_domains" "available" {
  compartment_id = var.tenancy_ocid
}
