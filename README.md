[English](README.md) | [Español](README.es.md)

# OCI Homelab

Infrastructure-as-code for provisioning, configuring, and operating a
Docker-based homelab on Oracle Cloud Infrastructure (OCI).

The repository is designed so that infrastructure and application
configuration can be reconstructed from code while persistent application data
remains on a separate OCI block volume.

- **Terraform** provisions OCI networking, compute, persistent storage, and
  supporting infrastructure.
- **Ansible** bootstraps the server, configures the operating system, installs
  Docker, and reconciles managed Docker Compose stacks.
- **Docker Compose** defines the individual application stacks.
- **Caddy** provides HTTPS ingress and reverse proxying.
- **Authentik** provides centralized authentication for supported services.
- Persistent application data is stored on a separate OCI block volume mounted
  at `/mnt/data`.

---

## Architecture

At a high level:

```text
                        Internet
                           │
                     TCP 80 / 443
                           │
                           ▼
                    ┌─────────────┐
                    │    Caddy    │
                    │ HTTPS / RP  │
                    └──────┬──────┘
                           │
                    Docker proxy network
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
     Authentik         Portainer        Monitoring
          │                                │
          │                                └── Grafana
          │
          └────────────── SSO / OIDC

                   Other managed stacks
                           │
                           ▼
                      Uptime Kuma

Persistent application state
                           │
                           ▼
                    /mnt/data/docker
                           │
                           ▼
                  OCI Block Volume
```

Infrastructure lifecycle:

```text
Terraform bootstrap
        │
        ▼
OCI state bucket
        │
        ▼
Terraform OCI
        │
        ├── networking
        ├── compute instance
        ├── reserved public IP
        └── persistent block volume
        │
        ▼
Generate bootstrap inventory
        │
        ▼
Ansible bootstrap
        │
        └── permanent administrator + SSH
        │
        ▼
Generate production inventory
        │
        ▼
Ansible site playbook
        │
        ├── base configuration
        ├── users / SSH
        ├── storage
        ├── Docker
        ├── Docker networks
        └── managed Compose stacks
```

---

## Repository layout

The main repository structure is:

```text
.
├── ansible/
│   ├── inventory/
│   │   └── group_vars/
│   ├── playbooks/
│   ├── roles/
│   └── requirements.yml
│
├── stacks/
│   ├── authentik/
│   ├── caddy/
│   ├── monitoring/
│   ├── portainer/
│   └── uptime-kuma/
│
├── terraform/
│   ├── bootstrap-state/
│   └── oci/
│
└── scripts/
    ├── generate-ansible-inventory.sh
    └── generate-terraform-backend.sh
```

The repository contains infrastructure and configuration definitions, while
runtime state is kept outside the Git working tree.

---

# Prerequisites

## Local machine

The deployment machine requires:

- Terraform >= 1.12
- Ansible
- Python 3
- PyYAML
- rsync
- OCI API credentials
- an SSH key for the server

OCI CLI/API credentials are expected under:

```text
~/.oci/config
```

Install the required Ansible collections:

```bash
cd ansible

ansible-galaxy collection install -r requirements.yml
```

---

# Configuration

## Terraform variables

Terraform variable files contain environment-specific configuration and are not
committed.

Before a fresh deployment, create:

```text
terraform/bootstrap-state/terraform.tfvars
terraform/oci/terraform.tfvars
```

### Bootstrap state

`terraform/bootstrap-state/terraform.tfvars` requires:

- `tenancy_ocid`
- `region`

It may optionally define:

- `state_bucket_name`

The bootstrap Terraform configuration creates the OCI Object Storage bucket
used for the main Terraform remote state.

### OCI infrastructure

`terraform/oci/terraform.tfvars` requires the OCI and instance-specific
configuration, including:

- `tenancy_ocid`
- `region`
- `compartment_name`
- `compartment_description`
- `instance_name`
- `instance_image_ocid`
- `ssh_public_key`

Network, instance-shape, and data-volume settings have defaults but should be
reviewed before deployment.

Example:

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

Real `terraform.tfvars` files must not be committed.

---

## Ansible configuration

Non-secret Ansible configuration is stored in:

```text
ansible/inventory/group_vars/all/vars.yml
```

Review at least:

```text
homelab_domain
server_hostname
bootstrap_user
admin_user
admin_ssh_public_key
data_filesystem_label
managed_stacks
enabled_stacks
```

before deploying a new environment.

---

## Ansible Vault

Production secrets are stored in:

```text
ansible/inventory/group_vars/production/vault.yml
```

The Vault is encrypted and committed.

Edit it with:

```bash
cd ansible

ansible-vault edit inventory/group_vars/production/vault.yml
```

It must define non-empty values for all required secret variables, currently
including:

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

Use strong randomly generated values.

Secrets are rendered into runtime configuration by Ansible rather than stored
in plaintext in Git.

Tasks rendering secret-bearing files use `no_log: true` to prevent their
contents from appearing in normal Ansible output or `--diff` output. New
secret-bearing templates should follow the same rule.

---

# Terraform state

The main OCI Terraform configuration uses remote state stored in OCI Object
Storage.

The state bucket itself is managed separately by:

```text
terraform/bootstrap-state/
```

This bootstrap configuration intentionally keeps its own Terraform state
locally.

The bootstrap outputs are used to generate the backend configuration for the
main OCI Terraform project.

Run:

```bash
./scripts/generate-terraform-backend.sh
```

This creates:

```text
terraform/oci/backend.hcl
```

containing the required Object Storage namespace, bucket and region
configuration.

`backend.hcl` is generated and ignored by Git.

Initialize the main Terraform configuration with:

```bash
cd terraform/oci

terraform init -backend-config=backend.hcl
```

---

# Ansible inventory

Ansible inventories are generated from Terraform outputs and are not committed.

Two inventories are used during the lifecycle of a new machine.

## Bootstrap inventory

```bash
./scripts/generate-ansible-inventory.sh bootstrap
```

Generates:

```text
ansible/inventory/bootstrap.yml
```

This connects using the OCI image's initial user:

```text
bootstrap_user
```

normally `ubuntu`.

## Production inventory

```bash
./scripts/generate-ansible-inventory.sh production
```

Generates:

```text
ansible/inventory/production.yml
```

This connects using the permanent administrator created during bootstrap:

```text
admin_user
```

The relevant usernames and server hostname are configured in:

```text
ansible/inventory/group_vars/all/vars.yml
```

---

# Fresh-machine deployment

The following procedure reconstructs the homelab from a new OCI environment.

## 1. Create the Terraform state bucket

Configure:

```text
terraform/bootstrap-state/terraform.tfvars
```

Then run:

```bash
cd terraform/bootstrap-state

terraform init
terraform plan
terraform apply

cd ../..
```

This creates the OCI Object Storage bucket used for the main Terraform state.

---

## 2. Generate the Terraform backend

From the repository root:

```bash
./scripts/generate-terraform-backend.sh
```

This generates:

```text
terraform/oci/backend.hcl
```

from the bootstrap Terraform outputs.

---

## 3. Provision OCI infrastructure

Configure:

```text
terraform/oci/terraform.tfvars
```

Then:

```bash
cd terraform/oci

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

cd ../..
```

Terraform provisions the homelab infrastructure, including:

- OCI compartment
- networking
- compute instance
- reserved public IP
- persistent data block volume

---

## 4. Generate the bootstrap inventory

```bash
./scripts/generate-ansible-inventory.sh bootstrap
```

The generated inventory connects using the original OCI image user.

---

## 5. Bootstrap the permanent administrator

```bash
cd ansible

ansible-playbook \
  -i inventory/bootstrap.yml \
  playbooks/bootstrap.yml
```

The bootstrap playbook creates the permanent administrator, installs the
configured SSH public key, and configures passwordless sudo for automation.

---

## 6. Generate the production inventory

Return to the repository root:

```bash
cd ..

./scripts/generate-ansible-inventory.sh production
```

---

## 7. Configure and deploy the server

For the **first run against a new empty data volume**:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  -e data_disk_initialize=true \
  --ask-vault-pass
```

`data_disk_initialize=true` explicitly authorizes Ansible to partition and
format a genuinely blank data disk.

Do not normally provide this option again.

Subsequent runs should use:

```bash
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --ask-vault-pass
```

The site playbook configures approximately:

```text
base
  ↓
users / SSH
  ↓
storage
  ↓
Docker
  ↓
Docker networks
  ↓
managed Compose stacks
```

This includes mounting persistent storage at `/mnt/data`, installing Docker,
creating shared networks, generating runtime configuration, and reconciling
enabled application stacks.

---

# Storage safety

Persistent application state is deliberately separated from the compute
instance.

The OCI data volume is mounted at:

```text
/mnt/data
```

Application state is stored primarily under:

```text
/mnt/data/docker/
```

## Disk initialization protection

Ansible does not assume that an unpartitioned disk is empty.

Before initializing a detected data disk it checks for:

- existing partitions
- filesystem signatures
- other disk signatures

If an unpartitioned disk contains an existing signature, Ansible refuses to
create a partition table.

A genuinely blank disk is also not initialized automatically. Initialization
requires the explicit:

```text
data_disk_initialize=true
```

opt-in.

This protects against accidentally overwriting a disk containing a filesystem
directly on the block device.

The initialization flag should therefore only be supplied when intentionally
preparing a new empty data volume.

---

# Persistent OCI resources

Terraform protects important persistent resources with lifecycle
`prevent_destroy` rules.

These include:

- the persistent data volume
- the reserved public IP

They survive normal compute-instance replacement and Terraform refuses to
destroy them unless the lifecycle protection is deliberately removed first.

The compute instance should therefore be treated as replaceable infrastructure,
while persistent state lives on separately protected resources.

---

# Docker stack management

Docker Compose definitions live under:

```text
stacks/
```

Ansible distinguishes between stacks it manages and stacks that should
currently be enabled.

Example:

```yaml
managed_stacks:
  - caddy
  - portainer
  - uptime-kuma
  - monitoring
  - authentik

enabled_stacks:
  - caddy
  - portainer
  - uptime-kuma
  - monitoring
  - authentik
```

## `managed_stacks`

Defines which application stacks belong to Ansible.

Stacks absent from this list are outside Ansible's lifecycle management.

This allows manually managed applications to coexist on the same server
without Ansible stopping or modifying them.

## `enabled_stacks`

Defines which managed stacks should currently be running.

A stack that is:

```text
managed + enabled
```

is reconciled and started.

A stack that is:

```text
managed + disabled
```

is stopped and removed through Docker Compose.

A stack that is:

```text
not managed
```

is left untouched.

---

# Per-stack reconciliation

Managed stacks have dedicated Ansible task files and can be reconciled
independently.

For example, Portainer can be reconciled without redeploying every other
application:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --tags portainer \
  --ask-vault-pass
```

Current stack tags include:

```text
caddy
authentik
monitoring
portainer
uptime-kuma
```

For example:

```bash
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --tags monitoring \
  --ask-vault-pass
```

or:

```bash
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --tags authentik \
  --ask-vault-pass
```

Cross-stack safety validation marked with the Ansible `always` tag still runs
during targeted reconciliation.

This prevents targeted deployments from bypassing required dependency checks.

---

# Stack synchronization

Configuration for enabled stacks is synchronized from:

```text
stacks/<stack>/
```

to:

```text
/opt/stacks/<stack>/
```

The server-side stack configuration is reconciled with the repository, meaning
configuration files removed from Git are also removed from the corresponding
server stack directory.

Runtime state must therefore not live directly in synchronized configuration
paths unless explicitly excluded.

Common exclusions include:

```text
.env
.env.*
data/
logs/
postgres/
cache/
heap_dumps/
backup/
__pycache__/
*.db
*.sqlite
*.rdb
*.log
*.key
*.pem
```

Persistent application state should instead live under `/mnt/data/docker/`.

Stack-specific exclusions can be added where configuration is rendered
directly by Ansible rather than synchronized verbatim.

---

# Runtime environment files

Runtime `.env` files are generated by Ansible and are not committed.

Do not manually maintain these files on the server.

For example, the monitoring stack receives values such as:

```text
GRAFANA_URL
AUTHENTIK_URL
```

from Ansible configuration.

These are derived from variables such as:

```text
homelab_domain
```

rather than hard-coded into the Compose definition.

Changing the configured homelab domain therefore updates the corresponding
runtime URLs during reconciliation.

---

# Reverse proxy and HTTPS

Caddy provides public ingress for web applications.

OCI permits inbound:

```text
TCP/22   SSH
TCP/80   HTTP
TCP/443  HTTPS
```

Application containers should normally not publish their application ports
directly to the public network.

Instead:

```text
Internet
   │
   ▼
Caddy :443
   │
   ▼
Docker proxy network
   │
   ▼
Application container
```

Caddy configuration is generated by Ansible from:

```text
Caddyfile.j2
```

and deployed to the Caddy stack.

Caddy may also proxy services that are not managed by Ansible. Those services
do not need to appear in `managed_stacks`.

## DNS prerequisite

DNS is intentionally outside this repository: neither Terraform nor Ansible
creates DNS records. Before the first Caddy deployment, configure the DNS zone
for `homelab_domain` with both of the following `A` records pointing at the
reserved OCI public IPv4 address:

| Name | Target | Purpose |
| --- | --- | --- |
| `@` | Reserved OCI public IPv4 | The apex domain |
| `*` | Reserved OCI public IPv4 | Every service subdomain |

The wildcard record does not cover the apex record, so both are required.
Caddy obtains and renews public TLS certificates for the hostnames declared in
its generated configuration; DNS must resolve to the server and TCP ports 80
and 443 must remain publicly reachable.

## Caddy routes

`Caddyfile.j2` currently declares these routes. A route can exist even when
its backend is not managed or is disabled; in that case the hostname may
resolve successfully but return a proxy error until its backend is available.

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

---

# Authentication

Authentik provides centralized authentication for supported applications.

Currently, Authentik is used by:

- Grafana
- Portainer

Application/provider configuration is managed through Authentik Blueprints
rendered by Ansible.

Blueprint templates are kept in the Ansible configuration, while their
sensitive values come from Ansible Vault.

Rendered Blueprints are stored under:

```text
/opt/stacks/authentik/blueprints/
```

## Blueprint permissions

Blueprints may contain passwords or OAuth client secrets and are therefore
treated as secret-bearing runtime files.

The Blueprint directory is private to the deployment administrator.

The Authentik worker runs under a separate UID and receives only the filesystem
access required to consume the Blueprints through explicit POSIX ACLs.

Conceptually:

```text
deployment user
    │
    ├── rwx  blueprints/
    └── rw-  *.yaml

Authentik worker UID
    │
    ├── r-x  blueprints/
    └── r--  *.yaml

other users
    │
    └── no access
```

This allows Authentik to reconcile the files without making credentials
world-readable.

---

# Stack dependencies

Some applications depend on other managed stacks.

In particular:

```text
Portainer ────┐
              ├──► Authentik
Grafana ──────┘
```

Ansible validates these dependencies before stack reconciliation.

A configuration enabling `portainer` or `monitoring` while disabling
`authentik` is rejected.

This prevents applications configured exclusively for Authentik authentication
from being left running with an unavailable identity provider.

Dependency validation also runs during targeted stack deployments.

---

# Checking changes before applying

## Ansible

For significant configuration changes, first run:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --check \
  --diff \
  --ask-vault-pass
```

A fully converged host should normally report no changes.

Secret-bearing tasks use `no_log: true`, preventing rendered credentials from
being included in Ansible diff output.

Check mode cannot perfectly simulate every Docker or external-service action,
so its output should still be reviewed before applying.

Apply normally with:

```bash
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --ask-vault-pass
```

A second run after a successful deployment should ideally converge to:

```text
changed=0
failed=0
```

---

## Terraform

Before infrastructure changes:

```bash
cd terraform/oci

terraform plan
```

A converged environment should report:

```text
No changes. Your infrastructure matches the configuration.
```

---

# Basic validation

Useful post-deployment checks include:

```bash
docker ps
```

and:

```bash
docker compose ls
```

On a fully converged deployment, all enabled stacks should be running and
persistent storage should be mounted:

```bash
findmnt /mnt/data
```

The server should expose only the intentionally public ports, with web
applications reached through Caddy.

---

# Updating a stack

A typical stack change follows this workflow:

```text
modify repository configuration
        │
        ▼
Ansible --check --diff
        │
        ▼
targeted stack reconciliation
        │
        ▼
verify service
        │
        ▼
full convergence check if necessary
```

For example:

```bash
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --tags portainer \
  --check \
  --diff \
  --ask-vault-pass
```

followed by:

```bash
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --tags portainer \
  --ask-vault-pass
```

---

# Image versioning

Images used by currently enabled stacks should be pinned to explicit versions
rather than floating `latest` tags.

This makes rebuilds reproducible and prevents an unrelated container image
release from silently changing the environment during reconciliation.

Stack definitions that are not currently enabled may still contain floating
tags and should be reviewed and pinned before being enabled.

Image upgrades should be intentional:

```text
change pinned version
        ↓
review upstream release
        ↓
Ansible check
        ↓
deploy affected stack
        ↓
verify
        ↓
commit
```

---

# Rebuilding the compute instance

The architecture separates replaceable compute from persistent application
state.

Conceptually:

```text
               ┌────────────────────┐
               │ Terraform / Ansible│
               │        Git         │
               └─────────┬──────────┘
                         │
                         ▼
                Replaceable compute
                         │
                         │ mounts
                         ▼
               Persistent OCI volume
                  /mnt/data/docker
```

If the compute instance must be recreated:

1. Preserve the protected OCI data volume.
2. Recreate the compute infrastructure with Terraform.
3. Generate the bootstrap inventory.
4. Run the Ansible bootstrap playbook.
5. Generate the production inventory.
6. Run the production site playbook.
7. Mount/reuse the persistent data volume.
8. Reconcile the managed stacks.

Application-specific recovery may still depend on the recovery behavior of each
application and its database, so persistent storage should also have an
independent backup strategy.

---

# Repository boundaries

## Committed

The repository intentionally contains:

- Terraform configuration
- Terraform backend configuration example
- Ansible configuration
- encrypted Ansible Vault
- Docker Compose definitions
- Ansible templates
- Authentik Blueprint templates
- helper scripts
- documentation

## Not committed

The repository must not contain:

- generated `terraform/oci/backend.hcl`
- generated Ansible inventories
- Terraform variable files
- Terraform local state
- SSH private keys
- OCI API private keys
- plaintext Vault contents
- real `.env` files
- application databases
- application data
- logs
- caches
- backups

---

# Secret management

The intended secret flow is:

```text
Encrypted Ansible Vault
          │
          ▼
       Ansible
          │
          ├──► runtime .env files
          │
          └──► Authentik Blueprints
                     │
                     ▼
               application config
```

Plaintext runtime secrets exist on the target machine where required by the
applications but should never be committed to Git.

If the local machine is lost, the encrypted Vault remains recoverable from the
repository **only if the Vault password is still available**.

The Vault password must therefore be backed up independently in a password
manager or another secure location.

Likewise, OCI credentials and SSH private keys are not recoverable from this
repository and require their own backup/recovery strategy.

---

# Operational principles

The repository follows several general rules:

1. **Infrastructure is reproducible.**  
   OCI resources are defined with Terraform.

2. **Server configuration is reproducible.**  
   Host and Docker configuration are managed through Ansible.

3. **Persistent data is separated from compute.**  
   Application state lives on a dedicated OCI block volume.

4. **Destructive storage operations require explicit authorization.**  
   A blank disk is not formatted merely because Ansible discovers it.

5. **Secrets are not stored in plaintext in Git.**  
   Production secrets originate from encrypted Ansible Vault.

6. **Application stacks are independently reconcilable.**  
   Individual services can be deployed using Ansible tags.

7. **Dependencies are validated.**  
   Invalid combinations such as Authentik-dependent services without
   Authentik are rejected before reconciliation.

8. **Public services go through the reverse proxy.**  
   Application ports should not normally be exposed directly.

9. **Container versions are pinned.**  
   Enabled stacks should use reproducible image versions rather than
   uncontrolled floating tags.

10. **Manual server configuration should be minimized.**  
    Changes required to rebuild or operate the environment should be captured
    in Terraform, Ansible, Compose, templates, or documentation.
