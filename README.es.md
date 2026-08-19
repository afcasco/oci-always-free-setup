[English](README.md) | [Español](README.es.md) | [Guía rápida](QUICKSTART.es.md)

# OCI Homelab

Mi homelab Docker en Oracle Cloud Infrastructure (OCI), guardado como código
para poder reconstruir el servidor sin perder los datos de aplicaciones en
`/mnt/data`.

- **Terraform** aprovisiona red, cómputo, IP pública reservada y almacenamiento persistente.
- **Ansible** prepara el host y reconcilia los stacks Docker Compose gestionados.
- **Caddy** proporciona HTTPS y proxy inverso.
- **Authentik** proporciona autenticación centralizada para Grafana, Portainer,
  Uptime Kuma, Stirling PDF y Paperless.

## Arquitectura

```text
Internet (80/443) → Caddy → red proxy de Docker
                              ├── Authentik ── SSO/OIDC ── Grafana
                              │                         └── Portainer
                              ├── Uptime Kuma
                              └── otros servicios

Estado persistente: /mnt/data/docker → volumen OCI
```

Ciclo de despliegue:

```text
Bootstrap estado Terraform → Terraform OCI → inventario bootstrap
→ Ansible bootstrap → inventario temporal de producción → Ansible site
→ WireGuard → inventario de producción
```

## Estructura del repositorio

```text
ansible/     inventarios, playbooks, roles y requirements
stacks/      definiciones Docker Compose
terraform/   bootstrap de estado e infraestructura OCI
scripts/     generación de inventarios y backend
```

El estado de ejecución queda fuera del árbol de Git.

# Lo que necesitas

El equipo de despliegue necesita Terraform >= 1.12, Ansible, Python 3 con PyYAML, rsync, credenciales API de OCI y una clave SSH. Las credenciales OCI se esperan en `~/.oci/config`.

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

# Antes de empezar

## Terraform

Crear estos archivos locales (intencionadamente no versionados):

```text
terraform/bootstrap-state/terraform.tfvars
terraform/oci/terraform.tfvars
```

El bootstrap requiere `tenancy_ocid` y `region` y puede definir `state_bucket_name`.

La configuración OCI requiere como mínimo `tenancy_ocid`, `region`, `compartment_name`, `compartment_description`, `instance_name`, `instance_image_ocid` y `ssh_public_key`. Revisar los valores por defecto de red, forma de instancia y volumen.

```hcl
tenancy_ocid            = "ocid1.tenancy.oc1..example"
region                  = "eu-madrid-1"
compartment_name        = "homelab"
compartment_description = "Personal homelab"
instance_name           = "homelab"
instance_image_ocid     = "ocid1.image.oc1.eu-madrid-1.example"
instance_private_ip     = "10.0.0.137"
ssh_public_key          = "ssh-ed25519 AAAA... oci-homelab"
bootstrap_ssh_cidr      = "203.0.113.10/32"
```

`bootstrap_ssh_cidr` es tu IP pública actual con `/32`. Permite SSH público
temporalmente para que el primer playbook de producción pueda instalar
WireGuard. No subir archivos `terraform.tfvars` reales a Git y eliminar este
valor después de pasar a WireGuard.

## Ansible

La configuración no secreta está en `ansible/inventory/group_vars/all/vars.yml`.
Antes de un despliegue nuevo, ajustar el dominio, datos del host y usuarios,
clave SSH pública, etiqueta del disco y los stacks que quieres habilitar.

Los secretos de producción están cifrados en `ansible/inventory/group_vars/production/vault.yml`.

```bash
cd ansible
ansible-vault edit inventory/group_vars/production/vault.yml
```

Debe contener valores no vacíos para estas variables:

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

El nombre de la variable del peer de WireGuard debe coincidir con el peer de
`vars.yml`. Usar valores aleatorios robustos. Las tareas que renderizan secretos usan
`no_log: true`; las nuevas plantillas deben hacer lo mismo.

# Despliegue desde cero

## 1. Bootstrap del estado de Terraform

Configurar `terraform/bootstrap-state/terraform.tfvars`:

```bash
cd terraform/bootstrap-state
terraform init
terraform plan
terraform apply
cd ../..
```

Generar el backend principal:

```bash
./scripts/generate-terraform-backend.sh
```

Esto crea el archivo ignorado `terraform/oci/backend.hcl`.

## 2. Aprovisionar OCI

Configurar `terraform/oci/terraform.tfvars`:

```bash
cd terraform/oci
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
cd ../..
```

Terraform crea el compartment, red, instancia, IP pública reservada y volumen persistente.

## 3. Bootstrap del servidor

```bash
./scripts/generate-ansible-inventory.sh bootstrap

cd ansible
ansible-playbook   -i inventory/bootstrap.yml   playbooks/bootstrap.yml
```

Esto crea el administrador permanente y configura SSH.

## 4. Primer despliegue de producción

```bash
cd ..
./scripts/generate-ansible-inventory.sh production-bootstrap
cd ansible
```

Para la primera ejecución sobre un volumen realmente vacío:

```bash
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   -e data_disk_initialize=true   --ask-vault-pass
```

Las ejecuciones posteriores normalmente deben omitir ese indicador:

```bash
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   --ask-vault-pass
```

`data_disk_initialize=true` autoriza explícitamente particionar y formatear un disco vacío. Ansible rechaza inicializar discos con particiones o firmas existentes.

Esta primera ejecución sigue usando SSH público e instala el servidor WireGuard.

## 5. Pasar a la gestión solo por WireGuard

Configurar el cliente WireGuard que corresponde a una entrada de
`wireguard_peers` y comprobar que puede llegar a `10.66.66.1`. El cliente usa
su propia clave privada, la clave pública del servidor, la IPv4 pública
reservada como endpoint en el puerto UDP `51820` y `10.66.66.0/24` como rango
de IPs permitidas.

Cuando SSH por VPN funcione, generar el inventario normal; todas las siguientes
ejecuciones de Ansible usan la dirección de WireGuard:

```bash
cd ..
./scripts/generate-ansible-inventory.sh production
```

Por último, eliminar `bootstrap_ssh_cidr` de
`terraform/oci/terraform.tfvars` y ejecutar `terraform apply` para cerrar el
SSH público.

# Recursos persistentes y almacenamiento

El estado de las aplicaciones vive principalmente en `/mnt/data/docker/`, sobre un volumen OCI independiente.

Terraform protege el volumen de datos y la IP pública reservada mediante `prevent_destroy`. El cómputo es reemplazable; los datos persistentes no.

El volumen requiere igualmente una estrategia de copias de seguridad independiente.

# Gestión de stacks Docker

Las definiciones Compose viven en `stacks/`.

`managed_stacks` define qué stacks pertenecen a Ansible. `enabled_stacks` define cuáles deben estar ejecutándose. Los stacks gestionados pero deshabilitados se detienen y eliminan; los no gestionados no se modifican.

Los stacks se pueden reconciliar individualmente:

```bash
cd ansible
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   --tags authentik   --ask-vault-pass
```

Las etiquetas actuales incluyen `caddy`, `authentik`, `monitoring`, `portainer`,
`uptime-kuma`, `n8n`, `stirling-pdf` y `paperless`.

La configuración se sincroniza desde `stacks/<stack>/` hacia `/opt/stacks/<stack>/`. El estado de ejecución debe quedar fuera de las rutas sincronizadas salvo exclusión explícita. Los `.env` se generan mediante Ansible y no deben mantenerse manualmente.

Las imágenes de los stacks habilitados deben fijarse a versiones explícitas.

# Proxy inverso, DNS y HTTPS

Caddy es el punto de entrada público. OCI expone TCP/22, TCP/80 y TCP/443; los contenedores de aplicaciones normalmente no deben publicar directamente sus puertos.

Antes de desplegar Caddy, configurar ambos registros DNS de `homelab_domain` apuntando a la IPv4 pública reservada de OCI:

| Nombre | Destino |
| --- | --- |
| `@` | IPv4 pública reservada OCI |
| `*` | IPv4 pública reservada OCI |

El comodín no cubre el dominio raíz. Caddy obtiene y renueva los certificados TLS públicos.

`Caddyfile.j2` declara actualmente estas rutas:

| Hostname | Backend |
| --- | --- |
| `{{ homelab_domain }}` | `apache:80` |
| `www.{{ homelab_domain }}` | Redirección al dominio raíz |
| `n8n.{{ homelab_domain }}` | `n8n:5678` (si `n8n` está habilitado) |
| `portainer.{{ homelab_domain }}` | `portainer:9000` (si `portainer` está habilitado) |
| `status.{{ homelab_domain }}` | `uptime-kuma:3001` (si `uptime-kuma` está habilitado) |
| `paperless.{{ homelab_domain }}` | `paperless:8000` (si `paperless` está habilitado) |
| `pdf.{{ homelab_domain }}` | `stirling-pdf:8080` (si `stirling-pdf` está habilitado) |
| `airflow.{{ homelab_domain }}` | `airflow-api-server:8080` |
| `grafana.{{ homelab_domain }}` | `grafana:3000` (si `monitoring` está habilitado) |
| `auth.{{ homelab_domain }}` | `authentik-server:9000` (si `authentik` está habilitado) |

Las rutas del dominio raíz y de Airflow apuntan a backends no gestionados.
Desplegar Apache y Airflow por separado, o eliminar esas rutas antes de un
despliegue desde cero; en caso contrario devolverán un error de proxy.

# Autenticación

Authentik proporciona autenticación centralizada para Grafana, Portainer,
Uptime Kuma, Stirling PDF y Paperless. Sus proveedores y aplicaciones se
gestionan mediante Blueprints renderizados por Ansible con secretos procedentes
del Vault.

Los Blueprints renderizados viven en:

```text
/opt/stacks/authentik/blueprints/
```

Como pueden contener contraseñas o secretos OAuth, el directorio es privado para el administrador de despliegue. El worker de Authentik recibe únicamente permisos de lectura/travesía mediante ACL POSIX explícitas; otros usuarios no tienen acceso.

```text
usuario despliegue    rwx directorio / rw archivos
worker Authentik      r-x directorio / r-- archivos
otros usuarios        sin acceso
```

Ansible rechaza configuraciones que habiliten Portainer, Monitoring, Uptime
Kuma, Stirling PDF o Paperless mientras Authentik esté deshabilitado.

# Validación y operación normal

Previsualizar cambios importantes de Ansible:

```bash
cd ansible
ansible-playbook   -i inventory/production.yml   playbooks/site.yml   --check   --diff   --ask-vault-pass
```

Una segunda ejecución sobre un host convergido debería mostrar normalmente `changed=0` y `failed=0`.

Comprobaciones básicas:

```bash
docker ps
docker compose ls
findmnt /mnt/data
```

Para cambios de infraestructura:

```bash
cd terraform/oci
terraform plan
```

El flujo normal para actualizar un stack es modificar el repositorio, previsualizar, reconciliar la etiqueta afectada, verificar el servicio y hacer commit.

# Reconstrucción de la instancia

La instancia se puede recrear conservando el volumen OCI y la IP reservada protegidos:

1. Recrear el cómputo con Terraform.
2. Definir `bootstrap_ssh_cidr`, generar el inventario bootstrap y ejecutar `bootstrap.yml`.
3. Usar el inventario `production-bootstrap` para ejecutar `site.yml` y luego pasar a WireGuard.
4. Eliminar `bootstrap_ssh_cidr`, reutilizar el volumen persistente y reconciliar los stacks.

La recuperación de aplicaciones sigue dependiendo de la integridad y las copias de seguridad de sus datos persistentes.

# Límites del repositorio y secretos

Se versionan la configuración Terraform/Ansible, el Vault cifrado, definiciones Compose, plantillas, Blueprints de Authentik, scripts y documentación.

No se versionan `backend.hcl` generado, inventarios generados, `terraform.tfvars` reales, estado local de Terraform, claves privadas SSH/OCI, Vault descifrado, `.env` de ejecución, bases de datos/datos de aplicaciones, logs, cachés ni backups.

Flujo de secretos:

```text
Ansible Vault cifrado → Ansible → .env de ejecución / Blueprints Authentik
```

La contraseña del Vault, credenciales OCI y claves privadas SSH deben respaldarse por separado; no son recuperables desde este repositorio.
