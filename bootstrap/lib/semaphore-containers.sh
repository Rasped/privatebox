#!/bin/bash
# Semaphore container management library

# Create directories for persistent storage
setup_storage_directories() {
    log_info "Creating directories for persistent storage..."
    mkdir -p /opt/semaphore/mysql/data
    mkdir -p /opt/semaphore/app/data
    mkdir -p /opt/semaphore/app/config
    chmod -R 777 /opt/semaphore
}

# Cleanup any manually created containers to avoid conflicts
cleanup_manual_containers() {
    log_info "Checking for manually created containers..."
    
    # Stop and remove containers if they exist
    if podman container exists semaphore-ui; then
        log_info "Stopping and removing manually created semaphore-ui container..."
        podman stop semaphore-ui 2>/dev/null || true
        podman rm semaphore-ui 2>/dev/null || true
    fi
    
    if podman container exists semaphore-db; then
        log_info "Stopping and removing manually created semaphore-db container..."
        podman stop semaphore-db 2>/dev/null || true
        podman rm semaphore-db 2>/dev/null || true
    fi
    
    # Remove the pod if it exists
    if podman pod exists semaphore-pod; then
        log_info "Removing manually created semaphore-pod..."
        podman pod rm -f semaphore-pod 2>/dev/null || true
    fi
}

# Setup pod and both containers using systemd
setup_pod_and_containers() {
    # Note: With Quadlet, we don't need to manually create pods
    # The network unit will handle this automatically
    log_info "Preparing for systemd-managed containers..."
    
    # Ensure any existing manual containers are stopped and removed
    cleanup_manual_containers
    
    # Create the quadlet files
    create_quadlet_files
    
    # Reload systemd to pick up new units
    systemctl daemon-reload
    
    # Start services via systemd
    start_systemd_services
}

# Initialize MySQL database (minimal version for systemd approach)
initialize_mysql_database() {
    log_info "Checking MySQL database initialization..."
    
    # With systemd/quadlet and environment variables, MySQL should auto-initialize
    # This function is kept for compatibility but does minimal work
    
    # Just verify the semaphore database exists
    if podman exec semaphore-db mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "USE semaphore" &>/dev/null; then
        log_info "MySQL database 'semaphore' is initialized"
        # Mark as initialized
        touch /opt/semaphore/.mysql_initialized
    else
        log_info "WARNING: MySQL database 'semaphore' not found, but should be auto-created by container"
    fi
}

# Start services using systemd
start_systemd_services() {
    log_info "Starting Semaphore services via systemd..."
    
    # Start the network first
    if ! systemctl start semaphore-network.service; then
        log_error "Failed to start semaphore-network.service"
        systemctl status semaphore-network.service --no-pager
        return 1
    fi
    
    # Start the database
    if ! systemctl start semaphore-db.service; then
        log_error "Failed to start semaphore-db.service"
        systemctl status semaphore-db.service --no-pager
        return 1
    fi
    
    # Wait for database to be ready
    log_info "Waiting for MySQL to be ready..."
    local db_ready=false
    for i in {1..30}; do
        if podman exec semaphore-db mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" &>/dev/null; then
            db_ready=true
            break
        fi
        if [ $((i % 6)) -eq 0 ]; then
            log_info "Still waiting for MySQL... ($((i * 5)) seconds elapsed)"
        fi
        sleep 5
    done
    
    if [ "$db_ready" != "true" ]; then
        log_error "MySQL failed to become ready"
        return 1
    fi
    
    # Initialize database if needed
    initialize_mysql_database
    
    # Start the UI service
    if ! systemctl start semaphore-ui.service; then
        log_error "Failed to start semaphore-ui.service"
        systemctl status semaphore-ui.service --no-pager
        return 1
    fi
    
    log_info "All services started successfully"
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
        systemctl status semaphore-ui.service --no-pager
        podman logs semaphore-ui | tail -50
        return 1
    fi
    
    return 0
}

# Display setup completion message
display_setup_completion_message() {
    log_info "================================================================"
    log_info "🚀 SemaphoreUI setup completed successfully!"
    log_info "================================================================"
    log_info "📌 Access URL: http://$(hostname -I | awk '{print $1}'):3000"
    log_info "📌 Admin login: admin / $SEMAPHORE_ADMIN_PASSWORD"
    if [ -n "${AUTOMATION_USER_PASSWORD:-}" ]; then
        log_info "📌 Automation user: automation / $AUTOMATION_USER_PASSWORD"
    fi
    log_info ""
    log_info "📝 All credentials saved to: /root/.credentials/semaphore_credentials.txt"
    log_info "   - File permission: 600 (readable only by root)"
    log_info ""
    log_info "🔄 Template Synchronization: Enabled"
    log_info "   - Run 'Generate Templates' task to sync playbooks with Semaphore"
    log_info "   - Templates are automatically created from annotated playbooks"
    log_info ""
    log_info "⚠️  SECURITY REMINDERS ⚠️"
    log_info "- Keep all passwords secure and don't share them"
    log_info "- Make a note of these passwords before closing this terminal"
    log_info "- Change default passwords after first login through the web interface"
    log_info "- Consider enabling 2FA for additional security if available"
    log_info "- Regularly rotate all passwords as part of your security practice"
    log_info "================================================================"
}

# Remove old systemd files if they exist
cleanup_old_systemd_files() {
    if [ -f /etc/systemd/system/pod-semaphore-pod.service ]; then
        log_info "Removing old systemd service files for Semaphore pod..."
        systemctl disable pod-semaphore-pod.service &>/dev/null || true
        systemctl disable container-semaphore-db.service &>/dev/null || true
        systemctl disable container-semaphore-ui.service &>/dev/null || true
        rm -f /etc/systemd/system/pod-semaphore-pod.service
        rm -f /etc/systemd/system/container-semaphore-db.service
        rm -f /etc/systemd/system/container-semaphore-ui.service
    fi
}

# Create Quadlet configuration files
create_quadlet_files() {
    log_info "Creating Semaphore Quadlet files..."
    mkdir -p /etc/containers/systemd

    create_network_quadlet_file
    create_mysql_quadlet_file
    create_ui_quadlet_file
    
    log_info "Semaphore Quadlet files created."
}

# Create network Quadlet file  
create_network_quadlet_file() {
    cat > /etc/containers/systemd/semaphore.network <<EOF
[Unit]
Description=Semaphore Network
Wants=network-online.target
After=network-online.target

[Network]

[Install]
WantedBy=multi-user.target
EOF
}

# Create MySQL container Quadlet file
create_mysql_quadlet_file() {
    cat > /etc/containers/systemd/semaphore-db.container <<EOF
[Unit]
Description=Semaphore MySQL Database
Requires=semaphore-network.service
After=semaphore-network.service
RequiresMountsFor=/opt/semaphore/mysql/data

[Container]
ContainerName=semaphore-db
Image=docker.io/library/mysql:8.0
Environment=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
Environment=MYSQL_DATABASE=semaphore
Environment=MYSQL_USER=semaphore
Environment=MYSQL_PASSWORD="$MYSQL_SEMAPHORE_PASSWORD"
Volume=/opt/semaphore/mysql/data:/var/lib/mysql:Z
Network=semaphore.network
PublishPort=3306:3306

[Service]
Restart=always
TimeoutStartSec=90s

[Install]
WantedBy=multi-user.target
EOF
}

# Create SemaphoreUI container Quadlet file
create_ui_quadlet_file() {
    cat > /etc/containers/systemd/semaphore-ui.container <<EOF
[Unit]
Description=Semaphore UI
Requires=semaphore-network.service semaphore-db.service
After=semaphore-network.service semaphore-db.service
RequiresMountsFor=/opt/semaphore/app/data /opt/semaphore/app/config

[Container]
ContainerName=semaphore-ui
Image=docker.io/semaphoreui/semaphore:latest
Environment=SEMAPHORE_DB_USER=semaphore
Environment=SEMAPHORE_DB_PASS="$MYSQL_SEMAPHORE_PASSWORD"
Environment=SEMAPHORE_DB_HOST=semaphore-db
Environment=SEMAPHORE_DB_PORT=3306
Environment=SEMAPHORE_DB_DIALECT=mysql
Environment=SEMAPHORE_DB=semaphore
Environment=SEMAPHORE_ADMIN_PASSWORD="$SEMAPHORE_ADMIN_PASSWORD"
Environment=SEMAPHORE_ADMIN_NAME=admin
Environment=SEMAPHORE_ADMIN_EMAIL=admin@localhost
Environment=SEMAPHORE_ADMIN=admin
Environment=SEMAPHORE_ACCESS_KEY_ENCRYPTION="$SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY"
Environment=SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/
Environment=TZ=UTC
Environment=SEMAPHORE_APPS='{"python":{"active":true,"priority":500}}'
Volume=/opt/semaphore/app/data:/etc/semaphore:Z
Volume=/opt/semaphore/app/config:/var/lib/semaphore:Z
Network=semaphore.network
PublishPort=3000:3000

[Service]
Restart=always
TimeoutStartSec=90s

[Install]
WantedBy=multi-user.target
EOF
}

# Setup systemd services using Quadlet
setup_systemd_services() {
    log_info "Reloading systemd daemon and attempting to start/restart Semaphore service..."
    
    if ! systemctl daemon-reload; then
        log_info "ERROR: Failed to reload systemd daemon. Check for systemd errors."
        return 1
    fi
    
    log_info "Systemd daemon reloaded."
    
    if check_semaphore_service_exists; then
        enable_and_start_semaphore_service
    else
        handle_missing_semaphore_service
        return 1
    fi
}

# Check if semaphore service exists
check_semaphore_service_exists() {
    [ -f "/run/systemd/generator/semaphore-network.service" ] || \
    [ -f "/run/systemd/generator.late/semaphore-network.service" ] || \
    systemctl list-unit-files --quiet semaphore-network.service
}

# Enable and start semaphore service
enable_and_start_semaphore_service() {
    log_info "Semaphore network service unit (semaphore-network.service) found by systemd. Attempting to enable and start."
    
    if systemctl enable --now semaphore-network.service semaphore-db.service semaphore-ui.service; then
        log_info "Semaphore services enabled and started/restarted successfully."
        verify_api_after_restart
    else
        handle_service_start_failure
        return 1
    fi
}

# Verify API is responsive after restart
verify_api_after_restart() {
    log_info "Waiting up to 180 seconds for service to fully initialize and API to be responsive..."
    
    local api_check_attempt=1
    local max_api_check_attempts=18 # Try for 3 minutes (18 * 10s)
    local semaphore_api_ready=false
    
    while [ $api_check_attempt -le $max_api_check_attempts ]; do
        log_info "Verifying Semaphore API readiness post-restart (attempt $api_check_attempt/$max_api_check_attempts)..."
        if curl -sSf http://localhost:3000/api/ping >/dev/null; then
            log_info "Semaphore API is responsive after restart."
            semaphore_api_ready=true
            break
        fi
        log_info "Semaphore API not yet responsive, waiting 10 seconds..."
        sleep 10
        ((api_check_attempt++))
    done

    if [ "$semaphore_api_ready" == "false" ]; then
        log_info "ERROR: Semaphore API did not become responsive after service restart and extended wait."
        log_info "Dumping logs and status for semaphore services and semaphore-ui container:"
        systemctl status semaphore-ui.service --no-pager -l || log_info "Failed to get status for semaphore-ui.service"
        podman logs --tail 100 semaphore-ui || log_info "Failed to get logs for semaphore-ui"
        return 1 
    fi
}

# Handle service start failure
handle_service_start_failure() {
    log_info "ERROR: Failed to enable/start semaphore services even though they were found by systemd."
    systemctl status semaphore-network.service --no-pager -l || log_info "Failed to get status for semaphore-network.service"
    systemctl status semaphore-db.service --no-pager -l || log_info "Failed to get status for semaphore-db.service"
    systemctl status semaphore-ui.service --no-pager -l || log_info "Failed to get status for semaphore-ui.service"
    log_info "Current semaphore containers:"
    podman ps -a --filter name=semaphore --format "{{.Names}} ({{.Status}})" || log_info "Failed to list semaphore containers"
    podman logs --tail 100 semaphore-ui || log_info "Failed to get logs for semaphore-ui"
}

# Handle missing semaphore service
handle_missing_semaphore_service() {
    log_info "ERROR: Semaphore network service unit (semaphore-network.service) not found by systemd after daemon-reload."
    log_info "This might indicate an issue with Quadlet generation or that the podman-quadlet package is not installed/working."
    log_info "Ensure '/etc/containers/systemd/semaphore.network' exists and is correctly formatted."
    log_info "Listing generated units (if any) in /run/systemd/generator/ and /run/systemd/generator.late/:"
    ls -la /run/systemd/generator/ || log_info "Could not list /run/systemd/generator/"
    ls -la /run/systemd/generator.late/ || log_info "Could not list /run/systemd/generator.late/"
    log_info "Output of 'systemctl list-unit-files semaphore-*.service':"
    systemctl list-unit_files semaphore-*.service --no-pager || log_info "semaphore services not found by list-unit-files"
}