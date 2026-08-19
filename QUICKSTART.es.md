[English](QUICKSTART.md) | [Español](QUICKSTART.es.md)

# Guía rápida para una instancia nueva

Este es el camino corto para una instancia OCI nueva. Consulta el
[README](README.es.md) para toda la referencia de configuración.

1. Instalar Terraform, Ansible, Python 3 con PyYAML y rsync. Configurar las
   credenciales OCI en `~/.oci/config` e instalar las colecciones de Ansible:

   ```bash
   cd ansible
   ansible-galaxy collection install -r requirements.yml
   cd ..
   ```

2. Crear `terraform/bootstrap-state/terraform.tfvars` y
   `terraform/oci/terraform.tfvars`. Estos archivos están ignorados por Git.
   El archivo de estado necesita el OCID del tenancy y la región:

   ```hcl
   tenancy_ocid = "ocid1.tenancy.oc1..example"
   region       = "eu-madrid-1"
   ```

   El archivo de OCI necesita estos valores; `bootstrap_ssh_cidr` es tu IP
   pública actual con `/32`:

   ```hcl
   tenancy_ocid            = "ocid1.tenancy.oc1..example"
   region                  = "eu-madrid-1"
   compartment_name        = "homelab"
   compartment_description = "Homelab personal"
   instance_name           = "homelab"
   instance_image_ocid     = "ocid1.image.oc1.eu-madrid-1.example"
   ssh_public_key          = "ssh-ed25519 AAAA... oci-homelab"
   bootstrap_ssh_cidr      = "TU.IP.PUBLICA/32"
   ```

3. Configurar `ansible/inventory/group_vars/all/vars.yml` antes de generar un
   inventario. Como mínimo, definir `homelab_domain`, `server_hostname`, zonas
   horarias, `bootstrap_user` (debe coincidir con la imagen OCI), los datos y
   clave SSH del administrador, el peer y la red WireGuard, la etiqueta del
   disco de datos y las listas de stacks gestionados y habilitados. El
   inventario generado proporciona la IP privada de escucha de Caddy, por lo
   que no debe mantenerse manualmente.

4. Crear o actualizar `ansible/inventory/group_vars/production/vault.yml` con
   Ansible Vault. No crear manualmente los archivos `.env` de los stacks:
   Ansible los genera a partir de estos valores.

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

   La configuración predeterminada de Caddy también mantiene rutas del dominio
   raíz y Airflow para servicios Apache y Airflow no gestionados. Desplegar
   esos servicios por separado o eliminar sus rutas antes de aprovisionar un
   host nuevo.

5. Crear el backend de estado Terraform y aprovisionar OCI:

   ```bash
   cd terraform/bootstrap-state && terraform init && terraform apply && cd ../..
   ./scripts/generate-terraform-backend.sh
   cd terraform/oci && terraform init -backend-config=backend.hcl && terraform apply && cd ../..
   ```

6. Apuntar los registros DNS `@` y `*` del dominio a la IP pública reservada.

7. Crear el administrador permanente y hacer la primera ejecución completa por
   SSH público temporal:

   ```bash
   ./scripts/generate-ansible-inventory.sh bootstrap
   cd ansible && ansible-playbook -i inventory/bootstrap.yml playbooks/bootstrap.yml && cd ..
   ./scripts/generate-ansible-inventory.sh production-bootstrap
   cd ansible && ansible-playbook -i inventory/production.yml playbooks/site.yml -e data_disk_initialize=true --ask-vault-pass
   ```

8. Obtener la clave pública del servidor con `sudo wg show wg0 public-key` y
   configurar el cliente WireGuard correspondiente con su clave privada. Usar
   la IP pública reservada con puerto `51820` como endpoint y comprobar que
   puede hacer SSH a `10.66.66.1`.

9. Pasar los siguientes despliegues a WireGuard. Después, eliminar
   `bootstrap_ssh_cidr` de `terraform.tfvars` y cerrar SSH público:

   ```bash
   cd .. && ./scripts/generate-ansible-inventory.sh production
   cd terraform/oci && terraform apply
   ```
