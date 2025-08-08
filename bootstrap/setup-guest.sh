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

#==============================#
# System packages
#==============================#
log "Updating package lists..."
apt-get update || error_exit "Failed to update package lists"

log "Installing required packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl wget ca-certificates gnupg lsb-release jq git \
  podman buildah skopeo openssh-client || error_exit "Failed to install required packages"

#==============================#
# Podman socket & auto-update
#==============================#
log "Enabling Podman socket (Docker API compatibility)..."
systemctl enable --now podman.socket || error_exit "Failed to enable Podman socket"

log "Enabling podman-auto-update timer..."
systemctl enable --now podman-auto-update.timer || error_exit "Failed to enable podman-auto-update.timer"

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
# Custom Semaphore image (with proxmoxer + community.general)
#==============================#
log "Writing Semaphore Containerfile..."
cat > /opt/semaphore/Containerfile <<'EOF'
FROM docker.io/semaphoreui/semaphore:latest
# Switch to root to install packages and create directories
USER root
# Add proxmoxer + requests for PVE modules, and community.general collection system-wide
RUN pip3 install --no-cache-dir proxmoxer requests \
 && mkdir -p /usr/share/ansible/collections \
 && ansible-galaxy collection install -p /usr/share/ansible/collections community.general
# Switch back to semaphore user
USER semaphore
EOF

log "Building Semaphore image (localhost/semaphore-proxmox:latest)..."
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
PublishPort=9000:9000
PublishPort=8000:8000
Environment=TZ=UTC
Label=io.containers.autoupdate=image

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
  "port": "3000",
  "interface": "",
  "tmp_path": "/tmp/semaphore",
  "cookie_hash": "${COOKIE_HASH}",
  "cookie_encryption": "${COOKIE_ENCRYPTION}",
  "access_key_encryption": "${ACCESS_KEY_ENCRYPTION}",
  "web": { "listen": "0.0.0.0:3000" },
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
PublishPort=3000:3000
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
Label=io.containers.autoupdate=image

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
systemctl enable --now portainer.service || error_exit "Failed to start/enable Portainer"

log "Waiting for Portainer to be ready..."
for i in {1..30}; do
  if curl -sf http://localhost:9000/api/status >/dev/null 2>&1; then
    log "Portainer is ready"
    break
  fi
  sleep 5
done

log "Starting Semaphore..."
systemctl enable --now semaphore.service || error_exit "Failed to start/enable Semaphore"

log "Waiting for Semaphore API to be ready..."
for i in {1..60}; do
  if curl -sf http://localhost:3000/api/ping >/dev/null 2>&1; then
    log "Semaphore is ready"
    break
  fi
  sleep 2
done

#==============================#
# Optional: API bootstrap (if library is present)
#==============================#
log "Configuring Semaphore via API (if library present)..."
if [[ -f /usr/local/lib/semaphore-api.sh ]]; then
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
    log "WARNING: Semaphore API configuration failed - manual setup may be required"
  fi
else
  log "Semaphore API library not found - skipping API configuration"
fi

#==============================#
# Success marker & summary
#==============================#
echo "SUCCESS" > /etc/privatebox-install-complete
log "Guest configuration complete!"

cat <<EOF

========================================
PrivateBox Guest Configuration Complete
========================================
Portainer: http://$(hostname -I | awk '{print $1}'):9000
Semaphore: http://$(hostname -I | awk '{print $1}'):3000

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
