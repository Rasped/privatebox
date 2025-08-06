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
    skopeo \
    openssh-client || error_exit "Failed to install required packages"

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
    "host": "/var/lib/semaphore/database.boltdb"
  },
  "dialect": "bolt",
  "port": "3000",
  "interface": "",
  "tmp_path": "/tmp/semaphore",
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
  "oidc_providers": {},
  "password_login_disable": false,
  "non_admin_can_create_project": false
}
EOF

# Install Semaphore
log "Installing Semaphore..."
# Fix ownership for Semaphore data directory (UID 1001)
chown -R 1001:1001 /opt/semaphore/data
cat > /etc/containers/systemd/semaphore.container <<EOF
[Unit]
Description=Semaphore Container
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/semaphoreui/semaphore:latest
ContainerName=semaphore
Volume=/opt/semaphore/data:/var/lib/semaphore:Z
Volume=/opt/semaphore/config:/etc/semaphore:Z
PublishPort=3000:3000
Environment=SEMAPHORE_DB_DIALECT=bolt
Environment=SEMAPHORE_DB_PATH=/var/lib/semaphore/database.boltdb
Environment=SEMAPHORE_ADMIN=admin
Environment=SEMAPHORE_ADMIN_PASSWORD=${SERVICES_PASSWORD}
Environment=SEMAPHORE_ADMIN_NAME=Administrator
Environment=SEMAPHORE_ADMIN_EMAIL=admin@privatebox.local
Environment=SEMAPHORE_ACCESS_KEY_ENCRYPTION=$(head -c32 /dev/urandom | base64 | head -c32)
Environment=SEMAPHORE_CONFIG_PATH=/etc/semaphore/config.json
Environment=SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/
Environment=TZ=UTC
Exec=semaphore server --config=/etc/semaphore/config.json

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

# Start Portainer first
systemctl start portainer.service || error_exit "Failed to start Portainer"
systemctl enable portainer.service || log "Warning: Failed to enable Portainer for boot"

# Wait for Portainer to be ready
log "Waiting for Portainer to be ready..."
for i in {1..30}; do
    if curl -sf http://localhost:9000 > /dev/null 2>&1; then
        log "Portainer is ready"
        break
    fi
    sleep 5
done

# Start Semaphore service first to let it initialize database
log "Starting Semaphore service for initial database setup..."
systemctl start semaphore.service || error_exit "Failed to start Semaphore"
systemctl enable semaphore.service || log "Warning: Failed to enable Semaphore for boot"

# Wait for Semaphore to initialize database
log "Waiting for Semaphore to initialize..."
for i in {1..30}; do
    if curl -sf http://localhost:3000/api/ping > /dev/null 2>&1; then
        log "Semaphore is ready"
        break
    fi
    sleep 2
done

# Now create admin user using the stop/start pattern (matching v1 exactly)
log "Creating Semaphore admin user..."

# Ensure SERVICES_PASSWORD is set
if [[ -z "${SERVICES_PASSWORD}" ]]; then
    log "ERROR: SERVICES_PASSWORD is not set!"
    log "WARNING: Admin user creation will fail"
else
    log "DEBUG: SERVICES_PASSWORD is set (length: ${#SERVICES_PASSWORD})"
    
    # Stop service to modify database
    log "Stopping Semaphore to create admin user..."
    systemctl stop semaphore.service
    sleep 2
    
    # Create admin user using container (matching v1 pattern EXACTLY)
    log "Adding admin user to database..."
    if podman run --rm \
        -v /opt/semaphore/config:/etc/semaphore:Z \
        -v /opt/semaphore/data:/var/lib/semaphore:Z \
        docker.io/semaphoreui/semaphore:latest \
        semaphore user add \
        --admin \
        --login admin \
        --name Admin \
        --email admin@localhost \
        --password "${SERVICES_PASSWORD}" \
        --config /etc/semaphore/config.json >/dev/null 2>&1; then
        log "✓ Admin user created successfully"
    else
        log "WARNING: Admin user creation failed (may already exist)"
    fi
    
    # Restart service
    log "Restarting Semaphore..."
    systemctl start semaphore.service
    sleep 3
    
    # Wait for API to be ready again
    for i in {1..30}; do
        if curl -sf http://localhost:3000/api/ping > /dev/null 2>&1; then
            log "Semaphore API ready after restart"
            break
        fi
        sleep 2
    done
fi

# Configure Semaphore via API
log "Configuring Semaphore via API..."
if [[ -f /usr/local/lib/semaphore-api.sh ]]; then
    log "Loading Semaphore API library..."
    source /usr/local/lib/semaphore-api.sh
    
    # Export required variables for API library
    export PRIVATEBOX_GIT_URL="https://github.com/Rasped/privatebox.git"
    export SERVICES_PASSWORD  # Already in environment from config.env
    export ADMIN_PASSWORD     # Already in environment from config.env
    
    # Generate VM SSH key pair if not exists
    if [[ ! -f /root/.credentials/semaphore_vm_key ]]; then
        log "Generating VM SSH key pair..."
        generate_vm_ssh_key_pair
    fi
    
    # Run API configuration
    log "Creating default Semaphore projects and configuration..."
    if create_default_projects; then
        log "✓ Semaphore API configuration completed successfully"
        
        # Clean up sensitive SSH keys after upload
        if [[ -f /root/.credentials/proxmox_ssh_key ]]; then
            rm -f /root/.credentials/proxmox_ssh_key
            log "Removed Proxmox SSH key after upload to Semaphore"
        fi
        
        # Keep VM key for potential future use
        log "VM SSH key retained at /root/.credentials/semaphore_vm_key"
    else
        log "WARNING: Semaphore API configuration failed - manual setup may be required"
    fi
else
    log "WARNING: Semaphore API library not found - skipping API configuration"
fi

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