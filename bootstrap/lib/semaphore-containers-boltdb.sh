#!/bin/bash
# Semaphore container management library - BoltDB version

# Create directories for persistent storage
setup_storage_directories() {
    log_info "Creating directories for persistent storage..."
    mkdir -p /opt/semaphore/data
    mkdir -p /opt/semaphore/config
    chmod -R 755 /opt/semaphore
    
    # Create directory for Ansible projects
    mkdir -p /opt/semaphore/projects
    
    # Create config.json to bypass setup wizard
    create_semaphore_config
    
    log_info "Storage directories created."
}

# Create Semaphore config.json file
create_semaphore_config() {
    log_info "Creating Semaphore config.json..."
    
    cat > /opt/semaphore/config/config.json <<EOF
{
  "bolt": {
    "host": "/var/lib/semaphore"
  },
  "dialect": "bolt",
  "port": "3000",
  "interface": "",
  "tmp_path": "/tmp/semaphore",
  "cookie_hash": "$(head -c16 /dev/urandom | base64)",
  "cookie_encryption": "$(head -c16 /dev/urandom | base64)",
  "access_key_encryption": "$SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY",
  "email_sender": "",
  "email_host": "",
  "email_port": "",
  "web_host": "",
  "ldap_binddn": "",
  "ldap_bindpassword": "",
  "ldap_server": "",
  "ldap_searchdn": "",
  "ldap_searchfilter": "",
  "ldap_mappings": {
    "dn": "",
    "mail": "",
    "uid": "",
    "cn": ""
  },
  "telegram_chat": "",
  "telegram_token": "",
  "slack_url": "",
  "rocketchat_url": "",
  "microsoft_teams_url": "",
  "max_parallel_tasks": 0,
  "email_secure": false,
  "email_alert": false,
  "telegram_alert": false,
  "slack_alert": false,
  "rocketchat_alert": false,
  "microsoft_teams_alert": false,
  "ldap_enable": false,
  "ldap_needtls": false,
  "ssh_config_path": "/etc/semaphore",
  "demo_mode": false
}
EOF
    
    chmod 644 /opt/semaphore/config/config.json
    log_info "Semaphore config.json created"
}

# Check and remove manually created containers
check_and_remove_manual_containers() {
    log_info "Checking for manually created containers..."
    
    # Check for manually created semaphore container
    if podman container exists semaphore; then
        log_info "Stopping and removing manually created semaphore container..."
        podman stop semaphore 2>/dev/null || true
        podman rm semaphore 2>/dev/null || true
    fi
    
    # Remove old MySQL-based containers if they exist
    if podman container exists semaphore-db; then
        log_info "Stopping and removing old semaphore-db container..."
        podman stop semaphore-db 2>/dev/null || true
        podman rm semaphore-db 2>/dev/null || true
    fi
    
    if podman container exists semaphore-ui; then
        log_info "Stopping and removing old semaphore-ui container..."
        podman stop semaphore-ui 2>/dev/null || true
        podman rm semaphore-ui 2>/dev/null || true
    fi
    
    # Also check for networks that might interfere
    if podman network exists semaphore; then
        log_info "Removing manually created semaphore network..."
        podman network rm semaphore 2>/dev/null || true
    fi
}

# Setup container pod and containers
setup_pod_and_containers() {
    log_info "Setting up Semaphore container with BoltDB..."
    
    # Check and remove any manually created containers
    check_and_remove_manual_containers
    
    # Create Quadlet files
    create_quadlet_files
    
    # Reload systemd to recognize new units
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload
    
    # Start the semaphore service
    log_info "Starting semaphore service..."
    if ! systemctl start semaphore.service; then
        log_error "Failed to start semaphore.service"
        systemctl status semaphore.service --no-pager
        return 1
    fi
    
    log_info "Semaphore service started successfully"
    return 0
}

# Wait for services to be ready and responsive
wait_for_services_ready() {
    log_info "Waiting for Semaphore API to be ready..."
    
    local api_ready=false
    for i in {1..60}; do
        if curl -sSf http://localhost:3000/api/ping >/dev/null 2>&1; then
            api_ready=true
            log_info "Semaphore API is ready!"
            break
        fi
        sleep 2
    done
    
    if [ "$api_ready" != "true" ]; then
        log_error "Semaphore API failed to become ready"
        systemctl status semaphore.service --no-pager
        podman logs semaphore | tail -50
        return 1
    fi
    
    return 0
}

# Display setup completion message
display_setup_completion_message() {
    log_info "🚀 Semaphore UI (BoltDB) setup completed successfully!"
    log_info ""
    log_info "Access Information:"
    log_info "  Web UI: http://localhost:3000"
    log_info "  Username: admin"
    log_info "  Password: $SEMAPHORE_ADMIN_PASSWORD"
    log_info ""
    log_info "Database: BoltDB (embedded)"
    log_info "Data Location: /opt/semaphore/data"
    log_info ""
    log_info "Service Management:"
    log_info "  Status: systemctl status semaphore"
    log_info "  Logs: podman logs semaphore"
    log_info "  Restart: systemctl restart semaphore"
}

# Clean up function for systemd units
cleanup_systemd_units() {
    log_info "Cleaning up systemd units..."
    
    # Stop and disable old services if they exist
    for service in semaphore-network semaphore-db semaphore-ui; do
        if systemctl is-enabled $service.service &>/dev/null; then
            systemctl disable $service.service &>/dev/null || true
            systemctl stop $service.service &>/dev/null || true
        fi
    done
    
    # Also check with container- prefix (systemd might generate these)
    for service in container-semaphore-db container-semaphore-ui; do
        if systemctl is-enabled $service.service &>/dev/null; then
            systemctl disable $service.service &>/dev/null || true
            systemctl stop $service.service &>/dev/null || true
        fi
    done
    
    # Remove old unit files
    rm -f /etc/systemd/system/pod-semaphore-pod.service
    rm -f /etc/systemd/system/container-semaphore-db.service
    rm -f /etc/systemd/system/container-semaphore-ui.service
    rm -f /etc/containers/systemd/semaphore-db.container
    rm -f /etc/containers/systemd/semaphore-ui.container
    rm -f /etc/containers/systemd/semaphore.network
}

# Create Quadlet configuration files
create_quadlet_files() {
    log_info "Creating Semaphore Quadlet file..."
    mkdir -p /etc/containers/systemd
    
    create_ui_quadlet_file
    
    log_info "Semaphore Quadlet file created."
}

# Create Semaphore container Quadlet file
create_ui_quadlet_file() {
    # Create Semaphore container Quadlet file
    cat > /etc/containers/systemd/semaphore.container <<EOF
[Unit]
Description=Semaphore UI with BoltDB
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/opt/semaphore/data /opt/semaphore/config

[Container]
ContainerName=semaphore
Image=docker.io/semaphoreui/semaphore:latest
Environment=SEMAPHORE_DB_DIALECT=bolt
Environment=SEMAPHORE_DB_PATH=/var/lib/semaphore
Environment=SEMAPHORE_ADMIN_PASSWORD="$SEMAPHORE_ADMIN_PASSWORD"
Environment=SEMAPHORE_ADMIN_NAME=admin
Environment=SEMAPHORE_ADMIN_EMAIL=admin@localhost
Environment=SEMAPHORE_ADMIN=admin
Environment=SEMAPHORE_ACCESS_KEY_ENCRYPTION="$SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY"
Environment=SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/
Environment=TZ=UTC
Environment=SEMAPHORE_APPS='{"python":{"active":true,"priority":500}}'
Volume=/opt/semaphore/data:/var/lib/semaphore:Z
Volume=/opt/semaphore/config:/etc/semaphore:Z
PublishPort=3000:3000

[Service]
Restart=always
TimeoutStartSec=90s

[Install]
WantedBy=multi-user.target default.target
EOF
}

# Convenient function to check all services status
check_services_status() {
    log_info "Checking Semaphore service status..."
    
    echo "=== Systemd Service Status ==="
    systemctl status semaphore.service --no-pager -l || log_info "Failed to get status for semaphore.service"
    
    echo -e "\n=== Container Status ==="
    podman ps -a --filter name=semaphore --format "table {{.Names}} {{.Status}} {{.Created}}"
    
    echo -e "\n=== Port Status ==="
    ss -tlnp | grep :3000 || log_info "Port 3000 not found in listening state"
    
    echo -e "\n=== Container Logs (last 20 lines) ==="
    podman logs semaphore --tail 20 2>&1 || log_info "Failed to get container logs"
}

# Function to enable services at boot
enable_services_at_boot() {
    log_info "Enabling Semaphore service at boot..."
    
    if systemctl enable semaphore.service; then
        log_success "Semaphore service enabled for automatic start at boot"
    else
        log_error "Failed to enable Semaphore service at boot"
        return 1
    fi
    
    return 0
}

# Main function to stop services
stop_services() {
    log_info "Stopping Semaphore service..."
    
    systemctl stop semaphore.service || log_warn "Failed to stop semaphore.service"
    
    # Also stop any containers that might be running
    podman stop semaphore 2>/dev/null || true
    
    log_info "Semaphore service stopped."
}

# Function to restart services
restart_services() {
    log_info "Restarting Semaphore service..."
    
    systemctl restart semaphore.service || {
        log_error "Failed to restart semaphore.service"
        return 1
    }
    
    log_success "Semaphore service restarted successfully"
    return 0
}

# Function to remove all Semaphore containers and data
remove_all() {
    log_warn "Removing all Semaphore containers and data..."
    
    # Stop services
    stop_services
    
    # Disable services
    systemctl disable semaphore.service 2>/dev/null || true
    
    # Remove containers
    podman rm -f semaphore 2>/dev/null || true
    
    # Remove Quadlet files
    rm -f /etc/containers/systemd/semaphore.container
    
    # Reload systemd
    systemctl daemon-reload
    
    # Optionally remove data (commented out for safety)
    # rm -rf /opt/semaphore
    
    log_info "Semaphore removal completed."
}