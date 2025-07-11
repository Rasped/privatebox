#!/bin/bash
# Semaphore setup script

# Source common library
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Default Git repository for PrivateBox project
PRIVATEBOX_GIT_URL="https://github.com/Rasped/privatebox.git"

# Global variable for automation user password
AUTOMATION_USER_PASSWORD=""

# SSH key paths for Ansible automation
SSH_KEY_BASE_PATH="/root/.credentials/semaphore_ansible_key"
SSH_PRIVATE_KEY_PATH="${SSH_KEY_BASE_PATH}"
SSH_PUBLIC_KEY_PATH="${SSH_KEY_BASE_PATH}.pub"

# Function to generate SSH key pair for Ansible automation
generate_ssh_key_pair() {
    log_info "Generating SSH key pair for Ansible automation..."
    
    local ssh_key_comment="semaphore-ansible-automation@$(hostname)"
    
    # Ensure credentials directory exists
    mkdir -p /root/.credentials
    chmod 700 /root/.credentials
    
    # Remove existing keys if they exist
    rm -f "${SSH_PRIVATE_KEY_PATH}" "${SSH_PUBLIC_KEY_PATH}"
    
    # Generate new SSH key pair
    ssh-keygen -t ed25519 -f "${SSH_PRIVATE_KEY_PATH}" -C "${ssh_key_comment}" -N "" -q
    
    if [ $? -ne 0 ]; then
        log_info "ERROR: Failed to generate SSH key pair"
        exit 1
    fi
    
    # Set secure permissions
    chmod 600 "${SSH_PRIVATE_KEY_PATH}"
    chmod 644 "${SSH_PUBLIC_KEY_PATH}"
    
    log_info "SSH key pair generated successfully:"
    log_info "  Private key: ${SSH_PRIVATE_KEY_PATH}"
    log_info "  Public key: ${SSH_PUBLIC_KEY_PATH}"
}

# Function to generate SSH key pair for VM self-management
generate_vm_ssh_key_pair() {
    log_info "Generating SSH key pair for VM self-management..."
    
    local vm_key_path="/root/.credentials/semaphore_vm_key"
    local vm_key_comment="semaphore-vm-self-management@$(hostname)"
    
    # Ensure credentials directory exists
    mkdir -p /root/.credentials
    chmod 700 /root/.credentials
    
    # Remove existing keys if they exist
    rm -f "${vm_key_path}" "${vm_key_path}.pub"
    
    # Generate new SSH key pair
    ssh-keygen -t ed25519 -f "${vm_key_path}" -C "${vm_key_comment}" -N "" -q
    
    if [ $? -ne 0 ]; then
        log_info "ERROR: Failed to generate VM SSH key pair"
        return 1
    fi
    
    # Set secure permissions
    chmod 600 "${vm_key_path}"
    chmod 644 "${vm_key_path}.pub"
    
    # Add public key to VM's own authorized_keys
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    cat "${vm_key_path}.pub" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    
    log_info "VM SSH key pair generated and added to authorized_keys"
    return 0
}

# Main setup function - orchestrates the entire Semaphore installation
setup_semaphore() {
    log_info "Setting up SemaphoreUI with MySQL in containers..."

    # Step 1: Generate and save credentials
    generate_and_save_credentials

    # Step 2: Setup storage directories
    setup_storage_directories

    # Step 3: Setup containers via systemd
    setup_pod_and_containers

    # Step 4: Wait for services to be ready
    wait_for_services_ready

    # Step 5: Create users and projects
    create_automation_user_and_projects

    log_info "Semaphore setup process completed."
}

# Setup users and projects (placeholder for main function consistency)
setup_users_and_projects() {
    # This is now handled within create_automation_user_and_projects
    # which is called from setup_semaphore_ui_container
    log_info "User and project setup is handled during container setup."
}

# Display final status (placeholder for main function consistency)  
display_final_status() {
    # This is now handled within display_setup_completion_message
    # which is called from setup_semaphore_ui_container
    log_info "Final status display is handled during container setup completion."
}

# Generate secure credentials and save them to a protected file
generate_and_save_credentials() {
    log_info "Generating secure credentials..."

    # Check if Semaphore admin password was provided (from cloud-init)
    if [[ -f /etc/privatebox-semaphore-password ]]; then
        source /etc/privatebox-semaphore-password
        log_info "Using provided Semaphore admin password"
    fi

    # Generate secure random passwords with mixed character types
    MYSQL_ROOT_PASSWORD=$(generate_password)
    MYSQL_SEMAPHORE_PASSWORD=$(generate_password)
    
    # Generate password if not provided
    if [[ -z "${SEMAPHORE_ADMIN_PASSWORD:-}" ]]; then
        SEMAPHORE_ADMIN_PASSWORD=$(generate_password)
        log_info "Generated new Semaphore admin password"
    fi
    
    # Generate strong encryption key as per Semaphore documentation
    SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY=$(head -c32 /dev/urandom | base64)

    # Generate SSH key pair for Ansible automation
    generate_ssh_key_pair

    # Generate SSH key pair for VM self-management
    generate_vm_ssh_key_pair

    # Save passwords to a secure file with extra safeguards
    mkdir -p /root/.credentials
    chmod 700 /root/.credentials  # Secure the directory itself
    
    # Create credentials file with clear sections and security notes
    cat > /root/.credentials/semaphore_credentials.txt << EOF
# Semaphore Credentials - CONFIDENTIAL
# Generated on: $(date '+%Y-%m-%d %H:%M:%S')
# Keep this file secure and do not share these credentials

## Database Credentials
MySQL Root Password: $MYSQL_ROOT_PASSWORD
MySQL Semaphore Password: $MYSQL_SEMAPHORE_PASSWORD

## User Credentials
Admin Password: $SEMAPHORE_ADMIN_PASSWORD

## System Credentials
Semaphore Access Key Encryption: $SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY

## SSH Keys
SSH Private Key Path: /root/.credentials/semaphore_ansible_key
SSH Public Key Path: /root/.credentials/semaphore_ansible_key.pub

## VM Self-Management SSH Keys
VM SSH Private Key Path: /root/.credentials/semaphore_vm_key
VM SSH Public Key Path: /root/.credentials/semaphore_vm_key.pub

## Security Note
# These passwords were automatically generated with strong security requirements.
# It is recommended to change these passwords periodically for optimal security.
EOF

    # Set very restrictive permissions
    chmod 600 /root/.credentials/semaphore_credentials.txt
    log_info "Secure credentials saved to /root/.credentials/semaphore_credentials.txt"
    log_info "Directory and file permissions set to restrict access to root only"
}

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

# Get repository ID by name
get_repository_id_by_name() {
    local base_url="$1"
    local session="$2"
    local project_id="$3"
    local repo_name="$4"
    
    log_info "Looking up repository '$repo_name' in project $project_id..." >&2
    
    local api_result=$(make_api_request "GET" \
        "$base_url/api/project/$project_id/repositories" "" "$session" "Getting repositories")
    
    if [ $? -eq 0 ]; then
        local status_code=$(echo "$api_result" | cut -d'|' -f1)
        local repos=$(echo "$api_result" | cut -d'|' -f2-)
        
        if [ "$status_code" -eq 200 ]; then
            local repo_id=$(echo "$repos" | jq -r ".[] | select(.name==\"$repo_name\") | .id" 2>/dev/null)
            if [ -n "$repo_id" ] && [ "$repo_id" != "null" ]; then
                log_info "Found repository '$repo_name' with ID: $repo_id" >&2
                echo "$repo_id"
            else
                log_info "WARNING: Repository '$repo_name' not found in project" >&2
                log_info "Available repositories: $(echo "$repos" | jq -r '.[].name' 2>/dev/null | tr '\n' ', ')" >&2
            fi
        else
            log_error "Failed to list repositories. Status: $status_code"
        fi
    else
        log_error "Failed to get repositories list"
    fi
}

# Create repository in Semaphore
create_repository() {
    local project_id="$1"
    local repo_name="$2"
    local git_url="$3"
    local admin_session="$4"
    
    log_info "Creating repository '$repo_name' in project $project_id..."
    log_info "Repository URL: $git_url"
    
    # Create repository payload
    local repo_payload=$(jq -n \
        --arg name "$repo_name" \
        --arg url "$git_url" \
        --argjson pid "$project_id" \
        '{
            name: $name,
            project_id: $pid,
            git_url: $url,
            git_branch: "main",
            ssh_key_id: 1
        }')
    
    log_info "Repository payload: $(echo "$repo_payload" | jq -c .)"
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/repositories" \
        "$repo_payload" "$admin_session" "Creating repository $repo_name")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for repository creation"
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    log_info "Repository creation response - Status: $status_code"
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local repo_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$repo_id" ] && [ "$repo_id" != "null" ]; then
            log_info "✓ Repository '$repo_name' created successfully with ID: $repo_id" >&2
            echo "$repo_id"
            return 0
        else
            log_info "WARNING: Repository '$repo_name' created but couldn't extract ID from response" >&2
            log_info "Response body: $response_body" >&2
            return 0
        fi
    elif [ -n "$response_body" ] && (echo "$response_body" | jq -e '.error' 2>/dev/null | grep -q "already exists" || \
         echo "$response_body" | jq -e '.message' 2>/dev/null | grep -q "already exists"); then
        log_info "Repository '$repo_name' already exists, looking up ID..." >&2
        # Get the existing repository ID
        local existing_id=$(get_repository_id_by_name "http://localhost:3000" "$admin_session" "$project_id" "$repo_name")
        if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
            log_info "✓ Using existing repository with ID: $existing_id" >&2
            echo "$existing_id"
            return 0
        else
            log_error "Repository exists but couldn't find its ID"
            return 1
        fi
    else
        log_error "Failed to create repository. Status: $status_code"
        log_error "Full response: $response_body"
        return 1
    fi
}

# Get inventory ID by name
get_inventory_id_by_name() {
    local base_url="$1"
    local session="$2"
    local project_id="$3"
    local inv_name="$4"
    
    local api_result=$(make_api_request "GET" \
        "$base_url/api/project/$project_id/inventory" "" "$session" "Getting inventories")
    
    if [ $? -eq 0 ]; then
        local invs=$(echo "$api_result" | cut -d'|' -f2-)
        echo "$invs" | jq -r ".[] | select(.name==\"$inv_name\") | .id" 2>/dev/null
    fi
}

# Function to create API token for template generator
create_api_token() {
    local admin_session="$1"
    local token_name="template-generator"
    
    log_info "Creating API token for template generator..." >&2
    
    # Create token via API
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/user/tokens" \
        "{\"name\": \"$token_name\"}" "$admin_session" "Creating API token")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create API token" >&2
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    log_info "API token creation response - Status: $status_code" >&2
    log_info "API token creation response body: $response_body" >&2
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local token=$(echo "$response_body" | jq -r '.id // .token' 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            log_info "Extracted API token: $token" >&2
            echo "$token"
            return 0
        fi
    fi
    
    log_error "Failed to extract token from response" >&2
    return 1
}

# Create SemaphoreAPI environment with token
create_semaphore_api_environment() {
    local project_id="$1"
    local api_token="$2"
    local admin_session="$3"
    
    log_info "Creating SemaphoreAPI environment for project $project_id..." >&2
    log_info "API Token (FULL): $api_token" >&2
    
    # Create environment payload - Semaphore stores variables and secrets separately
    # The json field expects a JSON string, not an object
    local env_payload=$(jq -n \
        --arg name "SemaphoreAPI" \
        --argjson pid "$project_id" \
        --arg url "http://localhost:3000" \
        --arg token "$api_token" \
        '{
            name: $name,
            project_id: $pid,
            json: ({SEMAPHORE_URL: $url} | tostring),
            env: "{}",
            secrets: [{
                type: "var",
                name: "SEMAPHORE_API_TOKEN",
                secret: $token,
                operation: "create"
            }]
        }')
    
    # Log the actual payload - full details for debugging
    log_info "Environment payload (FULL): $(echo "$env_payload" | jq -c '.')" >&2
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/environment" \
        "$env_payload" "$admin_session" "Creating SemaphoreAPI environment")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for environment creation"
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    log_info "Environment creation response - Status: $status_code" >&2
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local env_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$env_id" ] && [ "$env_id" != "null" ]; then
            log_info "✓ SemaphoreAPI environment created successfully with ID: $env_id" >&2
            echo "$env_id"
            return 0
        else
            log_info "WARNING: Environment created but couldn't extract ID" >&2
            log_info "Response body: $response_body" >&2
            # Check if environment already exists
            local existing_env=$(make_api_request "GET" \
                "http://localhost:3000/api/project/$project_id/environment" \
                "" "$admin_session" "Checking existing environments")
            if [ $? -eq 0 ]; then
                local envs=$(echo "$existing_env" | cut -d'|' -f2-)
                local found_id=$(echo "$envs" | jq -r '.[] | select(.name=="SemaphoreAPI") | .id' 2>/dev/null)
                if [ -n "$found_id" ] && [ "$found_id" != "null" ]; then
                    log_info "Found existing SemaphoreAPI environment with ID: $found_id" >&2
                    echo "$found_id"
                    return 0
                fi
            fi
        fi
    elif [ -n "$response_body" ] && (echo "$response_body" | jq -e '.error' 2>/dev/null | grep -q "already exists" || \
         echo "$response_body" | jq -e '.message' 2>/dev/null | grep -q "already exists"); then
        log_info "SemaphoreAPI environment already exists, looking up ID..." >&2
        # Get the existing environment ID
        local existing_env=$(make_api_request "GET" \
            "http://localhost:3000/api/project/$project_id/environment" \
            "" "$admin_session" "Getting existing environments")
        if [ $? -eq 0 ]; then
            local envs=$(echo "$existing_env" | cut -d'|' -f2-)
            local found_id=$(echo "$envs" | jq -r '.[] | select(.name=="SemaphoreAPI") | .id' 2>/dev/null)
            if [ -n "$found_id" ] && [ "$found_id" != "null" ]; then
                log_info "Using existing SemaphoreAPI environment with ID: $found_id" >&2
                echo "$found_id"
                return 0
            fi
        fi
    else
        log_error "Failed to create environment. Status: $status_code"
        log_error "Full response: $response_body"
        return 1
    fi
}

# Create Generate Templates task
create_template_generator_task() {
    local project_id="$1"
    local repository_id="$2"
    local inventory_id="$3"
    local environment_id="$4"
    local admin_session="$5"
    
    log_info "Creating Generate Templates task..."
    log_info "Project ID: $project_id, Repository ID: $repository_id, Inventory ID: $inventory_id, Environment ID: $environment_id"
    
    local template_payload=$(jq -n \
        --arg name "Generate Templates" \
        --argjson pid "$project_id" \
        --argjson inv_id "$inventory_id" \
        --argjson repo_id "$repository_id" \
        --argjson env_id "$environment_id" \
        '{
            name: $name,
            project_id: $pid,
            inventory_id: $inv_id,
            repository_id: $repo_id,
            environment_id: $env_id,
            app: "python",
            playbook: "tools/generate-templates.py",
            description: "Automatically generate Semaphore templates from playbooks",
            arguments: "[]",
            allow_override_args_in_task: false,
            type: ""
        }')
    
    log_info "Template payload: $(echo "$template_payload" | jq -c .)"
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/templates" \
        "$template_payload" "$admin_session" "Creating template generator task")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for template creation"
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    log_info "Template creation response - Status: $status_code"
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local template_id=$(echo "$response_body" | jq -r '.id')
        if [ -n "$template_id" ] && [ "$template_id" != "null" ]; then
            log_info "✓ Generate Templates task created successfully with ID: $template_id" >&2
            echo "$template_id"
            return 0
        else
            log_error "Template created but couldn't extract ID"
            log_error "Response body: $response_body"
            return 1
        fi
    else
        log_error "Failed to create template. Status: $status_code"
        log_error "Full response: $response_body"
        return 1
    fi
}

# Run a Semaphore task and wait for completion
run_semaphore_task() {
    local template_id="$1"
    local admin_session="$2"
    
    log_info "Running template generation task..."
    
    # Start the task
    local task_payload="{\"template_id\": $template_id}"
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/1/tasks" \
        "$task_payload" "$admin_session" "Starting template generation")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local task_id=$(echo "$api_result" | cut -d'|' -f2- | jq -r '.id' 2>/dev/null)
    
    if [ "$status_code" -ne 201 ] && [ "$status_code" -ne 200 ]; then
        log_error "Failed to start task"
        return 1
    fi
    
    log_info "Task started with ID: $task_id"
    
    # Wait for task completion
    local max_wait=60  # 60 seconds
    local waited=0
    while [ $waited -lt $max_wait ]; do
        sleep 5
        waited=$((waited + 5))
        
        # Check task status
        local status_result=$(make_api_request "GET" \
            "http://localhost:3000/api/project/1/tasks/$task_id" \
            "" "$admin_session" "Checking task status")
        
        if [ $? -eq 0 ]; then
            local task_status=$(echo "$status_result" | cut -d'|' -f2- | jq -r '.status' 2>/dev/null)
            if [ "$task_status" = "success" ]; then
                log_info "Template generation completed successfully!"
                return 0
            elif [ "$task_status" = "error" ] || [ "$task_status" = "failed" ]; then
                log_error "Template generation failed"
                return 1
            fi
        fi
        
        log_info "Task still running... ($waited/$max_wait seconds)"
    done
    
    log_info "WARNING: Task did not complete within timeout"
    return 1
}

# Setup template synchronization infrastructure
setup_template_synchronization() {
    local project_id="$1"
    local admin_session="$2"
    
    log_info "========================================"
    log_info "Setting up template synchronization infrastructure..."
    log_info "========================================"
    
    # Create API token
    log_info "Step 1/5: Creating API token..."
    local api_token=$(create_api_token "$admin_session")
    if [ -z "$api_token" ]; then
        log_error "❌ Failed to create API token for template sync"
        log_info "Template sync setup FAILED at step 1"
        return 1
    fi
    log_info "✓ API token created"
    
    # Save token to credentials file
    echo "Template Generator API Token: $api_token" >> /root/.credentials/semaphore_credentials.txt
    
    # Create SemaphoreAPI environment
    log_info "Step 2/5: Creating SemaphoreAPI environment..."
    local env_id=$(create_semaphore_api_environment "$project_id" "$api_token" "$admin_session")
    if [ -z "$env_id" ]; then
        log_error "❌ Failed to create SemaphoreAPI environment"
        log_info "Template sync setup FAILED at step 2"
        return 1
    fi
    log_info "✓ Environment created with ID: $env_id"
    
    # Get resource IDs
    log_info "Step 3/5: Looking up resource IDs..."
    local repo_id=$(get_repository_id_by_name "http://localhost:3000" "$admin_session" "$project_id" "PrivateBox")
    local inv_id=$(get_inventory_id_by_name "http://localhost:3000" "$admin_session" "$project_id" "Default Inventory")
    
    if [ -z "$repo_id" ]; then
        log_error "❌ Failed to find PrivateBox repository"
        log_info "Template sync setup FAILED at step 3 - repository not found"
        return 1
    fi
    if [ -z "$inv_id" ]; then
        log_error "❌ Failed to find Default Inventory"
        log_info "Template sync setup FAILED at step 3 - inventory not found"
        return 1
    fi
    log_info "✓ Found repository (ID: $repo_id) and inventory (ID: $inv_id)"
    
    # Create Generate Templates task
    log_info "Step 4/5: Creating Generate Templates task..."
    local template_id=$(create_template_generator_task "$project_id" "$repo_id" "$inv_id" "$env_id" "$admin_session")
    if [ -z "$template_id" ]; then
        log_error "❌ Failed to create template generator task"
        log_info "Template sync setup FAILED at step 4"
        return 1
    fi
    log_info "✓ Task created with ID: $template_id"
    
    # Run initial template generation
    log_info "Step 5/5: Running initial template generation..."
    if run_semaphore_task "$template_id" "$admin_session"; then
        log_info "✓ Initial template synchronization completed successfully!"
    else
        log_info "WARNING: ⚠️  Initial template sync failed, but can be run manually later"
    fi
    
    log_info "========================================"
    log_info "Template synchronization setup COMPLETED"
    log_info "Summary:"
    log_info "  - API Token: Created and saved"
    log_info "  - Environment: SemaphoreAPI (ID: $env_id)"
    log_info "  - Repository: PrivateBox (ID: $repo_id)"
    log_info "  - Task: Generate Templates (ID: $template_id)"
    log_info "========================================"
    
    return 0
}

# Note: The following functions are no longer used with systemd/quadlet approach
# but are kept for reference

# Setup MySQL container with proper initialization
setup_mysql_container() {
    local mysql_newly_created=false # Flag to track if MySQL was newly created
    
    if podman container inspect semaphore-db &>/dev/null; then
        handle_existing_mysql_container
    else
        create_new_mysql_container
        mysql_newly_created=true
    fi

    # Initialize MySQL if it's new or not yet initialized
    if [ "$mysql_newly_created" == "true" ] || [ ! -f "/opt/semaphore/.mysql_initialized" ]; then
        initialize_mysql_database
    else
        log_info "MySQL was already running or initialized, skipping explicit wait and setup."
    fi
}

# Handle existing MySQL container
handle_existing_mysql_container() {
    log_info "MySQL container (semaphore-db) already exists."
    local mysql_running_status=$(podman container inspect semaphore-db --format '{{.State.Running}}' 2>/dev/null || echo "false")
    if [ "$mysql_running_status" == "true" ]; then
        log_info "MySQL container (semaphore-db) is already running."
    else
        log_info "MySQL container (semaphore-db) is stopped. Attempting to start..."
        if podman start semaphore-db; then
            log_info "MySQL container (semaphore-db) started successfully."
        else
            log_info "ERROR: Failed to start existing MySQL container (semaphore-db)."
            podman log_infos semaphore-db
            exit 1
        fi
    fi
}

# Create new MySQL container
create_new_mysql_container() {
    log_info "Starting MySQL container..."
    podman run -d \
      --pod semaphore-pod \
      --name semaphore-db \
      --restart=no \
      -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
      -e MYSQL_DATABASE=semaphore \
      -e MYSQL_USER=semaphore \
      -e MYSQL_PASSWORD="$MYSQL_SEMAPHORE_PASSWORD" \
      -v /opt/semaphore/mysql/data:/var/lib/mysql:Z \
      docker.io/library/mysql:8.0

    # Verify MySQL container is running (after creation)
    if podman ps --filter name=semaphore-db --format '{{.Names}}' | grep -q "^semaphore-db$"; then
        log_info "MySQL container started successfully"
    else
        log_info "ERROR: Failed to start MySQL container!"
        podman log_infos semaphore-db
        exit 1
    fi
}

# Initialize MySQL database with proper user permissions
initialize_mysql_database() {
    log_info "Waiting for MySQL to initialize..."
    
    # Wait for MySQL to be ready with healthcheck
    wait_for_mysql_ready
    
    # Ensure the semaphore user has proper permissions
    configure_mysql_permissions
    
    # Mark MySQL as initialized
    touch /opt/semaphore/.mysql_initialized
    log_info "MySQL user permissions configured."
}

# Wait for MySQL to become ready
wait_for_mysql_ready() {
    local mysql_ready=false
    local attempt=1
    local max_attempts=30
    
    while [ $attempt -le $max_attempts ] && [ "$mysql_ready" == "false" ]; do
        log_info "Checking MySQL readiness (attempt $attempt/$max_attempts)..."
        if podman exec semaphore-db mysqladmin ping -h localhost -u root --password="$MYSQL_ROOT_PASSWORD" --silent &>/dev/null; then
            log_info "MySQL is ready."
            mysql_ready=true
        else
            log_info "MySQL not ready yet, waiting..."
            sleep 5
            ((attempt++))
        fi
    done
    
    if [ "$mysql_ready" == "false" ]; then
        log_info "ERROR: MySQL failed to become ready after multiple attempts."
        exit 1
    fi
}

# Configure MySQL user permissions
configure_mysql_permissions() {
    log_info "Configuring MySQL user permissions..."
    podman exec semaphore-db mysql -u root --password="$MYSQL_ROOT_PASSWORD" -e "
        CREATE USER IF NOT EXISTS 'semaphore'@'%' IDENTIFIED BY '$MYSQL_SEMAPHORE_PASSWORD';
        GRANT ALL PRIVILEGES ON semaphore.* TO 'semaphore'@'%';
        CREATE USER IF NOT EXISTS 'semaphore'@'127.0.0.1' IDENTIFIED BY '$MYSQL_SEMAPHORE_PASSWORD';
        GRANT ALL PRIVILEGES ON semaphore.* TO 'semaphore'@'127.0.0.1';
        CREATE USER IF NOT EXISTS 'semaphore'@'localhost' IDENTIFIED BY '$MYSQL_SEMAPHORE_PASSWORD';
        GRANT ALL PRIVILEGES ON semaphore.* TO 'semaphore'@'localhost';
        FLUSH PRIVILEGES;
    "
}

# Setup SemaphoreUI container
setup_semaphore_ui_container() {
    log_info "Ensuring MySQL is running properly before starting SemaphoreUI..."
    sleep 5
    
    handle_semaphore_ui_container
    verify_database_connection
    cleanup_old_systemd_files
    create_quadlet_files
    
    # Try to setup systemd services, but don't fail the whole setup if it fails
    if setup_systemd_services; then
        log_info "Systemd services setup completed successfully."
    else
        log_info "WARNING: Systemd services setup failed, but containers are running. Continuing with user and project creation."
    fi
    
    create_automation_user_and_projects
}

# Handle existing or create new SemaphoreUI container
handle_semaphore_ui_container() {
    if podman container inspect semaphore-ui &>/dev/null; then
        handle_existing_semaphore_ui_container
    else
        create_new_semaphore_ui_container
    fi
}

# Handle existing SemaphoreUI container
handle_existing_semaphore_ui_container() {
    log_info "SemaphoreUI container (semaphore-ui) already exists."
    local semaphore_running_status=$(podman container inspect semaphore-ui --format '{{.State.Running}}' 2>/dev/null || echo "false")
    if [ "$semaphore_running_status" == "true" ]; then
        log_info "SemaphoreUI container (semaphore-ui) is already running."
    else
        log_info "SemaphoreUI container (semaphore-ui) is stopped. Attempting to start..."
        if podman start semaphore-ui; then
            log_info "SemaphoreUI container (semaphore-ui) started successfully."
        else
            log_info "ERROR: Failed to start existing SemaphoreUI container (semaphore-ui)."
            podman log_infos semaphore-ui
            exit 1
        fi
    fi
}

# Create new SemaphoreUI container
create_new_semaphore_ui_container() {
    log_info "Starting SemaphoreUI container..."
    podman run -d \
      --pod semaphore-pod \
      --name semaphore-ui \
      --restart=no \
      -e SEMAPHORE_DB_USER=semaphore \
      -e SEMAPHORE_DB_PASS="$MYSQL_SEMAPHORE_PASSWORD" \
      -e SEMAPHORE_DB_HOST=127.0.0.1 \
      -e SEMAPHORE_DB_PORT=3306 \
      -e SEMAPHORE_DB_DIALECT=mysql \
      -e SEMAPHORE_DB=semaphore \
      -e SEMAPHORE_ADMIN_PASSWORD="$SEMAPHORE_ADMIN_PASSWORD" \
      -e SEMAPHORE_ADMIN_NAME=admin \
      -e SEMAPHORE_ADMIN_EMAIL=admin@localhost \
      -e SEMAPHORE_ADMIN=admin \
      -e SEMAPHORE_ACCESS_KEY_ENCRYPTION="$SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY" \
      -e SEMAPHORE_PLAYBOOK_PATH=/tmp/semaphore/ \
      -e TZ=UTC \
      -v /opt/semaphore/app/data:/etc/semaphore:Z \
      -v /opt/semaphore/app/config:/var/lib/semaphore:Z \
      docker.io/semaphoreui/semaphore:latest

    # Verify SemaphoreUI container is running
    if ! podman ps --filter name=semaphore-ui --format '{{.Names}}' | grep -q "^semaphore-ui$"; then
        log_info "ERROR: Failed to start SemaphoreUI container!"
        podman log_infos semaphore-ui
        exit 1
    fi
    
    log_info "SemaphoreUI container started successfully."
}

# Verify database connection from SemaphoreUI to MySQL
verify_database_connection() {
    log_info "Verifying database connection..."
    local connection_attempt=1
    local max_connection_attempts=15
    local connection_verified=false
    
    # Wait for Semaphore UI to start properly
    log_info "Waiting for Semaphore UI to initialize (this may take a minute)..."
    sleep 10
    
    while [ $connection_attempt -le $max_connection_attempts ] && [ "$connection_verified" == "false" ]; do
        log_info "Checking database connection (attempt $connection_attempt/$max_connection_attempts)..."
        
        if check_api_responding; then
            log_info "Database connection verified - API is responding."
            connection_verified=true
            continue
        fi
        
        if check_database_errors; then
            exit 1
        fi
        
        if check_direct_mysql_connection "$connection_attempt"; then
            connection_verified=true
            continue
        fi
        
        # If not verified yet, wait and retry
        if [ "$connection_verified" == "false" ]; then
            log_info "Database connection not confirmed yet, waiting..."
            sleep 10
            ((connection_attempt++))
        fi
    done
    
    handle_connection_verification_result "$connection_verified"
}

# Check if API is responding
check_api_responding() {
    curl -s -f http://localhost:3000/api/ping > /dev/null 2>&1
}

# Check for database error messages in log_infos
check_database_errors() {
    if podman log_infos semaphore-ui 2>&1 | grep -q "Access denied"; then
        log_info "ERROR: Database connection failed - Access denied error detected."
        podman log_infos semaphore-ui | grep -A 5 "Access denied"
        return 0  # Found error
    elif podman log_infos semaphore-ui 2>&1 | grep -q "Connection refused"; then
        log_info "ERROR: Database connection failed - Connection refused."
        podman log_infos semaphore-ui | grep -A 5 "Connection refused"
        return 0  # Found error
    fi
    return 1  # No error found
}

# Check direct MySQL connection every 3 attempts
check_direct_mysql_connection() {
    local attempt="$1"
    if ((attempt % 3 == 0)); then
        log_info "Attempting direct database connection check..."
        if podman exec semaphore-ui mysqladmin ping -h 127.0.0.1 -u semaphore --password="$MYSQL_SEMAPHORE_PASSWORD" --silent &>/dev/null; then
            log_info "Direct database connection successful."
            sleep 10  # Wait for application to fully connect
            return 0  # Success
        fi
    fi
    return 1  # No check performed or failed
}

# Handle the result of connection verification
handle_connection_verification_result() {
    local connection_verified="$1"
    
    if [ "$connection_verified" == "false" ]; then
        log_info "WARNING: Could not verify database connection within timeout period."
        log_info "Checking if API is responsive despite connection verification failure..."
        
        if curl -s -f http://localhost:3000/api/ping > /dev/null 2>&1; then
            log_info "API is actually responding. Proceeding despite connection verification failure."
        else
            log_info "API is not responding. Service may not work properly."
            log_info "Latest container log_infos:"
            podman log_infos --tail 20 semaphore-ui
        fi
    fi
    
    display_setup_completion_message
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
        log_info "Dumping log_infos and status for semaphore services and semaphore-ui container:"
        systemctl status semaphore-ui.service --no-pager -l || log_info "Failed to get status for semaphore-ui.service"
        podman log_infos --tail 100 semaphore-ui || log_info "Failed to get log_infos for semaphore-ui"
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
    podman log_infos --tail 100 semaphore-ui || log_info "Failed to get log_infos for semaphore-ui"
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

# Create automation user and default projects
create_automation_user_and_projects() {
    log_info "Setting up automation user and projects..."
    
    # Ensure tools are installed and API is ready (do this once for all operations)
    ensure_semaphore_tools || return 1
    wait_for_semaphore_api || return 1
    
    # Get admin session once for all operations
    local admin_session=$(get_admin_session "user and project setup")
    if [ $? -ne 0 ]; then
        log_error "Failed to get admin session for setup"
        return 1
    fi
    
    # Generate secure password for automation user (assign to global variable)
    AUTOMATION_USER_PASSWORD=$(generate_password)
    
    # Create automation user
    create_semaphore_user "automation" "$AUTOMATION_USER_PASSWORD" "auto@example.com" "Automation User" "$admin_session"
    
    # Save automation user credentials to the secure file
    echo "Automation User Password: $AUTOMATION_USER_PASSWORD" >> /root/.credentials/semaphore_credentials.txt
    
    # Create PrivateBox project and add SSH key
    create_infrastructure_project_with_ssh_key "$admin_session"
    
    # Deploy SSH public key to Proxmox host if configured
    deploy_ssh_key_to_proxmox
}

# Ensure required tools are installed
ensure_semaphore_tools() {
    if ! command -v jq &> /dev/null; then
        log_info "Installing required tools..."
        if command -v dnf &> /dev/null; then
            dnf install -y jq curl
        elif command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y jq curl
        else
            log_info "ERROR: Package manager not supported. Install jq and curl manually."
            return 1
        fi
    fi
}

# Wait for Semaphore API to be ready
wait_for_semaphore_api() {
    log_info "Waiting for Semaphore API to be ready..."
    local attempt=1
    local max_attempts=15
    while ! curl -sSf http://localhost:3000/api/ping >/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            log_info "ERROR: Semaphore API failed to start after $((max_attempts*10)) seconds"
            return 1
        fi
        log_info "API not ready yet, waiting (attempt $attempt/$max_attempts)..."
        sleep 10
        ((attempt++))
    done
    
    log_info "API is responding, waiting 5 more seconds for full initialization..."
    sleep 5
}

# Try different password sources for admin authentication
try_admin_authentication() {
    local file_admin_password=$(grep 'Admin Password' /root/.credentials/semaphore_credentials.txt | cut -d' ' -f3-)
    local container_admin_password=$(podman exec semaphore-ui printenv SEMAPHORE_ADMIN_PASSWORD 2>/dev/null)
    
    # Log debugging info to stderr
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using credential file password (first 2 chars): ${file_admin_password:0:2}****" >&2
    if [ -n "$container_admin_password" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found container password (first 2 chars): ${container_admin_password:0:2}****" >&2
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No container password found" >&2
    fi
    
    # Try container password if available
    local admin_password="$file_admin_password"
    local http_code=401
    
    if [ -n "$container_admin_password" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Trying with container environment password..." >&2
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 30 -X POST -H "Content-Type: application/json" \
            -d "{\"auth\": \"admin\", \"password\": \"$container_admin_password\"}" \
            http://localhost:3000/api/auth/login)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Container password auth HTTP status code: $http_code" >&2
        
        if [ "$http_code" == "200" ] || [ "$http_code" == "204" ]; then
            admin_password="$container_admin_password"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Container password authentication successful!" >&2
        fi
    fi
    
    # If container password didn't work, try credential file password
    if [ "$http_code" != "200" ] && [ "$http_code" != "204" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Trying with credential file password..." >&2
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 30 -X POST -H "Content-Type: application/json" \
            -d "{\"auth\": \"admin\", \"password\": \"$file_admin_password\"}" \
            http://localhost:3000/api/auth/login)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Credential file password auth HTTP status code: $http_code" >&2
    fi
    
    # Try with default credentials as last resort
    if [ "$http_code" != "200" ] && [ "$http_code" != "204" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Trying with default credentials (admin/changeme) as fallback..." >&2
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 30 -X POST -H "Content-Type: application/json" \
            -d '{"auth": "admin", "password": "changeme"}' \
            http://localhost:3000/api/auth/login)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Default credentials HTTP status code: $http_code" >&2
        
        if [ "$http_code" == "200" ] || [ "$http_code" == "204" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Default credentials worked! Using admin/changeme instead" >&2
            admin_password="changeme"
        fi
    fi
    
    echo "$admin_password"
}

# Get admin session cookie for API operations
get_admin_session() {
    local operation_name="$1"
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Obtaining admin session for $operation_name (attempt $attempt/$max_attempts)..." >&2
        
        local admin_password=$(try_admin_authentication)
        
        # Get session cookie using curl -c flag  
        log_info "Attempting to get session cookie with password: ${admin_password:0:2}****" >&2
        local cookie_output=$(curl -s -m 30 -c - -X POST -H "Content-Type: application/json" \
            -d "{\"auth\": \"admin\", \"password\": \"$admin_password\"}" \
            http://localhost:3000/api/auth/login)
        log_info "Cookie output (first 100 chars): ${cookie_output:0:100}..." >&2
        
        local session_cookie=$(echo "$cookie_output" | grep 'semaphore' | tail -1 | awk -F'\t' '{print $7}')
        log_info "Extracted session cookie (first 20 chars): ${session_cookie:0:20}..." >&2
        
        if [ -z "$session_cookie" ]; then
            log_info "ERROR: Failed to get session cookie for $operation_name." >&2
            log_info "Checking API health..." >&2
            if ! curl -sSf -m 5 http://localhost:3000/api/ping >/dev/null; then
                log_info "API is not responding to ping requests. Server may still be starting." >&2
            else
                log_info "API is responding to ping but login request failed." >&2
            fi
            
            if [ $attempt -eq $max_attempts ]; then
                log_info "Max session attempts reached. Aborting $operation_name." >&2
                return 1
            fi
            log_info "Retrying in 15 seconds..." >&2
            sleep 15
            ((attempt++))
            continue
        fi
        
        log_info "Admin session acquired successfully." >&2
        echo "semaphore=$session_cookie"
        return 0
    done
    
    return 1
}

# Make API request with retry log_infoic using session cookies
make_api_request() {
    local method="$1"
    local url="$2"
    local payload="$3"
    local session_cookie="$4"
    local operation_name="$5"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $operation_name (attempt $attempt/$max_attempts)..." >&2
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Making $method request to $url" >&2
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Payload: $payload" >&2
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cookie: ${session_cookie:0:30}..." >&2
        
        local response=$(curl -s -m 45 -X "$method" -w "\n%{http_code}" \
            -H "Cookie: $session_cookie" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$url")
            
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Raw response: $response" >&2
        
        # Check if response is empty
        if [ -z "$response" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Empty response from API for $operation_name." >&2
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] This could indicate a timeout or connection issue." >&2
            if [ $attempt -eq $max_attempts ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Max attempts reached. Aborting." >&2
                return 1
            fi
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Retrying in 15 seconds..." >&2
            sleep 15
            ((attempt++))
            continue
        fi
        
        local status_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | head -n -1)
        
        if [ -z "$status_code" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Invalid response format (no status code) for $operation_name." >&2
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Raw response: $response" >&2
            if [ $attempt -eq $max_attempts ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Max attempts reached. Aborting." >&2
                return 1
            fi
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Retrying in 10 seconds..." >&2
            sleep 10
            ((attempt++))
            continue
        fi
        
        # Return both status code and response body
        echo "$status_code|$response_body"
        return 0
    done
    
    return 1
}

# Function to create a Semaphore user via API
create_semaphore_user() {
    local username="$1"
    local password="$2"
    local email="$3"
    local full_name="$4"
    local admin_session="${5:-}"  # Optional parameter

    # If admin session not provided, get it
    if [ -z "$admin_session" ]; then
        ensure_semaphore_tools || return 1
        wait_for_semaphore_api || return 1
        
        admin_session=$(get_admin_session "user creation")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    log_info "Creating user: $username..."
    local create_user_payload=$(jq -n --arg u "$username" --arg p "$password" --arg e "$email" --arg n "$full_name" \
        "{name: \$n, username: \$u, email: \$e, password: \$p}")
    
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/users" "$create_user_payload" "$admin_session" "Creating user $username")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ] || [ "$status_code" -eq 204 ]; then
        log_info "User $username operation successful (HTTP $status_code)."
        if [ -n "$response_body" ]; then
            log_info "Response details: $response_body"
        fi
        return 0
    elif [ -n "$response_body" ] && echo "$response_body" | jq -e '.message' 2>/dev/null | grep -q "User with this username already exists"; then
        log_info "User $username already exists. Skipping creation."
        return 0
    else
        log_info "ERROR: Failed to create user $username (HTTP $status_code)."
        if [ -n "$response_body" ]; then
            log_info "Response body: $response_body"
            local error_message=$(echo "$response_body" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
            if [ "$error_message" != "null" ] && [ -n "$error_message" ]; then
                log_info "Error details: $error_message"
            fi
        fi
        
        # For debugging HTTP 400 errors, don't assume it means user exists
        if [ "$status_code" -eq 400 ]; then
            log_info "HTTP 400 detected. This is likely a validation error, not a duplicate user."
            log_info "Check if all required fields are provided and valid."
        fi
        
        return 1
    fi
}

# Function to create a Semaphore project via API
create_semaphore_project() {
    local project_name="$1"
    local project_description="$2"
    local git_url="${3:-}"  # Optional parameter for Git repository URL
    local admin_session="${4:-}"  # Optional parameter for admin session
    
    log_info "Creating Semaphore project: $project_name"
    
    # If admin session not provided, get it
    if [ -z "$admin_session" ]; then
        ensure_semaphore_tools || return 1
        wait_for_semaphore_api || return 1
        
        admin_session=$(get_admin_session "project creation")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # Create project payload
    local project_payload
    if [ -n "$git_url" ]; then
        # Create project with git repository
        project_payload=$(jq -n \
            --arg name "$project_name" \
            --arg desc "$project_description" \
            --arg git "$git_url" \
            '{name: $name, description: $desc, git_url: $git, git_branch: "main"}')
    else
        # Create local project
        project_payload=$(jq -n \
            --arg name "$project_name" \
            --arg desc "$project_description" \
            '{name: $name, description: $desc}')
    fi
    
    # Create project with retry mechanism
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/projects" "$project_payload" "$admin_session" "Creating project $project_name")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local project_id
        if [ -n "$response_body" ]; then
            project_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        fi
        
        if [ -z "$project_id" ] || [ "$project_id" == "null" ]; then
            log_info "WARNING: Project '$project_name' created but couldn't extract project ID from response."
            log_info "Response body: $response_body"
            return 0
        fi
        
        log_info "Project '$project_name' created successfully with ID: $project_id"
        
        # Create default inventory for the project
        create_default_inventory "$project_name" "$project_id" "$admin_session"
        
        return 0
    elif [ -n "$response_body" ] && (echo "$response_body" | jq -e '.error' 2>/dev/null | grep -q "Project with this name already exists" || \
         echo "$response_body" | jq -e '.message' 2>/dev/null | grep -q "already exists"); then
        log_info "Project '$project_name' already exists. Skipping creation."
        return 0
    else
        log_info "ERROR: Failed to create project '$project_name'. Status: $status_code"
        if [ -n "$response_body" ]; then
            log_info "Response body: $response_body"
            local error_message=$(echo "$response_body" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
            if [ "$error_message" != "null" ] && [ -n "$error_message" ]; then
                log_info "Error details: $error_message"
            fi
        fi
        
        # For debugging, let's also check if this is a missing required field issue
        if [ "$status_code" -eq 400 ]; then
            log_info "HTTP 400 detected. This might be a validation error, not a duplicate project."
            log_info "Checking if we need to adjust the project payload..."
            
            # Try a simplified payload without optional fields
            log_info "Retrying with minimal project payload..."
            local simple_payload=$(jq -n --arg name "$project_name" '{name: $name}')
            local retry_result=$(make_api_request "POST" "http://localhost:3000/api/projects" "$simple_payload" "$admin_session" "Retrying project $project_name with minimal payload")
            
            if [ $? -eq 0 ]; then
                local retry_status=$(echo "$retry_result" | cut -d'|' -f1)
                local retry_body=$(echo "$retry_result" | cut -d'|' -f2-)
                
                if [ "$retry_status" -eq 201 ] || [ "$retry_status" -eq 200 ]; then
                    log_info "Project '$project_name' created successfully with minimal payload."
                    local project_id=$(echo "$retry_body" | jq -r '.id' 2>/dev/null)
                    if [ -n "$project_id" ] && [ "$project_id" != "null" ]; then
                        create_default_inventory "$project_name" "$project_id" "$admin_session"
                    fi
                    return 0
                else
                    log_info "Retry also failed with status: $retry_status"
                    log_info "Retry response: $retry_body"
                fi
            fi
        fi
        
        return 1
    fi
}

# Create default inventory for a project
create_default_inventory() {
    local project_name="$1"
    local project_id="$2"
    local admin_session="$3"
    
    log_info "Creating default inventory for project '$project_name'..."
    local inventory_payload=$(jq -n \
        --arg name "Default Inventory" \
        --arg type "static" \
        --argjson pid "$project_id" \
        '{name: $name, type: $type, project_id: $pid}')
        
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/project/$project_id/inventory" "$inventory_payload" "$admin_session" "Creating inventory for project $project_name")
    if [ $? -ne 0 ]; then
        log_info "WARNING: Failed to create default inventory for project '$project_name'."
        return 0 # Continue even if inventory creation fails
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local inv_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$inv_id" ] && [ "$inv_id" != "null" ]; then
            log_info "Default inventory created for project '$project_name' with ID: $inv_id"
        else
            log_info "Default inventory created for project '$project_name'"
        fi
    else
        log_info "WARNING: Failed to create default inventory. Status code: $status_code"
        if [ -n "$response_body" ]; then
            log_info "Response details: $response_body"
        fi
    fi
}

# Function to create SSH key in Semaphore via API
create_semaphore_ssh_key() {
    local project_id="$1"
    local key_name="$2"
    local key_type="${3:-ssh}"  # Default to ssh type
    local admin_session="${4:-}"  # Optional parameter
    local key_path="${5:-$SSH_PRIVATE_KEY_PATH}"  # Use provided path or default
    
    log_info "Creating SSH key '$key_name' for project ID $project_id..."
    
    # If admin session not provided, get it
    if [ -z "$admin_session" ]; then
        ensure_semaphore_tools || return 1
        wait_for_semaphore_api || return 1
        
        admin_session=$(get_admin_session "SSH key creation")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # Read the private key content
    local private_key_content
    
    if [ ! -f "$key_path" ]; then
        log_info "ERROR: SSH private key not found at $key_path"
        return 1
    fi
    
    private_key_content=$(cat "$key_path")
    if [ -z "$private_key_content" ]; then
        log_info "ERROR: Failed to read SSH private key content"
        return 1
    fi
    
    # Create SSH key payload for Semaphore API
    # SSH keys require a nested ssh object with login, passphrase, and private_key fields
    # Use rawfile for proper multiline string handling
    local ssh_key_payload=$(jq -n \
        --arg name "$key_name" \
        --arg type "$key_type" \
        --arg login "root" \
        --rawfile private_key "$key_path" \
        --argjson pid "$project_id" \
        '{name: $name, type: $type, project_id: $pid, ssh: {login: $login, passphrase: "", private_key: $private_key}}')
    
    # Debug logging
    log_info "DEBUG: SSH private key path: $key_path"
    log_info "DEBUG: Private key content length: ${#private_key_content}"
    log_info "DEBUG: First 50 chars of key: ${private_key_content:0:50}..."
    log_info "DEBUG: Payload preview: $(echo "$ssh_key_payload" | jq -c '{name, type, project_id, ssh: {login: .ssh.login, passphrase: .ssh.passphrase, private_key: (.ssh.private_key | .[0:50] + "...")}}')"
    
    log_info "Sending SSH key to Semaphore API..."
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/project/$project_id/keys" "$ssh_key_payload" "$admin_session" "Creating SSH key $key_name")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local key_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$key_id" ] && [ "$key_id" != "null" ]; then
            log_info "SSH key '$key_name' created successfully with ID: $key_id"
            # Store the key ID for potential later use
            echo "SSH Key ID: $key_id" >> /root/.credentials/semaphore_credentials.txt
        else
            log_info "SSH key '$key_name' created successfully"
        fi
        return 0
    elif [ -n "$response_body" ] && (echo "$response_body" | jq -e '.error' 2>/dev/null | grep -q "already exists" || \
         echo "$response_body" | jq -e '.message' 2>/dev/null | grep -q "already exists"); then
        log_info "SSH key '$key_name' already exists. Skipping creation."
        return 0
    else
        log_info "ERROR: Failed to create SSH key '$key_name'. Status: $status_code"
        if [ -n "$response_body" ]; then
            log_info "Response body: $response_body"
            local error_message=$(echo "$response_body" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
            if [ "$error_message" != "null" ] && [ -n "$error_message" ]; then
                log_info "Error details: $error_message"
            fi
        fi
        return 1
    fi
}

# Create PrivateBox project with SSH key
create_infrastructure_project_with_ssh_key() {
    local admin_session="${1:-}"  # Optional parameter
    
    log_info "Creating PrivateBox project with SSH key..."
    
    # Create the project first
    local project_name="PrivateBox"
    local project_description="PrivateBox infrastructure automation"
    
    # If admin session not provided, get it
    if [ -z "$admin_session" ]; then
        ensure_semaphore_tools || return 1
        wait_for_semaphore_api || return 1
        
        admin_session=$(get_admin_session "privatebox project creation")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # Create project payload with Git repository
    local project_payload=$(jq -n \
        --arg name "$project_name" \
        --arg desc "$project_description" \
        --arg git "$PRIVATEBOX_GIT_URL" \
        '{name: $name, description: $desc, git_url: $git, git_branch: "main"}')
    
    # Create project
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/projects" "$project_payload" "$admin_session" "Creating privatebox project")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local project_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$project_id" ] && [ "$project_id" != "null" ]; then
            log_info "PrivateBox project created with ID: $project_id"
            
            # Create default inventory
            create_default_inventory "$project_name" "$project_id" "$admin_session"
            
            # Create repository for the project
            if ! create_repository "$project_id" "PrivateBox" "$PRIVATEBOX_GIT_URL" "$admin_session"; then
                log_error "Failed to create PrivateBox repository - template sync will not work"
                # Continue anyway to set up other components
            fi
            
            # Create SSH key for this project
            create_semaphore_ssh_key "$project_id" "proxmox-host" "ssh" "$admin_session"
            
            # Create SSH key for VM self-management
            create_semaphore_ssh_key "$project_id" "vm-container-host" "ssh" "$admin_session" "/root/.credentials/semaphore_vm_key"
            
            # Setup template synchronization
            setup_template_synchronization "$project_id" "$admin_session"
            
            return 0
        else
            log_info "WARNING: PrivateBox project created but couldn't extract project ID"
            return 1
        fi
    else
        log_info "ERROR: Failed to create PrivateBox project. Status: $status_code"
        return 1
    fi
}


# Function to deploy SSH public key to Proxmox host
deploy_ssh_key_to_proxmox() {
    log_info "Attempting to deploy SSH public key to Proxmox host..."
    
    # Check if we have the necessary configuration
    if [ -z "${PROXMOX_HOST:-}" ]; then
        log_info "WARNING: PROXMOX_HOST not configured. Skipping SSH key deployment."
        log_info "To enable automatic SSH key deployment, set PROXMOX_HOST in config/privatebox.conf"
        return 0
    fi
    
    if [ ! -f "$SSH_PUBLIC_KEY_PATH" ]; then
        log_info "ERROR: SSH public key not found at $SSH_PUBLIC_KEY_PATH"
        return 1
    fi
    
    local public_key_content=$(cat "$SSH_PUBLIC_KEY_PATH")
    if [ -z "$public_key_content" ]; then
        log_info "ERROR: Failed to read SSH public key content"
        return 1
    fi
    
    log_info "Deploying SSH public key to ${PROXMOX_USER:-root}@$PROXMOX_HOST..."
    
    # First, try to create .ssh directory on Proxmox host
    if ssh -o ConnectTimeout=10 -o BatchMode=yes -p "${PROXMOX_SSH_PORT:-22}" "${PROXMOX_USER:-root}@$PROXMOX_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh" 2>/dev/null; then
        log_info "Successfully connected to Proxmox host and ensured .ssh directory exists"
        
        # Deploy the public key
        if echo "$public_key_content" | ssh -o ConnectTimeout=10 -o BatchMode=yes -p "${PROXMOX_SSH_PORT:-22}" "${PROXMOX_USER:-root}@$PROXMOX_HOST" "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null; then
            log_info "✓ SSH public key successfully deployed to Proxmox host"
            log_info "✓ Semaphore can now connect to $PROXMOX_HOST as ${PROXMOX_USER:-root} using SSH keys"
            return 0
        else
            log_info "ERROR: Failed to add SSH public key to authorized_keys on Proxmox host"
            return 1
        fi
    else
        log_info "WARNING: Could not connect to Proxmox host $PROXMOX_HOST"
        log_info "This could be because:"
        log_info "  1. SSH password authentication is disabled"
        log_info "  2. The host is not reachable"
        log_info "  3. SSH keys are already required"
        log_info ""
        log_info "To manually deploy the SSH key, run this command on your Proxmox host:"
        log_info "  echo '$public_key_content' >> ~/.ssh/authorized_keys"
        log_info "  chmod 600 ~/.ssh/authorized_keys"
        log_info ""
        return 0  # Don't fail the whole setup for this
    fi
}
