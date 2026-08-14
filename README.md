[English](README.md) | [Español](README.es.md)

# OCI Homelab

Infrastructure-as-code for an OCI homelab.

- **Terraform** provisions OCI infrastructure.
- **Ansible** configures the server and deploys managed Docker Compose stacks.
- Persistent application data lives on a separate OCI block volume mounted at `/mnt/data`.

## Prerequisites

Local machine:

- Terraform >= 1.12
- Ansible
- Python 3 + PyYAML
- rsync
- OCI API credentials (`~/.oci/config`)
- SSH key for the server

Install the required Ansible collections:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Configuration

### Terraform

Create:

```text
terraform/oci/terraform.tfvars
```

with the required OCI and instance values, for example:

```hcl
tenancy_ocid             = "ocid1.tenancy.oc1..example"
region                   = "eu-madrid-1"

compartment_name         = "homelab"
compartment_description  = "Personal homelab"

instance_name            = "homelab"
instance_image_ocid      = "ocid1.image.oc1.eu-madrid-1.example"
instance_private_ip      = "10.0.0.137"

ssh_public_key           = "ssh-ed25519 AAAA... oci-homelab"
```

`terraform.tfvars` is not committed.

### Ansible

Non-secret configuration:

```text
ansible/inventory/group_vars/all/vars.yml
```

Production secrets:

```text
ansible/inventory/group_vars/production/vault.yml
```

The Vault is encrypted and committed. Edit it with:

```bash
cd ansible
ansible-vault edit inventory/group_vars/production/vault.yml
```

## Terraform state

The main OCI configuration stores its state remotely in OCI Object Storage.

The state bucket is managed separately by:

```text
terraform/bootstrap-state/
```

This bootstrap configuration intentionally keeps its own state locally.

The main Terraform backend configuration is generated from the bootstrap outputs:

```bash
./scripts/generate-terraform-backend.sh
```

This creates the ignored file:

```text
terraform/oci/backend.hcl
```

from the state bucket name, Object Storage namespace, and region.

The main Terraform configuration is then initialized with:

```bash
terraform init -backend-config=backend.hcl
```

## Ansible inventory

Inventories are generated from Terraform outputs and are not committed:

```bash
./scripts/generate-ansible-inventory.sh bootstrap
./scripts/generate-ansible-inventory.sh production
```

- `bootstrap.yml` connects as the OCI image user (`bootstrap_user`, normally `ubuntu`).
- `production.yml` connects as the permanent `admin_user`.

`server_hostname`, `bootstrap_user`, and `admin_user` are configured in:

```text
ansible/inventory/group_vars/all/vars.yml
```

## Fresh-machine deployment

For a completely new environment:

### 1. Create the Terraform state bucket

Configure the bootstrap Terraform variables, then:

```bash
cd terraform/bootstrap-state

terraform init
terraform plan
terraform apply

cd ../..
```

This creates the OCI Object Storage bucket used by the main Terraform configuration.

### 2. Generate the main Terraform backend

```bash
./scripts/generate-terraform-backend.sh
```

This generates:

```text
terraform/oci/backend.hcl
```

from the bootstrap Terraform outputs.

### 3. Provision OCI

```bash
cd terraform/oci

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

cd ../..
```

This provisions the homelab compartment, networking, compute instance, reserved public IP, and persistent data volume.

### 4. Bootstrap the administrator

Generate an inventory that connects using the OCI image user:

```bash
./scripts/generate-ansible-inventory.sh bootstrap
```

Then:

```bash
cd ansible

ansible-playbook \
  -i inventory/bootstrap.yml \
  playbooks/bootstrap.yml
```

This creates the permanent administrator, installs its SSH key, and configures passwordless sudo for automation.

### 5. Configure and deploy

Generate the production inventory:

```bash
cd ..

./scripts/generate-ansible-inventory.sh production
```

Then:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --ask-vault-pass
```

Ansible configures:

```text
base
→ users/SSH
→ storage
→ Docker
→ Docker networks
→ Compose stacks
```

This includes mounting the persistent volume at `/mnt/data`, installing Docker, creating the shared `proxy` network, generating runtime configuration, and deploying enabled stacks.

## Stack management

Stack definitions live under:

```text
stacks/
```

Ansible uses two lists:

```yaml
managed_stacks:
  - caddy
  - portainer
  - uptime-kuma
  - monitoring

enabled_stacks:
  - caddy
  - portainer
  - uptime-kuma
  - monitoring
```

- `managed_stacks` defines which stacks Ansible owns.
- `enabled_stacks` defines which managed stacks should be running.
- Managed but disabled stacks are stopped and removed by Compose.
- Stacks not listed in `managed_stacks` are left untouched.

Configuration for enabled stacks is synchronized to:

```text
/opt/stacks/
```

The synchronized configuration is reconciled with the repository, so removed configuration files are also removed from the server. Runtime data, secrets, logs, databases, caches, and backups are excluded from synchronization.

Persistent application data is stored separately under:

```text
/mnt/data/docker/
```

Images used by the currently enabled stacks are pinned rather than using floating `latest` tags. Other stack definitions may still use floating tags and should be pinned before being enabled.

## Check before applying

Run Ansible in check mode before significant changes:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --check \
  --diff \
  --ask-vault-pass
```

A converged host should normally report no changes.

Terraform can be checked with:

```bash
cd terraform/oci
terraform plan
```

A converged environment should report:

```text
No changes. Your infrastructure matches the configuration.
```

## Persistent resources

Terraform protects the persistent data volume and reserved public IP with `prevent_destroy`.

They survive normal compute-instance replacement and cannot be destroyed without first deliberately removing the lifecycle protection.

## Network exposure

OCI permits inbound:

- TCP/22 — SSH
- TCP/80 — HTTP
- TCP/443 — HTTPS

Public applications should normally be exposed through Caddy rather than by publishing their application ports directly.

Caddy may also route to services managed outside Ansible. Such services do not need to appear in `managed_stacks`.

## Repository boundaries

**Committed:**

- Terraform configuration
- Terraform backend configuration example
- Ansible configuration
- encrypted Ansible Vault
- Compose definitions
- configuration templates
- helper scripts

**Not committed:**

- generated `terraform/oci/backend.hcl`
- generated Ansible inventories
- Terraform variable files
- Terraform local state
- SSH/API private keys
- real `.env` files
- application data
- databases, logs, caches, and backups