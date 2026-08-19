[English](QUICKSTART.md) | [Español](QUICKSTART.es.md)

# Fresh-instance quickstart

This is the short path for a new OCI instance. See the [README](README.md) for
the full configuration reference.

1. Install Terraform, Ansible, Python 3 with PyYAML and rsync. Configure OCI
   credentials in `~/.oci/config`, then install the Ansible collections:

   ```bash
   cd ansible
   ansible-galaxy collection install -r requirements.yml
   cd ..
   ```

2. Create `terraform/bootstrap-state/terraform.tfvars` and
   `terraform/oci/terraform.tfvars`. These files are ignored by Git. The
   bootstrap-state file needs your tenancy OCID and region:

   ```hcl
   tenancy_ocid = "ocid1.tenancy.oc1..example"
   region       = "eu-madrid-1"
   ```

   The OCI file needs these values; `bootstrap_ssh_cidr` is your current
   public IP with `/32`:

   ```hcl
   tenancy_ocid            = "ocid1.tenancy.oc1..example"
   region                  = "eu-madrid-1"
   compartment_name        = "homelab"
   compartment_description = "Personal homelab"
   instance_name           = "homelab"
   instance_image_ocid     = "ocid1.image.oc1.eu-madrid-1.example"
   ssh_public_key          = "ssh-ed25519 AAAA... oci-homelab"
   bootstrap_ssh_cidr      = "YOUR.PUBLIC.IP/32"
   ```

3. Configure `ansible/inventory/group_vars/all/vars.yml` before generating an
   inventory. At minimum, set `homelab_domain`, `server_hostname`, time zones,
   `bootstrap_user` (to match the OCI image), administrator details and SSH
   key, the WireGuard peer and network, the data-disk label, and the managed
   and enabled stack lists. The generated inventory supplies Caddy's private
   bind IP, so do not maintain it by hand.

4. Create or update `ansible/inventory/group_vars/production/vault.yml` with
   Ansible Vault. Do not create stack `.env` files manually: Ansible renders
   them from these values.

   ```bash
   cd ansible
   ansible-vault edit inventory/group_vars/production/vault.yml
   cd ..
   ```

   ```yaml
   vault_grafana_admin_user: "..."
   vault_grafana_admin_password: "..."
   vault_grafana_oidc_client_secret: "..."
   vault_portainer_admin_password: "..."
   vault_portainer_oidc_client_secret: "..."
   vault_authentik_primary_user_password: "..."
   vault_authentik_pg_pass: "..."
   vault_authentik_secret_key: "..."
   vault_n8n_encryption_key: "..."
   vault_stirling_admin_user: "..."
   vault_stirling_admin_password: "..."
   vault_stirling_oidc_client_secret: "..."
   vault_paperless_db_password: "..."
   vault_paperless_secret_key: "..."
   vault_paperless_admin_user: "..."
   vault_paperless_admin_password: "..."
   vault_paperless_oidc_client_secret: "..."
   vault_wireguard_server_private_key: "..."
   vault_wireguard_pr819_public_key: "..."
   ```

   The default Caddy configuration also keeps apex and Airflow routes for
   unmanaged Apache and Airflow services. Deploy those services separately or
   remove their routes before provisioning a fresh host.

5. Create the Terraform state backend and provision OCI:

   ```bash
   cd terraform/bootstrap-state && terraform init && terraform apply && cd ../..
   ./scripts/generate-terraform-backend.sh
   cd terraform/oci && terraform init -backend-config=backend.hcl && terraform apply && cd ../..
   ```

6. Point the `@` and `*` DNS records for your domain to the reserved public IP.

7. Bootstrap the permanent administrator, then do the first full run over
   temporary public SSH:

   ```bash
   ./scripts/generate-ansible-inventory.sh bootstrap
   cd ansible && ansible-playbook -i inventory/bootstrap.yml playbooks/bootstrap.yml && cd ..
   ./scripts/generate-ansible-inventory.sh production-bootstrap
   cd ansible && ansible-playbook -i inventory/production.yml playbooks/site.yml -e data_disk_initialize=true --ask-vault-pass
   ```

8. Get the server public key with `sudo wg show wg0 public-key`, then configure
   the matching WireGuard client using its private key. Use the reserved public
   IP with port `51820` as the endpoint and verify it can SSH to `10.66.66.1`.

9. Switch future deployments to WireGuard. Then remove `bootstrap_ssh_cidr`
   from `terraform.tfvars` and close public SSH:

   ```bash
   cd .. && ./scripts/generate-ansible-inventory.sh production
   cd terraform/oci && terraform apply
   ```
