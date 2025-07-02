#!/bin/bash
# Portainer setup script

# Source common library
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

setup_portainer() {
    # Create directory for Portainer data
    log_info "Creating Portainer data directory..."
    mkdir -p /opt/portainer/data
    chmod 755 /opt/portainer/data

    # Create and properly set up the snippets directory
    log_info "Setting up snippets directory and files..."
    mkdir -p /var/lib/snippets
    touch /var/lib/snippets/user-data-9000.yaml
    chmod 644 /var/lib/snippets/user-data-9000.yaml
    chmod 755 /var/lib/snippets

    # Create a persistent volume for snippets if it doesn't exist
    if ! podman volume ls | grep -q "snippets"; then
        log_info "Creating persistent podman volume for snippets..."
        podman volume create snippets
        # Copy the files to the new volume
        cp /var/lib/snippets/user-data-9000.yaml $(podman volume inspect snippets --format '{{.Mountpoint}}')/
        log_info "Snippets volume created and files copied"
    fi

    # Ensure the required volume or file exists before starting containers
    log_info "Ensuring required volume or file exists..."
    if [ ! -f $(podman volume inspect snippets --format '{{.Mountpoint}}')/user-data-9000.yaml ]; then
        log_info "Creating missing file in snippets volume: user-data-9000.yaml"
        touch $(podman volume inspect snippets --format '{{.Mountpoint}}')/user-data-9000.yaml
        chmod 644 $(podman volume inspect snippets --format '{{.Mountpoint}}')/user-data-9000.yaml
    fi

    # Remove old systemd file if it exists from previous method
    if [ -f /etc/systemd/system/container-portainer.service ]; then
        log_info "Removing old systemd service file for Portainer..."
        systemctl disable container-portainer.service &>/dev/null || true
        rm -f /etc/systemd/system/container-portainer.service
    fi

    # Create Quadlet definition for Portainer
    log_info "Creating Portainer Quadlet file..."
    mkdir -p /etc/containers/systemd

    cat > /etc/containers/systemd/portainer.container <<EOF
[Unit]
Description=Portainer CE
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/opt/portainer/data /run/podman

[Container]
Image=docker.io/portainer/portainer-ce:latest
ContainerName=portainer
PublishPort=9000:9000
PublishPort=8000:8000
Volume=/opt/portainer/data:/data:Z
Volume=/run/podman/podman.sock:/var/run/docker.sock:Z
Volume=snippets:/snippets:Z

[Service]
Restart=always
TimeoutStartSec=90s

[Install]
WantedBy=multi-user.target
EOF

    log_info "Portainer Quadlet file created at /etc/containers/systemd/portainer.container"
    
    # Reload systemd to pick up the new Quadlet file
    log_info "Reloading systemd daemon..."
    if ! systemctl daemon-reload; then
        log_error "Failed to reload systemd daemon"
        return 1
    fi
    
    # Start the Portainer service
    log_info "Starting Portainer service..."
    if ! systemctl start portainer.service; then
        log_error "Failed to start Portainer service"
        return 1
    fi
    
    # Verify the service is running
    if systemctl is-active --quiet portainer.service; then
        log_info "Portainer service started successfully"
    else
        log_error "Portainer service failed to start"
        systemctl status portainer.service
        return 1
    fi
}

