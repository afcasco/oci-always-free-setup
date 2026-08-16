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
   `terraform/oci/terraform.tfvars`. Set the required OCI values and add
   `bootstrap_ssh_cidr = "YOUR.PUBLIC.IP/32"` to the latter.

3. Configure `ansible/inventory/group_vars/all/vars.yml`, then add every
   required secret—including the WireGuard keys—to the encrypted production
   Vault.

4. Create the Terraform state backend and provision OCI:

   ```bash
   cd terraform/bootstrap-state && terraform init && terraform apply && cd ../..
   ./scripts/generate-terraform-backend.sh
   cd terraform/oci && terraform init -backend-config=backend.hcl && terraform apply && cd ../..
   ```

5. Point the `@` and `*` DNS records for your domain to the reserved public IP.

6. Bootstrap the permanent administrator, then do the first full run over
   temporary public SSH:

   ```bash
   ./scripts/generate-ansible-inventory.sh bootstrap
   cd ansible && ansible-playbook -i inventory/bootstrap.yml playbooks/bootstrap.yml && cd ..
   ./scripts/generate-ansible-inventory.sh production-bootstrap
   cd ansible && ansible-playbook -i inventory/production.yml playbooks/site.yml -e data_disk_initialize=true --ask-vault-pass
   ```

7. Get the server public key with `sudo wg show wg0 public-key`, then configure
   the matching WireGuard client using its private key. Use the reserved public
   IP with port `51820` as the endpoint and verify it can SSH to `10.66.66.1`.

8. Switch future deployments to WireGuard. Then remove `bootstrap_ssh_cidr`
   from `terraform.tfvars` and close public SSH:

   ```bash
   cd .. && ./scripts/generate-ansible-inventory.sh production
   cd terraform/oci && terraform apply
   ```
