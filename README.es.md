[English](README.md) | [Español](README.es.md)

# OCI Homelab

Infraestructura como código para aprovisionar, configurar y operar un homelab Docker en Oracle Cloud Infrastructure (OCI). La infraestructura se reconstruye desde código y los datos persistentes se conservan en un volumen OCI independiente montado en `/mnt/data`.

- **Terraform** aprovisiona red, cómputo, IP pública y almacenamiento OCI.
- **Ansible** prepara el sistema, instala Docker y reconcilia los stacks gestionados.
- **Docker Compose** define las aplicaciones; **Caddy** proporciona HTTPS y proxy inverso; **Authentik** ofrece autenticación centralizada.

## Arquitectura

```text
Internet (80/443) → Caddy → red proxy de Docker
                              ├── Authentik ── SSO/OIDC ── Grafana y Portainer
                              ├── Monitoring / Grafana
                              └── Uptime Kuma

Estado persistente: /mnt/data/docker → volumen de bloques OCI
```

El ciclo de vida es: Terraform bootstrap → bucket de estado OCI → Terraform OCI → inventario bootstrap → Ansible bootstrap → inventario de producción → playbook site.

## Estructura del repositorio

```text
ansible/     inventario, playbooks, roles y requirements
stacks/      definiciones de Docker Compose
terraform/   bootstrap-state y oci
scripts/     generación de inventario y backend
```

El estado de ejecución queda fuera del árbol de Git.

---

# Requisitos previos

En el equipo de despliegue se necesitan Terraform >= 1.12, Ansible, Python 3 con PyYAML, rsync, credenciales de API de OCI y una clave SSH. Las credenciales de OCI se esperan en `~/.oci/config`.

```bash
cd ansible

ansible-galaxy collection install -r requirements.yml
```

---

# Configuración

## Variables de Terraform

Crear los archivos no versionados:

```text
terraform/bootstrap-state/terraform.tfvars
terraform/oci/terraform.tfvars
```

El archivo de bootstrap requiere `tenancy_ocid` y `region`, y puede definir `state_bucket_name`. El archivo de OCI requiere `tenancy_ocid`, `region`, `compartment_name`, `compartment_description`, `instance_name`, `instance_image_ocid` y `ssh_public_key`. Revisar los valores por defecto de red, forma de instancia y volumen antes de aplicar.

Ejemplo de `terraform/oci/terraform.tfvars`:

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

No versionar archivos reales `terraform.tfvars`.

## Configuración de Ansible

La configuración no secreta está en `ansible/inventory/group_vars/all/vars.yml`. Antes de desplegar, revisar `homelab_domain`, `server_hostname`, `bootstrap_user`, `admin_user`, `admin_ssh_public_key`, `data_filesystem_label`, `managed_stacks` y `enabled_stacks`.

## Ansible Vault

Los secretos de producción están cifrados y versionados en `ansible/inventory/group_vars/production/vault.yml`.

```bash
cd ansible

ansible-vault edit inventory/group_vars/production/vault.yml
```

Debe contener valores no vacíos para:

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

Usar valores aleatorios robustos. Ansible renderiza los secretos en la configuración de ejecución; no se guardan en texto plano en Git. Las tareas que generan archivos con secretos usan `no_log: true` y las nuevas plantillas deben hacer lo mismo.

---

# Estado de Terraform

El estado principal se guarda en OCI Object Storage. El bucket se gestiona por separado en `terraform/bootstrap-state/`, cuyo propio estado es local. Generar la configuración del backend principal:

```bash
./scripts/generate-terraform-backend.sh
```

Genera el archivo ignorado `terraform/oci/backend.hcl`. Inicializarlo:

```bash
cd terraform/oci

terraform init -backend-config=backend.hcl
```

---

# Inventario de Ansible

Los inventarios se generan desde outputs de Terraform y no se versionan.

```bash
./scripts/generate-ansible-inventory.sh bootstrap
./scripts/generate-ansible-inventory.sh production
```

El primero genera `ansible/inventory/bootstrap.yml` y conecta como `bootstrap_user` (normalmente `ubuntu`). El segundo genera `ansible/inventory/production.yml` y conecta como el `admin_user` creado durante el bootstrap.

---

# Despliegue desde cero

## 1. Crear el bucket de estado

Configurar `terraform/bootstrap-state/terraform.tfvars` y ejecutar:

```bash
cd terraform/bootstrap-state

terraform init
terraform plan
terraform apply

cd ../..
```

## 2. Generar el backend

```bash
./scripts/generate-terraform-backend.sh
```

## 3. Aprovisionar OCI

Configurar `terraform/oci/terraform.tfvars` y ejecutar:

```bash
cd terraform/oci

terraform init -backend-config=backend.hcl
terraform plan
terraform apply

cd ../..
```

Terraform crea el compartment, la red, la instancia, la IP pública reservada y el volumen persistente.

## 4. Generar el inventario bootstrap y crear el administrador

```bash
./scripts/generate-ansible-inventory.sh bootstrap

cd ansible

ansible-playbook \
  -i inventory/bootstrap.yml \
  playbooks/bootstrap.yml
```

## 5. Generar el inventario de producción y desplegar

```bash
cd ..

./scripts/generate-ansible-inventory.sh production

cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  -e data_disk_initialize=true \
  --ask-vault-pass
```

Este indicador sólo se usa en la primera ejecución sobre un volumen nuevo y vacío: autoriza a Ansible a crear una partición y formatearla. Las ejecuciones posteriores no deben incluirlo:

```bash
ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --ask-vault-pass
```

El playbook configura base, usuarios/SSH, almacenamiento, Docker, redes Docker y stacks Compose gestionados.

---

# Seguridad del almacenamiento

Los datos persistentes se separan de la instancia. El volumen OCI se monta en `/mnt/data` y el estado de aplicaciones reside principalmente en `/mnt/data/docker/`.

## Protección de inicialización de disco

Ansible no supone que un disco sin particiones esté vacío. Comprueba particiones, firmas de sistemas de archivos y otras firmas de disco. Si encuentra una firma, se niega a crear una tabla de particiones. Un disco realmente vacío requiere el opt-in explícito `data_disk_initialize=true`; esto protege sistemas de archivos situados directamente en el dispositivo de bloques.

## Recursos OCI persistentes

Terraform protege el volumen de datos y la IP pública reservada con `prevent_destroy`. Sobreviven al reemplazo normal de la instancia; Terraform no los destruye hasta retirar deliberadamente esa protección.

---

# Gestión de stacks Docker

Los stacks viven en `stacks/`. Ansible distingue los stacks que gestiona de los que deben ejecutarse:

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

`managed_stacks` define el ciclo de vida bajo Ansible; los stacks ausentes pueden coexistir sin ser modificados. Un stack gestionado y habilitado se reconcilia e inicia. Uno gestionado y deshabilitado se detiene y elimina con Compose.

## Reconciliación por stack

Los stacks se pueden reconciliar independientemente. Ejemplo:

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --tags portainer \
  --ask-vault-pass
```

Las etiquetas disponibles son `caddy`, `authentik`, `monitoring`, `portainer` y `uptime-kuma`. La validación de dependencias, marcada con `always`, también se ejecuta en despliegues dirigidos.

## Sincronización y entorno de ejecución

La configuración se sincroniza de `stacks/<stack>/` a `/opt/stacks/<stack>/`. Los archivos eliminados del repositorio también se eliminan en el servidor. El estado de ejecución no debe vivir en esas rutas salvo si se excluye explícitamente; las exclusiones incluyen `.env`, `data/`, `logs/`, `postgres/`, `cache/`, `backup/`, `*.db`, `*.sqlite`, `*.log`, `*.key` y `*.pem`.

Ansible genera los `.env` de ejecución y no deben mantenerse manualmente en el servidor. Monitoring recibe `GRAFANA_URL` y `AUTHENTIK_URL` desde `homelab_domain`, de modo que cambiar el dominio actualiza sus URLs en la siguiente reconciliación.

---

# Proxy inverso y HTTPS

Caddy proporciona el acceso público. OCI admite entrada TCP/22 (SSH), TCP/80 (HTTP) y TCP/443 (HTTPS). Los contenedores no deberían publicar directamente puertos de aplicación: Caddy los alcanza mediante la red `proxy` de Docker. Su configuración se genera desde `Caddyfile.j2`, y también puede enrutar servicios no gestionados por Ansible.

## Requisito de DNS

El DNS queda intencionadamente fuera de este repositorio: ni Terraform ni
Ansible crean registros DNS. Antes del primer despliegue de Caddy, configurar
en la zona de `homelab_domain` estos dos registros `A`, ambos apuntando a la IP
pública IPv4 reservada de OCI:

| Nombre | Destino | Propósito |
| --- | --- | --- |
| `@` | IPv4 pública reservada de OCI | Dominio raíz |
| `*` | IPv4 pública reservada de OCI | Todos los subdominios de servicios |

El comodín no cubre el dominio raíz, por lo que ambos registros son necesarios.
Caddy obtiene y renueva certificados TLS públicos para los hostnames declarados
en su configuración; el DNS debe resolver hacia el servidor y los puertos TCP
80 y 443 deben permanecer accesibles públicamente.

## Rutas de Caddy

`Caddyfile.j2` declara actualmente estas rutas. Una ruta puede existir aunque
su backend no esté gestionado o esté deshabilitado; en ese caso el hostname
resolverá correctamente, pero devolverá un error de proxy hasta que el backend
esté disponible.

| Hostname | Backend |
| --- | --- |
| `{{ homelab_domain }}` | `apache:80` |
| `www.{{ homelab_domain }}` | Redirección al dominio raíz |
| `n8n.{{ homelab_domain }}` | `n8n:5678` |
| `portainer.{{ homelab_domain }}` | `portainer:9000` |
| `status.{{ homelab_domain }}` | `uptime-kuma:3001` |
| `paperless.{{ homelab_domain }}` | `paperless:8000` |
| `pdf.{{ homelab_domain }}` | `stirling-pdf:8080` |
| `airflow.{{ homelab_domain }}` | `airflow-api-server:8080` |
| `grafana.{{ homelab_domain }}` | `grafana:3000` |
| `auth.{{ homelab_domain }}` | `authentik-server:9000` |

---

# Autenticación y dependencias

Authentik proporciona autenticación centralizada para Grafana y Portainer. Ansible administra sus proveedores y aplicaciones mediante Blueprints con valores del Vault, ubicados en `/opt/stacks/authentik/blueprints/`.

Los Blueprints contienen potencialmente contraseñas o secretos OAuth. El directorio es privado para el administrador de despliegue; el worker de Authentik recibe sólo acceso de lectura mediante ACL POSIX explícitas. Otros usuarios no tienen acceso.

```text
Portainer ────┐
              ├──► Authentik
Grafana ──────┘
```

Ansible rechaza habilitar `portainer` o `monitoring` mientras `authentik` esté deshabilitado, incluso en ejecuciones dirigidas.

---

# Comprobar cambios antes de aplicar

```bash
cd ansible

ansible-playbook \
  -i inventory/production.yml \
  playbooks/site.yml \
  --check \
  --diff \
  --ask-vault-pass
```

Un host convergido normalmente no muestra cambios. `no_log: true` evita que los secretos renderizados aparezcan en el diff; el modo check no simula perfectamente todas las acciones de Docker o de servicios externos.

Para infraestructura:

```bash
cd terraform/oci

terraform plan
```

---

# Validación, actualización y recuperación

Tras desplegar, comprobar:

```bash
docker ps
docker compose ls
findmnt /mnt/data
```

El flujo habitual para actualizar un stack es modificar la configuración, ejecutar `--check --diff`, reconciliar el stack afectado con `--tags`, verificarlo y, si hace falta, realizar una convergencia completa.

Las imágenes de los stacks habilitados deben fijarse a versiones explícitas; antes de actualizarlas, revisar la versión upstream, desplegar intencionadamente y verificar el resultado.

Para reconstruir la instancia, conservar el volumen OCI protegido, recrear la infraestructura con Terraform, generar los inventarios, ejecutar bootstrap y site, reutilizar el volumen y reconciliar los stacks. Los datos persistentes requieren además su propia estrategia de copias de seguridad.

---

# Límites del repositorio y gestión de secretos

Se versionan la configuración de Terraform y Ansible, el Vault cifrado, las definiciones Compose, plantillas, Blueprints, scripts y documentación. No se versionan `backend.hcl`, inventarios generados, variables ni estado local de Terraform, claves privadas SSH/OCI, Vault descifrado, `.env` reales, bases de datos, datos de aplicaciones, logs, cachés ni backups.

El flujo de secretos es:

```text
Ansible Vault cifrado → Ansible → .env y Blueprints → configuración de aplicación
```

Los secretos en texto plano existen en el host sólo cuando las aplicaciones los necesitan. La contraseña del Vault, las credenciales OCI y las claves privadas SSH deben conservarse por separado en un gestor de contraseñas u otra ubicación segura.

---

# Principios operativos

1. **La infraestructura y la configuración son reproducibles** con Terraform y Ansible.
2. **Los datos persistentes se separan del cómputo** en un volumen OCI dedicado.
3. **Las operaciones destructivas requieren autorización explícita**.
4. **Los secretos no se guardan en texto plano en Git**.
5. **Los stacks se reconcilian de forma independiente** mediante etiquetas de Ansible.
6. **Las dependencias se validan** antes de reconciliar.
7. **Los servicios públicos pasan por el proxy inverso** y los puertos de aplicación no se exponen normalmente de forma directa.
8. **Las versiones de contenedores se fijan** para despliegues reproducibles.
9. **La configuración manual debe minimizarse** y documentarse cuando sea necesaria.
