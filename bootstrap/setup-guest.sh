#!/bin/bash
# Phase 3: Guest Configuration Script
# Runs inside VM via cloud-init

set -euo pipefail

#==============================#
# Bootstrap & Logging
#==============================#
if [[ -f /etc/privatebox/config.env ]]; then
  # expected to define at least: SERVICES_PASSWORD (for Semaphore admin)
  # optionally ADMIN_PASSWORD for your own scripts
  source /etc/privatebox/config.env
else
  echo "ERROR: Config file not found at /etc/privatebox/config.env" >&2
  exit 1
fi

LOG_FILE="/var/log/privatebox-guest-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error_exit() { log "ERROR: $*"; echo "ERROR" > /etc/privatebox-install-complete; exit 1; }

if [[ -z "${SERVICES_PASSWORD:-}" ]]; then
  error_exit "SERVICES_PASSWORD is not set in /etc/privatebox/config.env"
fi

log "Starting guest configuration..."
echo "PROGRESS:Starting guest configuration" >> /etc/privatebox-install-complete

#==============================#
# System packages
#==============================#
log "Updating package lists..."
echo "PROGRESS:Updating system packages" >> /etc/privatebox-install-complete
apt-get update || error_exit "Failed to update package lists"

log "Upgrading system packages to latest versions..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || error_exit "Failed to upgrade system packages"

log "Installing required packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl wget ca-certificates gnupg lsb-release jq git \
  podman buildah skopeo openssh-client || error_exit "Failed to install required packages"

#==============================#
# Podman socket & auto-update
#==============================#
log "Enabling Podman socket (Docker API compatibility)..."
systemctl enable --now podman.socket || error_exit "Failed to enable Podman socket"

# Automatic container updates disabled - manual updates only via Semaphore
log "Container auto-updates disabled - use Semaphore for manual updates"

#==============================#
# Directories & volumes
#==============================#
log "Creating directories..."
mkdir -p /opt/portainer/data
mkdir -p /opt/semaphore/{data,config,projects,ansible}
mkdir -p /etc/containers/systemd
mkdir -p /usr/local/lib
mkdir -p /root/.credentials

# Semaphore container runs as uid 1001
chown -R 1001:1001 /opt/semaphore

log "Creating Portainer snippets volume..."
podman volume create snippets >/dev/null 2>&1 || true

#==============================#
# Generate HTTPS certificate
#==============================#
log "Generating self-signed HTTPS certificate..."
CERT_DIR="/etc/privatebox/certs"
mkdir -p "$CERT_DIR"

openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout "$CERT_DIR/privatebox.key" \
  -out "$CERT_DIR/privatebox.crt" \
  -subj "/CN=PrivateBox Management/O=SubRosa ApS/C=DK" \
  -addext "subjectAltName=IP:10.10.20.10,DNS:privatebox.local,DNS:*.privatebox.local" \
  2>/dev/null || error_exit "Failed to generate certificate"

chmod 600 "$CERT_DIR/privatebox.key"
chmod 644 "$CERT_DIR/privatebox.crt"

log "✓ HTTPS certificate generated (valid 10 years)"

#==============================#
# Custom Semaphore image (with proxmoxer)
#==============================#
log "Writing Semaphore Containerfile..."
cat > /opt/semaphore/Containerfile <<'EOF'
FROM docker.io/semaphoreui/semaphore:latest
# Switch to root to install packages
USER root
# Add proxmoxer + requests for PVE modules
RUN pip3 install --no-cache-dir proxmoxer requests
# Switch back to semaphore user
USER semaphore
EOF

log "Building Semaphore image (localhost/semaphore-proxmox:latest)..."
echo "PROGRESS:Building custom Semaphore image" >> /etc/privatebox-install-complete
podman build -t localhost/semaphore-proxmox:latest /opt/semaphore || error_exit "Failed to build Semaphore image"

#==============================#
# Portainer quadlet
#==============================#
log "Writing Portainer quadlet..."
cat > /etc/containers/systemd/portainer.container <<'EOF'
[Unit]
Description=Portainer Container
Wants=network-online.target podman.socket
After=network-online.target podman.socket

[Container]
Image=docker.io/portainer/portainer-ce:latest
ContainerName=portainer
Volume=/run/podman/podman.sock:/var/run/docker.sock:z
Volume=/opt/portainer/data:/data:z
Volume=snippets:/snippets:z
Volume=/etc/privatebox/certs:/certs:ro
PublishPort=1443:9443
Environment=TZ=UTC
Exec=--ssl --sslcert /certs/privatebox.crt --sslkey /certs/privatebox.key
# Auto-update disabled - manual updates only

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target
EOF

#==============================#
# Semaphore config.json
#==============================#
log "Creating Semaphore config.json..."
COOKIE_HASH=$(head -c32 /dev/urandom | base64 | head -c44)
COOKIE_ENCRYPTION=$(head -c32 /dev/urandom | base64 | head -c32)
ACCESS_KEY_ENCRYPTION=$(head -c32 /dev/urandom | base64 | head -c32)

SEMAPHORE_CONFIG="/opt/semaphore/config/config.json"
cat > "$SEMAPHORE_CONFIG" <<EOF
{
  "bolt": { "host": "/var/lib/semaphore/database.boltdb" },
  "dialect": "bolt",
  "port": ":3443",
  "interface": "",
  "tmp_path": "/tmp/semaphore",
  "cookie_hash": "${COOKIE_HASH}",
  "cookie_encryption": "${COOKIE_ENCRYPTION}",
  "access_key_encryption": "${ACCESS_KEY_ENCRYPTION}",
  "tls": {
    "enabled": true,
    "cert_file": "/certs/privatebox.crt",
    "key_file": "/certs/privatebox.key"
  },
  "email": { "alert": false },
  "telegram": { "alert": false },
  "ldap": { "enable": false },
  "oidc_providers": {},
  "password_login_disable": false,
  "non_admin_can_create_project": false
}
EOF

#==============================#
# Semaphore quadlet (custom image)
#==============================#
log "Writing Semaphore quadlet..."
cat > /etc/containers/systemd/semaphore.container <<'EOF'
[Unit]
Description=Semaphore Container
Wants=network-online.target
After=network-online.target

[Container]
Image=localhost/semaphore-proxmox:latest
ContainerName=semaphore
# Persistent data/config
Volume=/opt/semaphore/data:/var/lib/semaphore:Z
Volume=/opt/semaphore/config:/etc/semaphore:Z
# Persistent playbooks/projects and Ansible home (optional but handy)
Volume=/opt/semaphore/projects:/projects:Z
Volume=/opt/semaphore/ansible:/home/semaphore/.ansible:Z
# HTTPS certificate
Volume=/etc/privatebox/certs:/certs:ro
PublishPort=2443:3443
Environment=SEMAPHORE_DB_DIALECT=bolt
Environment=SEMAPHORE_DB_PATH=/var/lib/semaphore/database.boltdb
Environment=SEMAPHORE_ADMIN=admin
Environment=SEMAPHORE_ADMIN_PASSWORD=${SERVICES_PASSWORD}
Environment=SEMAPHORE_ADMIN_NAME=Administrator
Environment=SEMAPHORE_ADMIN_EMAIL=admin@privatebox.local
Environment=SEMAPHORE_CONFIG_PATH=/etc/semaphore/config.json
Environment=SEMAPHORE_PLAYBOOK_PATH=/projects
Environment=TZ=UTC
# If you have a trusted PVE CA bundle on the host, you can mount it and let proxmoxer validate TLS:
# Volume=/etc/ssl/certs/pve-ca.pem:/etc/ssl/certs/pve-ca.pem:ro,Z
# Environment=REQUESTS_CA_BUNDLE=/etc/ssl/certs/pve-ca.pem
Exec=semaphore server --config=/etc/semaphore/config.json
# Auto-update disabled - manual updates only

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target
EOF

#==============================#
# Nightly rebuild of custom image
# (podman-auto-update will pick up the new local image)
#==============================#
log "Writing nightly image rebuild units..."
cat > /etc/systemd/system/semaphore-image-update.service <<'EOF'
[Unit]
Description=Rebuild custom Semaphore image (with proxmoxer)

[Service]
Type=oneshot
WorkingDirectory=/opt/semaphore
ExecStart=/usr/bin/podman build -t localhost/semaphore-proxmox:latest .
EOF

cat > /etc/systemd/system/semaphore-image-update.timer <<'EOF'
[Unit]
Description=Nightly rebuild for custom Semaphore image

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

#==============================#
# Start services
#==============================#
log "Reloading systemd (quadlets + timers)..."
systemctl daemon-reload

log "Enabling nightly image rebuild timer..."
systemctl enable --now semaphore-image-update.timer

log "Starting Portainer..."
echo "PROGRESS:Starting Portainer service" >> /etc/privatebox-install-complete
# Quadlet services are auto-generated, just start them
systemctl start portainer.service || error_exit "Failed to start Portainer"

log "Waiting for Portainer to be ready..."
for i in {1..30}; do
  if curl -sfk https://localhost:1443/api/status >/dev/null 2>&1; then
    log "Portainer is ready"
    break
  fi
  sleep 5
done

log "Starting Semaphore..."
echo "PROGRESS:Starting Semaphore service" >> /etc/privatebox-install-complete
# Quadlet services are auto-generated, just start them
systemctl start semaphore.service || error_exit "Failed to start Semaphore"

log "Waiting for Semaphore API to be ready..."
for i in {1..60}; do
  if curl -sfk https://localhost:2443/api/ping >/dev/null 2>&1; then
    log "Semaphore is ready"
    break
  fi
  sleep 2
done

# Create admin user via stop/start dance (idempotent)
log "Creating Semaphore admin user..."
echo "PROGRESS:Creating Semaphore admin user" >> /etc/privatebox-install-complete
IMAGE="$(podman container inspect -f '{{.ImageName}}' semaphore 2>/dev/null || echo localhost/semaphore-proxmox:latest)"

systemctl stop semaphore.service
sleep 2  # Give it time to fully stop

podman run --rm \
  -v /opt/semaphore/config:/etc/semaphore:Z \
  -v /opt/semaphore/data:/var/lib/semaphore:Z \
  "$IMAGE" semaphore user add \
  --admin \
  --login admin \
  --name "Administrator" \
  --email admin@privatebox.local \
  --password "${SERVICES_PASSWORD}" \
  --config /etc/semaphore/config.json 2>&1 | grep -v "already exists" || true

systemctl start semaphore.service

# Wait for Semaphore to be ready again
log "Waiting for Semaphore to restart..."
for i in {1..30}; do
  if curl -sfk https://localhost:2443/api/ping >/dev/null 2>&1; then
    log "Semaphore restarted successfully"
    break
  fi
  sleep 2
done

#==============================#
# Optional: API bootstrap (if library is present)
#==============================#
log "Configuring Semaphore via API (if library present)..."
if [[ -f /usr/local/lib/semaphore-api.sh ]]; then
  echo "PROGRESS:Configuring Semaphore API" >> /etc/privatebox-install-complete
  log "Loading /usr/local/lib/semaphore-api.sh"
  # shellcheck disable=SC1091
  source /usr/local/lib/semaphore-api.sh

  export PRIVATEBOX_GIT_URL="https://github.com/Rasped/privatebox.git"
  export SERVICES_PASSWORD
  export ADMIN_PASSWORD="${ADMIN_PASSWORD:-$SERVICES_PASSWORD}"

  # Generate VM SSH key pair if not exists
  if [[ ! -f /root/.credentials/semaphore_vm_key ]]; then
    log "Generating VM SSH key pair..."
    generate_vm_ssh_key_pair || log "WARNING: generate_vm_ssh_key_pair failed"
  fi

  if create_default_projects; then
    log "✓ Semaphore API configuration completed successfully"
    if [[ -f /root/.credentials/proxmox_ssh_key ]]; then
      rm -f /root/.credentials/proxmox_ssh_key
      log "Removed Proxmox SSH key after upload to Semaphore"
    fi
    log "VM SSH key retained at /root/.credentials/semaphore_vm_key"
  else
    log "ERROR: Semaphore API configuration failed"
    log "Service deployment did not complete successfully"
    echo "ERROR" >> /etc/privatebox-install-complete
    exit 1
  fi
else
  log "Semaphore API library not found - skipping API configuration"
fi

#==============================#
# Success marker & summary
#==============================#
echo "SUCCESS" >> /etc/privatebox-install-complete
log "Guest configuration complete!"

cat <<EOF

========================================
PrivateBox Guest Configuration Complete
========================================
Portainer: https://$(hostname -I | awk '{print $1}'):1443
Semaphore: https://$(hostname -I | awk '{print $1}'):2443

Admin user: admin
Admin password: (from /etc/privatebox/config.env -> SERVICES_PASSWORD)

Data dirs:
  - /opt/portainer/data
  - /opt/semaphore/data, /opt/semaphore/config
Projects/playbooks:
  - /opt/semaphore/projects  (mounted at /projects in the container)

Auto-update:
  - podman-auto-update.timer enabled (container label-driven)
  - semaphore-image-update.timer enabled (nightly image rebuild)

Log file:
  - $LOG_FILE
========================================
EOF
