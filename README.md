[English](README.md) | [Español](README.es.md)

# OCI Homelab

My Docker homelab on Oracle Cloud Infrastructure (OCI), kept in code so I can
rebuild the server without losing the application data on `/mnt/data`.

- **Terraform** provisions OCI networking, compute, reserved public IP and persistent storage.
- **Ansible** bootstraps the host and reconciles managed Docker Compose stacks.
- **Caddy** provides HTTPS and reverse proxying.
- **Authentik** provides centralized authentication for Grafana and Portainer.

## Architecture

```text
Internet (80/443) → Caddy → Docker proxy network
                              ├── Authentik ── SSO/OIDC ── Grafana
                              │                         └── Portainer
                              ├── Uptime Kuma
                              └── other proxied services

Persistent state: /mnt/data/docker → OCI Block Volume
```

The deployment lifecycle is:

```text
Terraform state bootstrap → Terraform OCI → bootstrap inventory
→ Ansible bootstrap → production inventory → Ansible site playbook
```

## Repository layout

```text
ansible/     inventories, playbooks, roles and requirements
stacks/      Docker Compose stack definitions
terraform/   state bootstrap and OCI infrastructure
scripts/     inventory/backend generation helpers
```

Runtime state is kept outside the Git working tree.

# What you'll need

The deployment machine requires Terraform >= 1.12, Ansible, Python 3 with PyYAML, rsync, OCI API credentials and an SSH key. OCI credentials are expected in `~/.oci/config`.

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

# Before you start

## Terraform

Create these local files (they are intentionally not committed):

```text
terraform/bootstrap-state/terraform.tfvars
terraform/oci/terraform.tfvars
```

The bootstrap configuration requires `tenancy_ocid` and `region` and may define `state_bucket_name`.

The OCI configuration requires at least `tenancy_ocid`, `region`, `compartment_name`, `compartment_description`, `instance_name`, `instance_image_ocid` and `ssh_public_key`. Review network, instance-shape and volume defaults before applying.

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

Keep real `terraform.tfvars` files out of Git.

## Ansible

The non-secret settings live in `ansible/inventory/group_vars/all/vars.yml`.
Before a new deployment, set your domain, host/user details, SSH public key,
disk label, and the stacks you want enabled.

Production secrets are stored encrypted in `ansible/inventory/group_vars/production/vault.yml`.

```bash
cd ansible
ansible-vault edit inventory/group_vars/production/vault.yml
```

It must define non-empty values for these variables:

```yaml
vault_grafana_admin_user: "..."
vault_grafana_admin_password: "..."
vault_grafana_oidc_client_secret: "..."
vault_portainer_admin_password: "..."
vault_portainer_oidc_client_secret: "..."
vault_authentik_primary_user_password: "..."
vault_authentik_pg_pass: "..."
vault_authentik_secret_key: "..."
```

Use strong randomly generated values. Secret-bearing templates use `no_log: true`; new ones should do the same.

# Fresh deployment

## 1. Bootstrap Terraform state

Configure `terraform/bootstrap-state/terraform.tfvars`:

```bash
cd terraform/bootstrap-state
terraform init
terraform plan
terraform apply
cd ../..
```

Generate the main backend:

```bash
./scripts/generate-terraform-backend.sh
```

This creates the ignored `terraform/oci/backend.hcl`.

## 2. Provision OCI

Configure `terraform/oci/terraform.tfvars`:

```bash
cd terraform/oci
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
cd ../..
```

Terraform creates the compartment, networking, compute instance, reserved public IP and persistent block volume.

## 3. Bootstrap the server

```bash
./scripts/generate-ansible-inventory.sh bootstrap

cd ansible
ansible-playbook   -i inventory/bootstrap.yml   playbooks/bootstrap.yml
```

This creates the permanent administrator and configures SSH.

## 4. Deploy the homelab

```bash
cd ..
./scripts/generate-ansible-inventory.sh production
cd ansible
```

For the first run against a genuinely blank data volume:

```bash
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   -e data_disk_initialize=true   --ask-vault-pass
```

Subsequent runs must normally omit the initialization flag:

```bash
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   --ask-vault-pass
```

`data_disk_initialize=true` explicitly authorizes partitioning and formatting a blank disk. Ansible refuses to initialize disks containing existing partitions or signatures.

# Persistent resources and storage

Application state lives primarily under `/mnt/data/docker/`, on a separate OCI block volume.

Terraform protects the persistent data volume and reserved public IP with `prevent_destroy`. Compute is intended to be replaceable; persistent data is not.

The block volume still requires an independent backup strategy.

# Docker stack management

Compose definitions live under `stacks/`.

`managed_stacks` defines which stacks belong to Ansible. `enabled_stacks` defines which managed stacks should currently run. Managed-but-disabled stacks are stopped and removed; unmanaged stacks are left untouched.

Stacks can be reconciled independently:

```bash
cd ansible
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   --tags authentik   --ask-vault-pass
```

Current tags include `caddy`, `authentik`, `monitoring`, `portainer` and `uptime-kuma`.

Configuration is synchronized from `stacks/<stack>/` to `/opt/stacks/<stack>/`. Runtime state must therefore live outside synchronized paths unless explicitly excluded. Runtime `.env` files are rendered by Ansible and must not be maintained manually.

Enabled container images should be pinned to explicit versions.

# Reverse proxy, DNS and HTTPS

Caddy is the public ingress. OCI exposes TCP/22, TCP/80 and TCP/443; application containers should normally not publish their application ports directly.

Before deploying Caddy, configure both DNS records for `homelab_domain` to point to the reserved OCI public IPv4 address:

| Name | Target |
| --- | --- |
| `@` | Reserved OCI public IPv4 |
| `*` | Reserved OCI public IPv4 |

The wildcard does not cover the apex domain. Caddy obtains and renews public TLS certificates.

`Caddyfile.j2` currently declares these routes:

| Hostname | Backend |
| --- | --- |
| `{{ homelab_domain }}` | `apache:80` |
| `www.{{ homelab_domain }}` | Redirects to the apex domain |
| `n8n.{{ homelab_domain }}` | `n8n:5678` |
| `portainer.{{ homelab_domain }}` | `portainer:9000` |
| `status.{{ homelab_domain }}` | `uptime-kuma:3001` |
| `paperless.{{ homelab_domain }}` | `paperless:8000` |
| `pdf.{{ homelab_domain }}` | `stirling-pdf:8080` |
| `airflow.{{ homelab_domain }}` | `airflow-api-server:8080` |
| `grafana.{{ homelab_domain }}` | `grafana:3000` |
| `auth.{{ homelab_domain }}` | `authentik-server:9000` |

A configured route can exist while its backend is unmanaged or disabled; it
will fail to proxy until that backend is available.

# Authentication

Authentik provides centralized authentication for Grafana and Portainer. Their providers/applications are managed through Authentik Blueprints rendered by Ansible with secrets sourced from Vault.

Rendered Blueprints live under:

```text
/opt/stacks/authentik/blueprints/
```

Because they may contain passwords or OAuth secrets, the directory is private to the deployment administrator. The Authentik worker receives only the required read/traverse access through explicit POSIX ACLs; other users receive no access.

```text
deployment user     rwx directory / rw files
Authentik worker    r-x directory / r-- files
other users         no access
```

Ansible rejects configurations that enable Portainer or Monitoring while Authentik is disabled.

# Validation and normal operation

Preview significant Ansible changes:

```bash
cd ansible
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   --check   --diff   --ask-vault-pass
```

A second run on a converged host should normally report `changed=0` and `failed=0`.

Basic post-deployment checks:

```bash
docker ps
docker compose ls
findmnt /mnt/data
```

For infrastructure changes:

```bash
cd terraform/oci
terraform plan
```

A normal stack update is: change the repository configuration, preview it, reconcile the affected tag, verify the service, then commit.

# Rebuilding the compute instance

The compute instance can be recreated while retaining the protected OCI data volume and reserved IP:

1. Recreate the compute infrastructure with Terraform.
2. Generate the bootstrap inventory and run `bootstrap.yml`.
3. Generate the production inventory and run `site.yml`.
4. Reuse the persistent volume and reconcile the stacks.

Application recovery still depends on the integrity and backups of persistent application data.

# Repository boundaries and secrets

Committed: Terraform/Ansible configuration, encrypted Vault, Compose definitions, templates, Authentik Blueprint templates, helper scripts and documentation.

Do not commit generated `backend.hcl`, generated inventories, real `terraform.tfvars`, Terraform local state, SSH/OCI private keys, plaintext Vault contents, runtime `.env` files, application databases/data, logs, caches or backups.

Secret flow:

```text
Encrypted Ansible Vault → Ansible → runtime .env / Authentik Blueprints
```

The Vault password, OCI credentials and SSH private keys must be backed up separately; they are not recoverable from this repository.
