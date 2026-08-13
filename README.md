# OCI homelab

Terraform configuration for a small Oracle Cloud Infrastructure (OCI) homelab: a compartment, VCN/subnet, public ARM instance, reserved public IP, and attached data volume.

## Setup

1. Install [Terraform](https://developer.hashicorp.com/terraform/install) 1.5+ and configure OCI API-signing credentials (for example, `~/.oci/config` and the API-signing private key it references). This key authenticates Terraform to OCI; it is **not** used to log in to the server. Your OCI user needs permission to manage compartments, networking, compute, volumes, and public IPs in the tenancy.
2. Create a separate SSH key for the server (skip this if you already have one you want to use):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oci-homelab -C "oci-homelab"
```

3. Copy the example below to `terraform/oci/terraform.tfvars`, replacing every placeholder. Choose an image OCID for your region from the OCI Console.

```hcl
tenancy_ocid           = "ocid1.tenancy.oc1..example"
region                 = "eu-madrid-1"
compartment_name       = "homelab"
compartment_description = "Personal homelab"
instance_name          = "homelab"
instance_image_ocid    = "ocid1.image.oc1.eu-madrid-1.example"
ssh_public_key          = "ssh-ed25519 AAAA... oci-homelab"
```

4. Provision it:

```bash
cd terraform/oci
terraform init
terraform plan
terraform apply
```

For `ssh_public_key`, paste the one-line contents of `~/.ssh/oci-homelab.pub` (for example, from `cat ~/.ssh/oci-homelab.pub`).

Get the server address with `terraform output instance_public_ip`, then connect using the second key. The login user depends on the image (usually `ubuntu` for Ubuntu images and `opc` for Oracle Linux):

```bash
ssh -i ~/.ssh/oci-homelab ubuntu@"$(terraform output -raw instance_public_ip)"
```

The default shape is `VM.Standard.A1.Flex` with 2 OCPUs and 12 GB RAM. Adjust the optional values in `variables.tf` with a `terraform.tfvars` entry as needed.

> **Note:** SSH (22), HTTP (80), and HTTPS (443) are open to the internet. The reserved public IP and data volume are protected with `prevent_destroy`; remove those lifecycle guards deliberately before destroying them.
