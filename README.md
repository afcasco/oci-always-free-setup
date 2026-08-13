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
tenancy_ocid            = "ocid1.tenancy.oc1..example"
region                  = "eu-madrid-1"

compartment_name        = "homelab"
compartment_description = "Personal homelab"

instance_name           = "homelab"
instance_image_ocid     = "ocid1.image.oc1.eu-madrid-1.example"
instance_private_ip     = "10.0.0.137"

ssh_public_key          = "ssh-ed25519 AAAA... oci-homelab"
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

This bootstrap configuration intentionally uses local state.

For a new environment, create the state bucket first:

```bash
cd terraform/bootstrap-state
terraform init
terraform plan
terraform apply
```

Then provision the homelab:

```bash
cd ../oci
terraform init
terraform plan
terraform apply
```

## Ansible inventory

Inventories are generated from Terraform outputs and are not committed.

From the repository root:

```bash
./scripts/generate-ansible-inventory.sh bootstrap
./scripts/generate-ansible-inventory.sh production
```

The two inventories serve different purposes:

- `bootstrap.yml` connects as the OCI image user (`bootstrap_user`, normally `ubuntu`).
- `production.yml` connects as the permanent `admin_user`.

`server_hostname`, `bootstrap_user`, and `admin_user` are configured in `vars.yml`.

## Fresh-machine deployment

### 1. Provision OCI

```bash
cd terraform/oci

terraform init
terraform plan
terraform apply

cd ../..
```

### 2. Bootstrap the administrator

```bash
./scripts/generate-ansible-inventory.sh bootstrap

cd ansible

ansible-playbook \
  -i inventory/bootstrap.yml \
  playbooks/bootstrap.yml
```

This creates the permanent administrator, installs its SSH key, and configures passwordless sudo for automation.

### 3. Configure and deploy

```bash
cd ..

./scripts/generate-ansible-inventory.sh production

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
- Managed but disabled stacks are stopped.
- Stacks not listed in `managed_stacks` are left untouched.

Only enabled stack configuration is synchronized to `/opt/stacks`.

Persistent data is stored separately under:

```text
/mnt/data/docker/
```

Docker image versions are pinned in the Compose files. Upgrades should be made deliberately by changing the pinned version.

## Check before applying

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

## Persistent resources

Terraform protects the persistent data volume and reserved public IP with `prevent_destroy`.

They therefore survive normal compute-instance replacement and cannot be destroyed accidentally without first changing the lifecycle configuration.

## Network exposure

OCI permits inbound:

- TCP/22 — SSH
- TCP/80 — HTTP
- TCP/443 — HTTPS

Public applications should normally be exposed through Caddy rather than by publishing their application ports directly.

## Repository boundaries

**Committed:**

- Terraform configuration
- Ansible configuration
- encrypted Ansible Vault
- Compose definitions
- configuration templates
- pinned container versions

**Not committed:**

- generated Ansible inventories
- Terraform variable files
- Terraform local state
- SSH/API private keys
- real `.env` files
- application data
- databases, logs, caches and backups