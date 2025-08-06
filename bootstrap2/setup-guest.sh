#!/bin/bash
# Phase 3: Guest Configuration Script
# Runs inside VM via cloud-init

set -euo pipefail

# Source config
if [[ -f /etc/privatebox/config.env ]]; then
    source /etc/privatebox/config.env
else
    echo "ERROR: Config file not found at /etc/privatebox/config.env" >&2
    exit 1
fi

# Logging setup
LOG_FILE="/var/log/privatebox-guest-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    echo "ERROR" > /etc/privatebox-install-complete
    exit 1
}

# Update system
log "Starting guest configuration..."
log "Updating package lists..."
apt-get update || error_exit "Failed to update package lists"

# Install required packages
log "Installing required packages..."
apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    git \
    podman \
    buildah \
    skopeo || error_exit "Failed to install required packages"

# Podman is installed from Debian repos above
log "Podman installed from Debian repositories"

# Enable Podman socket for Docker API compatibility
log "Enabling Podman socket..."
systemctl enable --now podman.socket || error_exit "Failed to enable Podman socket"
log "Podman socket enabled successfully"

# Create directories
log "Creating service directories..."
mkdir -p /opt/portainer/data
mkdir -p /opt/semaphore/data
mkdir -p /opt/semaphore/config
mkdir -p /etc/containers/systemd

# Create snippets volume for Semaphore integration
log "Creating snippets volume..."
podman volume create snippets || log "Snippets volume already exists"

# Install Portainer
log "Installing Portainer..."
cat > /etc/containers/systemd/portainer.container <<EOF
[Unit]
Description=Portainer Container
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/portainer/portainer-ce:latest
ContainerName=portainer
Volume=/run/podman/podman.sock:/var/run/docker.sock:z
Volume=/opt/portainer/data:/data:z
Volume=snippets:/snippets:z
PublishPort=9000:9000
PublishPort=8000:8000
Environment=TZ=UTC

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target
EOF

# Create Semaphore config
log "Creating Semaphore configuration..."
SEMAPHORE_CONFIG="/opt/semaphore/config/config.json"
cat > "$SEMAPHORE_CONFIG" <<EOF
{
  "bolt": {
    "host": "/opt/semaphore/data/database.boltdb"
  },
  "web": {
    "listen": "0.0.0.0:3000"
  },
  "email": {
    "alert": false
  },
  "telegram": {
    "alert": false
  },
  "ldap": {
    "enable": false
  },
  "oidc_providers": [],
  "password_login_disable": false,
  "non_admin_can_create_project": false
}
EOF

# Install Semaphore
log "Installing Semaphore..."
cat > /etc/containers/systemd/semaphore.container <<EOF
[Unit]
Description=Semaphore Container
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/semaphoreui/semaphore:latest
ContainerName=semaphore
Volume=/opt/semaphore/data:/var/lib/semaphore:z
Volume=/opt/semaphore/config:/etc/semaphore:z
PublishPort=3000:3000
Environment=SEMAPHORE_DB_DIALECT=bolt
Environment=SEMAPHORE_DB=bolt:///var/lib/semaphore/database.boltdb
Environment=SEMAPHORE_ADMIN=admin
Environment=SEMAPHORE_ADMIN_PASSWORD=${SERVICES_PASSWORD}
Environment=SEMAPHORE_ADMIN_NAME=Administrator
Environment=SEMAPHORE_ADMIN_EMAIL=admin@privatebox.local
Environment=SEMAPHORE_ACCESS_KEY_ENCRYPTION=$(head -c32 /dev/urandom | base64 | head -c32)

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target
EOF

# Reload systemd and start services
log "Starting services..."
systemctl daemon-reload

# Enable podman auto-update timer
systemctl enable --now podman-auto-update.timer

# Start services (triggers Quadlet generation)
systemctl start portainer.service || error_exit "Failed to start Portainer"
systemctl start semaphore.service || error_exit "Failed to start Semaphore"

# Enable services for boot
systemctl enable portainer.service || log "Warning: Failed to enable Portainer for boot"
systemctl enable semaphore.service || log "Warning: Failed to enable Semaphore for boot"

# Wait for services to be ready
log "Waiting for services to be ready..."
for i in {1..30}; do
    if curl -sf http://localhost:9000 > /dev/null 2>&1; then
        log "Portainer is ready"
        break
    fi
    sleep 5
done

for i in {1..30}; do
    if curl -sf http://localhost:3000 > /dev/null 2>&1; then
        log "Semaphore is ready"
        break
    fi
    sleep 5
done

# Create success marker
log "Guest configuration complete!"
echo "SUCCESS" > /etc/privatebox-install-complete

# Output summary
cat <<EOF

========================================
PrivateBox Guest Configuration Complete
========================================
Portainer: http://$(hostname -I | awk '{print $1}'):9000
Semaphore: http://$(hostname -I | awk '{print $1}'):3000

Admin credentials saved in /etc/privatebox/config.env
========================================

EOF