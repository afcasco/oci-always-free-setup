[English](README.md) | [Español](README.es.md)

# Homelab en OCI

Infraestructura como código para un homelab alojado en OCI.

- **Terraform** aprovisiona la infraestructura de OCI.
- **Ansible** configura el servidor y despliega los stacks de Docker Compose gestionados.
- Los datos persistentes de las aplicaciones se almacenan en un volumen de bloques de OCI independiente, montado en `/mnt/data`.

## Requisitos previos

En la máquina local:

- Terraform >= 1.12
- Ansible
- Python 3 + PyYAML
- rsync
- Credenciales de la API de OCI (`~/.oci/config`)
- Clave SSH para el servidor

Instalar las colecciones de Ansible necesarias:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Configuración

### Terraform

Crear:

```text
terraform/oci/terraform.tfvars
```

con los valores necesarios para OCI y la instancia. Por ejemplo:

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

`terraform.tfvars` no se versiona en Git.

### Ansible

Configuración no secreta:

```text
ansible/inventory/group_vars/all/vars.yml
```

Secretos de producción:

```text
ansible/inventory/group_vars/production/vault.yml
```

El Vault está cifrado y se versiona en Git. Para editarlo:

```bash
cd ansible
ansible-vault edit inventory/group_vars/production/vault.yml
```

## Estado de Terraform

La configuración principal de OCI almacena su estado de forma remota en OCI Object Storage.

El bucket utilizado para almacenar el estado se gestiona de forma independiente mediante:

```text
terraform/bootstrap-state/
```

Esta configuración de bootstrap mantiene intencionadamente su propio estado de forma local.

La configuración del backend del Terraform principal se genera a partir de los outputs del bootstrap:

```bash
./scripts/generate-terraform-backend.sh
```

Esto genera el archivo ignorado por Git:

```text
terraform/oci/backend.hcl
```

utilizando el nombre del bucket, el namespace de Object Storage y la región.

A continuación se inicializa la configuración principal de Terraform con:

```bash
terraform init -backend-config=backend.hcl
```

## Inventario de Ansible

Los inventarios se generan a partir de los outputs de Terraform y no se versionan en Git:

```bash
./scripts/generate-ansible-inventory.sh bootstrap
./scripts/generate-ansible-inventory.sh production
```

- `bootstrap.yml` se conecta utilizando el usuario inicial de la imagen de OCI (`bootstrap_user`, normalmente `ubuntu`).
- `production.yml` se conecta utilizando el `admin_user` permanente.

`server_hostname`, `bootstrap_user` y `admin_user` se configuran en:

```text
ansible/inventory/group_vars/all/vars.yml
```

## Despliegue desde cero

Para desplegar un entorno completamente nuevo:

### 1. Crear el bucket para el estado de Terraform

Configurar las variables necesarias del Terraform de bootstrap y ejecutar:

```bash
cd terraform/bootstrap-state

terraform init
terraform plan
terraform apply

cd ../..
```

Esto crea el bucket de OCI Object Storage que utilizará la configuración principal de Terraform.

### 2. Generar el backend del Terraform principal

```bash
./scripts/generate-terraform-backend.sh
```

Esto genera:

```text
terraform/oci/backend.hcl
```

a partir de los outputs del Terraform de bootstrap.

### 3. Aprovisionar la infraestructura de OCI

```bash
cd terraform/oci

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

cd ../..
```

Esto aprovisiona el compartment del homelab, la red, la instancia de Compute, la IP pública reservada y el volumen de datos persistente.

### 4. Crear el administrador del servidor

Generar un inventario que se conecte utilizando el usuario inicial de la imagen de OCI:

```bash
./scripts/generate-ansible-inventory.sh bootstrap
```

Después:

```bash
cd ansible

ansible-playbook \
  -i inventory/bootstrap.yml \
  playbooks/bootstrap.yml
```

Esto crea el administrador permanente, instala su clave SSH y configura `sudo` sin contraseña para la automatización.

### 5. Configurar y desplegar el servidor

Generar el inventario de producción:

```bash
cd ..

./scripts/generate-ansible-inventory.sh production
```

Después:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --ask-vault-pass
```

Ansible configura:

```text
base
→ usuarios/SSH
→ almacenamiento
→ Docker
→ redes de Docker
→ stacks de Compose
```

Esto incluye montar el volumen persistente en `/mnt/data`, instalar Docker, crear la red compartida `proxy`, generar la configuración necesaria en tiempo de ejecución y desplegar los stacks habilitados.

## Gestión de stacks

Las definiciones de los stacks se encuentran en:

```text
stacks/
```

Ansible utiliza dos listas:

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

- `managed_stacks` define qué stacks son responsabilidad de Ansible.
- `enabled_stacks` define qué stacks gestionados deben estar en ejecución.
- Los stacks gestionados pero deshabilitados se detienen y eliminan mediante Compose.
- Los stacks que no aparecen en `managed_stacks` no son modificados por Ansible.

La configuración de los stacks habilitados se sincroniza en:

```text
/opt/stacks/
```

La configuración sincronizada se reconcilia con el repositorio, por lo que los archivos de configuración eliminados del repositorio también se eliminan del servidor.

Los datos de ejecución, secretos, logs, bases de datos, cachés y backups quedan excluidos de esta sincronización.

Los datos persistentes de las aplicaciones se almacenan por separado en:

```text
/mnt/data/docker/
```

Las imágenes utilizadas por los stacks actualmente habilitados utilizan versiones fijadas en lugar de tags flotantes como `latest`. Otros stacks disponibles pueden seguir utilizando tags flotantes y deberían fijarse antes de habilitarlos.

## Comprobar antes de aplicar cambios

Antes de realizar cambios importantes con Ansible:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --check \
  --diff \
  --ask-vault-pass
```

Un servidor correctamente convergido normalmente no debería mostrar cambios.

Terraform puede comprobarse con:

```bash
cd terraform/oci
terraform plan
```

Un entorno convergido debería mostrar:

```text
No changes. Your infrastructure matches the configuration.
```

## Recursos persistentes

Terraform protege el volumen de datos persistente y la IP pública reservada mediante `prevent_destroy`.

Por tanto, estos recursos sobreviven al reemplazo normal de la instancia de Compute y no pueden destruirse accidentalmente sin eliminar primero de forma explícita esta protección del ciclo de vida.

## Exposición de red

OCI permite tráfico entrante en:

- TCP/22 — SSH
- TCP/80 — HTTP
- TCP/443 — HTTPS

Las aplicaciones públicas deberían exponerse normalmente a través de Caddy en lugar de publicar directamente sus puertos de aplicación.

Caddy también puede enrutar tráfico hacia servicios gestionados fuera de Ansible. Estos servicios no necesitan aparecer en `managed_stacks`.

## Contenido del repositorio

**Versionado en Git:**

- configuración de Terraform
- ejemplo de configuración del backend de Terraform
- configuración de Ansible
- Ansible Vault cifrado
- definiciones de Compose
- plantillas de configuración
- scripts auxiliares

**No versionado en Git:**

- `terraform/oci/backend.hcl` generado
- inventarios de Ansible generados
- archivos de variables de Terraform
- estado local de Terraform
- claves privadas SSH/API
- archivos `.env` reales
- datos de las aplicaciones
- bases de datos, logs, cachés y backups