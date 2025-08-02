#!/bin/bash
# Semaphore setup script - BoltDB version

# Source common library
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Source Semaphore libraries
# shellcheck source=../lib/semaphore-credentials-boltdb.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/semaphore-credentials-boltdb.sh" || {
    echo "ERROR: Cannot source semaphore-credentials library" >&2
    exit 1
}

# shellcheck source=../lib/semaphore-containers-boltdb.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/semaphore-containers-boltdb.sh" || {
    echo "ERROR: Cannot source semaphore-containers library" >&2
    exit 1
}

# shellcheck source=../lib/semaphore-api.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/semaphore-api.sh" || {
    echo "ERROR: Cannot source semaphore-api library" >&2
    exit 1
}

# Default Git repository for PrivateBox project
PRIVATEBOX_GIT_URL="https://github.com/Rasped/privatebox.git"

# Main setup function - orchestrates the entire Semaphore installation
setup_semaphore() {
    log_info "Setting up SemaphoreUI with BoltDB..."

    # Step 1: Generate and save credentials
    generate_and_save_credentials

    # Step 2: Setup storage directories
    setup_storage_directories

    # Step 3: Setup containers via systemd
    setup_pod_and_containers

    # Step 4: Wait for services to be ready
    wait_for_services_ready

    # Step 5: Create default projects
    create_default_projects

    log_info "Semaphore setup process completed."
    
    # Display completion message
    display_setup_completion_message
}