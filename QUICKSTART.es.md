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
   `terraform/oci/terraform.tfvars`. Definir los valores OCI necesarios y
   añadir `bootstrap_ssh_cidr = "TU.IP.PUBLICA/32"` al segundo.

3. Configurar `ansible/inventory/group_vars/all/vars.yml` y añadir todos los
   secretos necesarios—incluidas las claves de WireGuard—al Vault de
   producción cifrado.

4. Crear el backend de estado Terraform y aprovisionar OCI:

   ```bash
   cd terraform/bootstrap-state && terraform init && terraform apply && cd ../..
   ./scripts/generate-terraform-backend.sh
   cd terraform/oci && terraform init -backend-config=backend.hcl && terraform apply && cd ../..
   ```

5. Apuntar los registros DNS `@` y `*` del dominio a la IP pública reservada.

6. Crear el administrador permanente y hacer la primera ejecución completa por
   SSH público temporal:

   ```bash
   ./scripts/generate-ansible-inventory.sh bootstrap
   cd ansible && ansible-playbook -i inventory/bootstrap.yml playbooks/bootstrap.yml && cd ..
   ./scripts/generate-ansible-inventory.sh production-bootstrap
   cd ansible && ansible-playbook -i inventory/production.yml playbooks/site.yml -e data_disk_initialize=true --ask-vault-pass
   ```

7. Obtener la clave pública del servidor con `sudo wg show wg0 public-key` y
   configurar el cliente WireGuard correspondiente con su clave privada. Usar
   la IP pública reservada con puerto `51820` como endpoint y comprobar que
   puede hacer SSH a `10.66.66.1`.

8. Pasar los siguientes despliegues a WireGuard. Después, eliminar
   `bootstrap_ssh_cidr` de `terraform.tfvars` y cerrar SSH público:

   ```bash
   cd .. && ./scripts/generate-ansible-inventory.sh production
   cd terraform/oci && terraform apply
   ```
