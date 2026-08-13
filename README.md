# OCI Homelab

Infrastructure-as-code configuration for a small Oracle Cloud Infrastructure (OCI) homelab.

The repository is split into two layers:

- **Terraform** provisions the OCI infrastructure: compartment, networking, ARM compute instance, reserved public IP, and persistent data volume.
- **Ansible** bootstraps and configures the host, installs Docker, prepares persistent storage, and deploys the enabled Docker Compose stacks.

The intended goal is to be able to recreate the server from a fresh OCI instance without manually configuring the host.

## Prerequisites

Install:

- Terraform 1.5+
- Ansible
- Python 3
- `rsync`
- OCI CLI/configuration or equivalent OCI API-signing credentials

Terraform requires OCI API-signing credentials, typically configured in:

```text
~/.oci/config
```

The API-signing key referenced there authenticates Terraform to OCI. It is **not** the SSH key used to access the server.

The OCI user must have sufficient permissions to manage the resources created by this configuration, including:

- compartments
- networking
- compute instances
- block volumes
- reserved public IPs

## SSH key

Create a dedicated SSH key for the server if you do not already have one:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oci-homelab -C "oci-homelab"
```

The public key is provided to Terraform and installed on the initial OCI image user.

For example:

```bash
cat ~/.ssh/oci-homelab.pub
```

The corresponding private key remains local and is used by SSH/Ansible.

## Terraform configuration

Create:

```text
terraform/oci/terraform.tfvars
```

using the repository configuration as reference and replacing the environment-specific values.

For example:

```hcl
tenancy_ocid            = "ocid1.tenancy.oc1..example"
region                  = "eu-madrid-1"

compartment_name        = "homelab"
compartment_description = "Personal homelab"

instance_name           = "homelab"
instance_image_ocid     = "ocid1.image.oc1.eu-madrid-1.example"
instance_private_ip     = "10.0.0.137"

ssh_public_key          = "ssh-ed25519 AAAA... oci-homelab"
```

Choose an image OCID appropriate for the configured OCI region.

The default compute shape is:

```text
VM.Standard.A1.Flex
2 OCPUs
12 GB RAM
```

Optional Terraform variables can be overridden in `terraform.tfvars`.

## Provision the infrastructure

Initialize and review Terraform:

```bash
cd terraform/oci

terraform init
terraform plan
```

Then apply:

```bash
terraform apply
```

Useful outputs include:

```bash
terraform output instance_public_ip
terraform output instance_private_ip
terraform output instance_name
```

Terraform injects `ssh_public_key` into the instance using OCI instance metadata, allowing the initial image user to connect over SSH.

For Ubuntu images, the initial user is normally `ubuntu`.

For example:

```bash
ssh -i ~/.ssh/oci-homelab \
  ubuntu@"$(terraform output -raw instance_public_ip)"
```

## Ansible configuration

Install the required Ansible collections:

```bash
cd ansible

ansible-galaxy collection install -r requirements.yml
```

General non-secret configuration is stored under:

```text
ansible/inventory/group_vars/all/vars.yml
```

This includes values such as:

```yaml
server_hostname: gizmo
bootstrap_user: ubuntu
admin_user: afcasco
```

These values deliberately represent different concepts:

- `instance_name` — OCI resource/display name, managed by Terraform
- `server_hostname` — Linux hostname and Ansible logical host name
- `bootstrap_user` — initial user supplied by the OCI image
- `admin_user` — permanent administrative user created by Ansible

## Secrets

Production secrets are stored in the encrypted Ansible Vault:

```text
ansible/inventory/group_vars/production/vault.yml
```

Edit it with:

```bash
cd ansible

ansible-vault edit inventory/group_vars/production/vault.yml
```

The Vault currently contains secrets such as the Grafana administrator credentials.

Real `.env` files, private SSH keys, Terraform secrets, and other sensitive runtime files must not be committed.

## Generate Ansible inventories

Do not manually copy Terraform IP addresses into the Ansible inventory.

The inventory generator reads the Terraform outputs and Ansible configuration:

```bash
./scripts/generate-ansible-inventory.sh bootstrap
./scripts/generate-ansible-inventory.sh production
```

The bootstrap inventory connects using the initial OCI image user:

```yaml
ansible_user: ubuntu
```

The production inventory connects using the permanent administrative user:

```yaml
ansible_user: afcasco
```

The generated inventory also obtains the public and private IP addresses directly from Terraform.

This keeps Terraform as the source of truth for the infrastructure addresses.

## Bootstrap a fresh server

A newly created OCI instance does not yet contain the permanent administrative user.

Generate the bootstrap inventory:

```bash
./scripts/generate-ansible-inventory.sh bootstrap
```

Then run:

```bash
cd ansible

ansible-playbook \
  -i inventory/bootstrap.yml \
  playbooks/bootstrap.yml
```

The bootstrap playbook connects using `bootstrap_user` and:

- creates `admin_user`
- creates its home and SSH directory
- installs the configured SSH public key
- grants the required administrative groups

The bootstrap phase intentionally does **not** require the production Ansible Vault or Docker.

After bootstrap completes, subsequent configuration is performed using `admin_user`.

## Configure the server

Generate the production inventory:

```bash
./scripts/generate-ansible-inventory.sh production
```

Then run the complete configuration:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --ask-become-pass \
  --ask-vault-pass
```

The playbook configures the server in stages:

```text
base
  ↓
users_ssh
  ↓
storage
  ↓
docker
  ↓
docker_networks
  ↓
homelab
```

Among other things, Ansible:

- configures the Linux hostname
- installs base system packages
- manages the administrative user and SSH key
- detects the non-root data disk
- partitions and formats a blank data volume as ext4 when necessary
- mounts the data volume persistently at `/mnt/data` by UUID
- creates persistent application directories with the required ownership
- installs and configures Docker
- adds the configured administrator to the `docker` group
- creates the shared Docker `proxy` network
- copies only enabled stack configurations to `/opt/stacks`
- generates runtime `.env` files
- generates the Caddy configuration
- starts the enabled Docker Compose stacks

## Enabled stacks

Only stacks listed in the Ansible `enabled_stacks` variable are synchronized and started.

For example:

```yaml
enabled_stacks:
  - caddy
  - portainer
  - uptime-kuma
  - monitoring
```

Stack definitions are stored under:

```text
stacks/
```

Persistent application data is stored separately under:

```text
/mnt/data/docker/
```

This means application data is not part of the Git repository or copied by Ansible.

## Docker image versions

Docker images used by the managed stacks are pinned rather than using `latest`.

This makes deployments reproducible and prevents an Ansible run from unexpectedly upgrading a service to a newer image.

Upgrades should be performed deliberately by updating the image version in the corresponding Compose file, reviewing the change, and redeploying.

## Checking changes before applying

Use Ansible check mode before applying configuration changes:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --check \
  --diff \
  --ask-become-pass \
  --ask-vault-pass
```

A converged server should normally report no changes.

Some modules may report a prospective change in check mode even when a real run is idempotent. In particular, the Docker repository GPG-key download may appear as changed during `--check`.

## Fresh-machine rebuild

The complete rebuild sequence is:

```bash
# 1. Provision OCI infrastructure
cd terraform/oci
terraform init
terraform plan
terraform apply

# 2. Return to the repository root
cd ../..

# 3. Generate inventory for the initial OCI user
./scripts/generate-ansible-inventory.sh bootstrap

# 4. Create the permanent administrator
cd ansible
ansible-playbook \
  -i inventory/bootstrap.yml \
  playbooks/bootstrap.yml

# 5. Generate the normal production inventory
cd ..
./scripts/generate-ansible-inventory.sh production

# 6. Configure and deploy the server
cd ansible
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --ask-become-pass \
  --ask-vault-pass
```

The first bootstrap connection requires the SSH private key corresponding to the public key supplied to Terraform.

The Ansible Vault password is also external to the repository and must be available when applying the production configuration.

## Persistent resources and destruction protection

The reserved public IP and persistent data volume are protected with Terraform `prevent_destroy` lifecycle rules.

This is intentional: destroying the compute instance should not accidentally destroy persistent application data or the stable public IP.

Removing these resources therefore requires deliberately removing or changing the corresponding lifecycle protection first.

## Network exposure

The OCI network configuration permits inbound:

- SSH — TCP/22
- HTTP — TCP/80
- HTTPS — TCP/443

These ports are internet-accessible unless additional OCI or host-level restrictions are configured.

Services behind Caddy should normally be exposed through the reverse proxy rather than publishing their application ports directly.

## Repository boundaries

Committed:

- Terraform configuration
- Ansible roles and playbooks
- encrypted Ansible Vault
- Docker Compose definitions
- `.env.example` files
- configuration templates
- pinned container versions

Not committed:

- SSH private keys
- OCI API private keys
- real `.env` files
- application data
- databases
- logs
- caches
- backups
- Terraform variable files containing secrets