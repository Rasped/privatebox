#!/bin/bash
# Semaphore API interaction library for Bootstrap v2
# Adapted from bootstrap/lib/semaphore-api.sh with embedded logging

# Embedded logging functions (no common.sh dependency)
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1" >&2
}

# Helper function to parse API response status code
get_api_status() {
    echo "$1" | cut -d'|' -f1
}

# Helper function to parse API response body
get_api_body() {
    echo "$1" | cut -d'|' -f2-
}

# Helper function to check if API call was successful
is_api_success() {
    local status="$1"
    [[ "$status" == "200" || "$status" == "201" || "$status" == "204" ]]
}

# Create repository
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
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/repositories" \
        "$repo_payload" "$admin_session" "Creating repository $repo_name")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for repository creation"
        return 1
    fi
    
    local status_code=$(get_api_status "$api_result")
    local response_body=$(get_api_body "$api_result")
    
    if is_api_success "$status_code"; then
        local repo_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$repo_id" ] && [ "$repo_id" != "null" ]; then
            log_info "✓ Repository '$repo_name' created successfully with ID: $repo_id"
            echo "$repo_id"
            return 0
        else
            log_warn "Repository '$repo_name' created but couldn't extract ID from response"
            return 0
        fi
    elif echo "$response_body" | grep -q "already exists"; then
        log_info "✓ Repository '$repo_name' already exists"
        return 0
    else
        log_error "Failed to create repository. Status: $status_code"
        return 1
    fi
}

# Create API token
create_api_token() {
    local admin_session="$1"
    local token_name="template-generator"
    
    log_info "Creating API token for template generator..."
    
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/user/tokens" \
        "{\"name\": \"$token_name\"}" "$admin_session" "Creating API token")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create API token"
        return 1
    fi
    
    local status_code=$(get_api_status "$api_result")
    local response_body=$(get_api_body "$api_result")
    
    if is_api_success "$status_code"; then
        local token=$(echo "$response_body" | jq -r '.id // .token' 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            log_info "Extracted API token: $token"
            echo "$token"
            return 0
        fi
    fi
    
    log_error "Failed to extract token from response"
    return 1
}

# Create SemaphoreAPI environment with token
create_semaphore_api_environment() {
    local project_id="$1"
    local api_token="$2"
    local admin_session="$3"
    
    # Get VM IP dynamically
    local vm_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$vm_ip" ]]; then
        vm_ip="${STATIC_IP:-192.168.1.20}"
    fi
    
    log_info "Creating SemaphoreAPI environment for project $project_id..."
    
    local env_payload=$(jq -n \
        --arg name "SemaphoreAPI" \
        --argjson pid "$project_id" \
        --arg url "http://${vm_ip}:3000" \
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
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/environment" \
        "$env_payload" "$admin_session" "Creating SemaphoreAPI environment")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for environment creation"
        return 1
    fi
    
    local status_code=$(get_api_status "$api_result")
    local response_body=$(get_api_body "$api_result")
    
    if is_api_success "$status_code"; then
        local env_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$env_id" ] && [ "$env_id" != "null" ]; then
            log_info "✓ SemaphoreAPI environment created successfully with ID: $env_id"
            echo "$env_id"
            return 0
        fi
    fi
    
    # Check if already exists
    if echo "$response_body" | grep -q "already exists"; then
        log_info "SemaphoreAPI environment already exists, looking up ID..."
        local existing_env=$(make_api_request "GET" \
            "http://localhost:3000/api/project/$project_id/environment" \
            "" "$admin_session" "Getting existing environments")
        if [ $? -eq 0 ]; then
            local envs=$(echo "$existing_env" | cut -d'|' -f2-)
            local found_id=$(echo "$envs" | jq -r '.[] | select(.name=="SemaphoreAPI") | .id' 2>/dev/null)
            if [ -n "$found_id" ] && [ "$found_id" != "null" ]; then
                log_info "Using existing SemaphoreAPI environment with ID: $found_id"
                echo "$found_id"
                return 0
            fi
        fi
    fi
    
    log_error "Failed to create environment. Status: $status_code"
    return 1
}

# Create Generate Templates task
create_template_generator_task() {
    local project_id="$1"
    local repository_id="$2"
    local inventory_id="$3"
    local environment_id="$4"
    local admin_session="$5"
    
    log_info "Creating Generate Templates task..."
    
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
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/templates" \
        "$template_payload" "$admin_session" "Creating template generator task")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for template creation"
        return 1
    fi
    
    local status_code=$(get_api_status "$api_result")
    local response_body=$(get_api_body "$api_result")
    
    if is_api_success "$status_code"; then
        local template_id=$(echo "$response_body" | jq -r '.id')
        if [ -n "$template_id" ] && [ "$template_id" != "null" ]; then
            log_info "✓ Generate Templates task created successfully with ID: $template_id"
            echo "$template_id"
            return 0
        fi
    fi
    
    # If template already exists, return its ID
    if echo "$response_body" | grep -qi "already exists"; then
        local existing_id=$(get_template_id_by_name "$project_id" "Generate Templates" "$admin_session" 2>/dev/null)
        if [ -n "$existing_id" ]; then
            log_info "Using existing Generate Templates task with ID: $existing_id"
            echo "$existing_id"
            return 0
        fi
    fi
    
    log_error "Failed to create template. Status: $status_code"
    return 1
}

# Create ProxmoxAPI environment
create_proxmox_api_environment() {
    local project_id="$1"
    local admin_session="$2"
    
    local token_id="${PROXMOX_TOKEN_ID}"
    local token_secret="${PROXMOX_TOKEN_SECRET}"
    local api_host="${PROXMOX_API_HOST}"
    
    # Debug: Write values to file for verification
    {
        echo "=== ProxmoxAPI Environment Debug ==="
        echo "Timestamp: $(date)"
        echo "PROXMOX_TOKEN_ID: '${token_id}'"
        echo "PROXMOX_TOKEN_SECRET: '${token_secret}'"
        echo "PROXMOX_API_HOST: '${api_host}'"
        echo "Token ID empty? $([[ -z "$token_id" ]] && echo "YES" || echo "NO")"
        echo "Token Secret empty? $([[ -z "$token_secret" ]] && echo "YES" || echo "NO")"
        echo "=================================="
    } >> /tmp/proxmox-api-debug.log
    
    # Skip if no token configured
    if [[ -z "$token_id" ]] || [[ -z "$token_secret" ]]; then
        log_info "No Proxmox API token found, skipping ProxmoxAPI environment"
        echo "SKIPPED: Empty tokens" >> /tmp/proxmox-api-debug.log
        return 0
    fi
    
    log_info "Creating ProxmoxAPI environment for project $project_id..."
    echo "PROCEEDING: Creating environment" >> /tmp/proxmox-api-debug.log
    
    local env_payload=$(jq -n \
        --arg name "ProxmoxAPI" \
        --argjson pid "$project_id" \
        --arg token_id "$token_id" \
        --arg token_secret "$token_secret" \
        --arg api_host "$api_host" \
        '{
            name: $name,
            project_id: $pid,
            json: ({} | tostring),
            env: "{}",
            secrets: [
                {
                    type: "var",
                    name: "PROXMOX_TOKEN_ID",
                    secret: $token_id,
                    operation: "create"
                },
                {
                    type: "var",
                    name: "PROXMOX_TOKEN_SECRET",
                    secret: $token_secret,
                    operation: "create"
                },
                {
                    type: "var",
                    name: "PROXMOX_API_HOST",
                    secret: $api_host,
                    operation: "create"
                },
                {
                    type: "var",
                    name: "PROXMOX_NODE",
                    secret: "pve",
                    operation: "create"
                }
            ]
        }')
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/environment" \
        "$env_payload" "$admin_session" "Creating ProxmoxAPI environment")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for ProxmoxAPI environment creation"
        return 1
    fi
    
    # Parse response
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [[ "$status_code" == "201" ]] || [[ "$status_code" == "204" ]]; then
        local env_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$env_id" ] && [ "$env_id" != "null" ]; then
            log_info "✓ ProxmoxAPI environment created successfully with ID: $env_id"
            echo "$env_id"
            return 0
        fi
    fi
    
    # Check if already exists
    if echo "$response_body" | grep -q "already exists"; then
        log_info "ProxmoxAPI environment already exists"
        return 0
    fi
    
    log_error "Failed to create ProxmoxAPI environment. Status: $status_code"
    return 1
}

# Create password environment
create_password_environment() {
    local project_id="$1"
    local admin_session="$2"
    
    local services_password="${SERVICES_PASSWORD}"
    local admin_password="${ADMIN_PASSWORD}"
    
    if [[ -z "$services_password" ]] || [[ -z "$admin_password" ]]; then
        log_error "Passwords not found in environment variables"
        return 1
    fi
    
    log_info "Creating ServicePasswords environment for project $project_id..."
    
    local env_payload=$(jq -n \
        --arg name "ServicePasswords" \
        --argjson pid "$project_id" \
        --arg admin_pass "$admin_password" \
        --arg services_pass "$services_password" \
        '{
            name: $name,
            project_id: $pid,
            json: ({} | tostring),
            env: "{}",
            secrets: [
                {
                    type: "var",
                    name: "ADMIN_PASSWORD",
                    secret: $admin_pass,
                    operation: "create"
                },
                {
                    type: "var",
                    name: "SERVICES_PASSWORD",
                    secret: $services_pass,
                    operation: "create"
                }
            ]
        }')
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/environment" \
        "$env_payload" "$admin_session" "Creating ServicePasswords environment")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for password environment creation"
        return 1
    fi
    
    local status_code=$(get_api_status "$api_result")
    local response_body=$(get_api_body "$api_result")
    
    if is_api_success "$status_code"; then
        local env_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$env_id" ] && [ "$env_id" != "null" ]; then
            log_info "✓ ServicePasswords environment created successfully with ID: $env_id"
            echo "$env_id"
            return 0
        fi
    fi
    
    # Check if already exists
    if echo "$response_body" | grep -q "already exists"; then
        log_info "ServicePasswords environment already exists"
        return 0
    fi
    
    log_error "Failed to create password environment. Status: $status_code"
    return 1
}

# Setup template synchronization infrastructure
setup_template_synchronization() {
    local project_id="$1"
    local admin_session="$2"
    
    log_info "Setting up template synchronization infrastructure..."
    
    # Create API token
    log_info "Step 1/5: Creating API token..."
    local api_token=$(create_api_token "$admin_session")
    if [ -z "$api_token" ]; then
        log_error "Failed to create API token for template sync"
        return 1
    fi
    log_info "✓ API token created"
    
    # Create SemaphoreAPI environment
    log_info "Step 2/5: Creating SemaphoreAPI environment..."
    local env_id=$(create_semaphore_api_environment "$project_id" "$api_token" "$admin_session")
    if [ -z "$env_id" ]; then
        log_error "Failed to create SemaphoreAPI environment"
        return 1
    fi
    log_info "✓ Environment created with ID: $env_id"
    
    # Use default resource IDs
    log_info "Step 3/5: Using default resource IDs..."
    local repo_id=1
    local inv_id=1
    log_info "✓ Using repository ID: $repo_id and inventory ID: $inv_id"
    
    # Create Generate Templates task
    log_info "Step 4/5: Creating Generate Templates task..."
    local template_id=$(create_template_generator_task "$project_id" "$repo_id" "$inv_id" "$env_id" "$admin_session")
    if [ -z "$template_id" ]; then
        log_error "Failed to create template generator task"
        return 1
    fi
    log_info "✓ Task created with ID: $template_id"
    
    # Auto-run the Generate Templates task once to sync templates
    if run_generate_templates_task "$project_id" "$template_id" "$admin_session"; then
        log_info "✓ Generate Templates task triggered successfully"
    else
        log_warn "Generate Templates task could not be triggered automatically"
    fi
    
    log_info "Template synchronization setup COMPLETED"
    return 0
}

# Wait for Semaphore API to be ready
wait_for_semaphore_api() {
    log_info "Waiting for Semaphore API to be ready..."
    local attempt=1
    local max_attempts=30
    while ! curl -sSf http://localhost:3000/api/ping >/dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            log_error "Semaphore API failed to start after $((max_attempts*10)) seconds"
            return 1
        fi
        log_info "API not ready yet, waiting (attempt $attempt/$max_attempts)..."
        sleep 10
        ((attempt++))
    done
    
    log_info "API is responding, waiting 5 more seconds for full initialization..."
    sleep 5
    return 0
}

# Get admin session cookie for API operations
get_admin_session() {
    local operation_name="$1"
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Obtaining admin session for $operation_name (attempt $attempt/$max_attempts)..."
        
        local admin_password="${SERVICES_PASSWORD}"
        
        # Get session cookie using curl -c flag  
        local cookie_output=$(curl -s -m 30 -c - -X POST -H "Content-Type: application/json" \
            -d "{\"auth\": \"admin\", \"password\": \"$admin_password\"}" \
            http://localhost:3000/api/auth/login 2>/dev/null)
        
        local session_cookie=$(echo "$cookie_output" | grep 'semaphore' | tail -1 | awk -F'\t' '{print $7}')
        
        if [ -z "$session_cookie" ]; then
            log_error "Failed to get session cookie for $operation_name"
            if [ $attempt -eq $max_attempts ]; then
                return 1
            fi
            log_info "Retrying in 15 seconds..."
            sleep 15
            ((attempt++))
            continue
        fi
        
        log_info "Admin session acquired successfully"
        echo "semaphore=$session_cookie"
        return 0
    done
    
    return 1
}

# Find template by name and return ID
get_template_id_by_name() {
    local project_id="$1"
    local template_name="$2"
    local admin_session="$3"
    
    local api_result=$(make_api_request "GET" \
        "http://localhost:3000/api/project/$project_id/templates" "" "$admin_session" "Listing templates")
    if [ $? -ne 0 ]; then
        return 1
    fi
    local status_code=$(get_api_status "$api_result")
    local body=$(get_api_body "$api_result")
    if ! is_api_success "$status_code"; then
        return 1
    fi
    local tid=$(echo "$body" | jq -r ".[] | select(.name==\"$template_name\") | .id" 2>/dev/null)
    if [ -n "$tid" ] && [ "$tid" != "null" ]; then
        echo "$tid"
        return 0
    fi
    return 1
}

# Run the Generate Templates task
run_generate_templates_task() {
    local project_id="$1"
    local template_id="${2:-}"
    local admin_session="$3"
    
    # Resolve template id if not provided
    if [ -z "$template_id" ]; then
        template_id=$(get_template_id_by_name "$project_id" "Generate Templates" "$admin_session") || true
        if [ -z "$template_id" ]; then
            log_warn "Generate Templates task not found for project $project_id"
            return 1
        fi
    fi
    
    log_info "Triggering Generate Templates (template_id=$template_id)"
    local payload='{}'
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/template/$template_id/run" \
        "$payload" "$admin_session" "Running Generate Templates")
    if [ $? -ne 0 ]; then
        return 1
    fi
    local status_code=$(get_api_status "$api_result")
    if is_api_success "$status_code"; then
        return 0
    fi
    log_warn "Generate Templates run returned status $status_code"
    return 1
}

# Make API request with retry logic using session cookies
make_api_request() {
    local method="$1"
    local url="$2"
    local payload="$3"
    local session_cookie="$4"
    local operation_name="$5"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "$operation_name (attempt $attempt/$max_attempts)..."
        
        local response=$(curl -s -m 45 -X "$method" -w "\n%{http_code}" \
            -H "Cookie: $session_cookie" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$url" 2>/dev/null)
        
        if [ -z "$response" ]; then
            log_error "Empty response from API for $operation_name"
            if [ $attempt -eq $max_attempts ]; then
                return 1
            fi
            sleep 15
            ((attempt++))
            continue
        fi
        
        local status_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | head -n -1)
        
        echo "$status_code|$response_body"
        return 0
    done
    
    return 1
}

# Get SSH key ID by name
get_ssh_key_id_by_name() {
    local project_id="$1"
    local key_name="$2"
    local admin_session="$3"
    
    log_info "Looking up SSH key '$key_name' in project $project_id..."
    
    local api_result=$(make_api_request "GET" \
        "http://localhost:3000/api/project/$project_id/keys" "" "$admin_session" "Getting SSH keys")
    
    if [ $? -eq 0 ]; then
        local status_code=$(get_api_status "$api_result")
        local keys=$(get_api_body "$api_result")
        
        if is_api_success "$status_code"; then
            local key_id=$(echo "$keys" | jq -r ".[] | select(.name==\"$key_name\") | .id" 2>/dev/null)
            if [ -n "$key_id" ] && [ "$key_id" != "null" ]; then
                log_info "Found SSH key '$key_name' with ID: $key_id"
                echo "$key_id"
            else
                log_warn "SSH key '$key_name' not found in project"
            fi
        fi
    fi
}

# Create inventory
create_inventory() {
    local project_id="$1"
    local admin_session="$2"
    local inventory_name="$3"
    local inventory_content="$4"
    local ssh_key_id="$5"
    
    log_info "Creating inventory: $inventory_name"
    
    local inventory_payload=$(jq -n \
        --arg name "$inventory_name" \
        --arg type "static" \
        --argjson pid "$project_id" \
        --arg inv "$inventory_content" \
        --argjson ssh_key_id "$ssh_key_id" \
        '{name: $name, type: $type, project_id: $pid, inventory: $inv, ssh_key_id: $ssh_key_id}')
    
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/project/$project_id/inventory" \
        "$inventory_payload" "$admin_session" "Creating $inventory_name")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create $inventory_name"
        return 1
    fi
    
    local status_code=$(get_api_status "$api_result")
    local response_body=$(get_api_body "$api_result")
    
    if is_api_success "$status_code"; then
        local inv_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        log_info "$inventory_name created successfully (ID: $inv_id)"
        return 0
    else
        log_error "Failed to create $inventory_name. Status: $status_code"
        return 1
    fi
}

# Create default inventory
create_default_inventory() {
    local project_name="$1"
    local project_id="$2"
    local admin_session="$3"
    local vm_ssh_key_id="${4:-}"
    
    log_info "Creating inventories for project '$project_name'..."
    
    # Get the VM IP address dynamically
    local vm_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$vm_ip" ]]; then
        vm_ip="${STATIC_IP:-192.168.1.20}"
    fi
    log_info "Using VM IP: $vm_ip"
    
    # Create VM inventory first
    if [ -n "$vm_ssh_key_id" ] && [[ "$vm_ssh_key_id" =~ ^[0-9]+$ ]]; then
        local vm_inventory="all:
  hosts:
    container-host:
      ansible_host: ${vm_ip}
      ansible_user: debian
      ansible_become: true
      ansible_become_method: sudo"
        
        create_inventory "$project_id" "$admin_session" "container-host" "$vm_inventory" "$vm_ssh_key_id"
    else
        log_warn "No valid VM SSH key ID provided, skipping VM inventory creation"
    fi
    
    # Check if Proxmox host IP was discovered and create Proxmox inventory
    if [[ -f /etc/privatebox-proxmox-host ]]; then
        local proxmox_ip=$(cat /etc/privatebox-proxmox-host 2>/dev/null)
        if [ -n "$proxmox_ip" ]; then
            log_info "Found Proxmox host IP: $proxmox_ip"
            
            local proxmox_key_id=$(get_ssh_key_id_by_name "$project_id" "proxmox" "$admin_session")
            
            if [ -n "$proxmox_key_id" ] && [[ "$proxmox_key_id" =~ ^[0-9]+$ ]]; then
                local proxmox_inventory="all:
  hosts:
    proxmox:
      ansible_host: ${proxmox_ip}
      ansible_user: root"
                
                create_inventory "$project_id" "$admin_session" "proxmox" "$proxmox_inventory" "$proxmox_key_id"
            else
                log_warn "No Proxmox SSH key found, cannot create Proxmox inventory"
            fi
        fi
    else
        log_info "No Proxmox host IP found in /etc/privatebox-proxmox-host, skipping Proxmox inventory"
    fi
}

# Create infrastructure project with SSH key
create_infrastructure_project_with_ssh_key() {
    local admin_session="${1:-}"
    
    log_info "Creating PrivateBox project with SSH key..."
    
    # Get admin session if not provided
    if [ -z "$admin_session" ]; then
        wait_for_semaphore_api || return 1
        
        admin_session=$(get_admin_session "privatebox project creation")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # Create project payload with Git repository
    local project_payload=$(jq -n \
        --arg name "PrivateBox" \
        --arg desc "PrivateBox infrastructure management" \
        --arg git "${PRIVATEBOX_GIT_URL}" \
        '{name: $name, description: $desc, git_url: $git, git_branch: "main"}')
    
    # Create project
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/projects" \
        "$project_payload" "$admin_session" "Creating privatebox project")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local status_code=$(get_api_status "$api_result")
    local response_body=$(get_api_body "$api_result")
    
    if is_api_success "$status_code"; then
        local project_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$project_id" ] && [ "$project_id" != "null" ]; then
            log_info "PrivateBox project created with ID: $project_id"
            
            # Create SSH key for Proxmox if available
            local proxmox_key_id=""
            if [ -f "/root/.credentials/proxmox_ssh_key" ]; then
                local ssh_payload=$(jq -n \
                    --arg name "proxmox" \
                    --arg type "ssh" \
                    --argjson pid "$project_id" \
                    --arg priv "$(cat /root/.credentials/proxmox_ssh_key)" \
                    '{name: $name, type: $type, project_id: $pid, ssh: {private_key: $priv}}')
                
                local api_result=$(make_api_request "POST" \
                    "http://localhost:3000/api/project/$project_id/keys" \
                    "$ssh_payload" "$admin_session" "Creating Proxmox SSH key")
                
                if [ $? -eq 0 ]; then
                    local status_code=$(get_api_status "$api_result")
                    local response_body=$(get_api_body "$api_result")
                    
                    if is_api_success "$status_code"; then
                        proxmox_key_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
                        log_info "✓ Proxmox SSH key created with ID: $proxmox_key_id"
                        
                        # Delete the key file after uploading
                        rm -f /root/.credentials/proxmox_ssh_key
                        log_info "✓ Proxmox SSH key removed from filesystem"
                    fi
                fi
            else
                log_warn "Proxmox SSH key not found at /root/.credentials/proxmox_ssh_key"
            fi
            
            # Create SSH key for VM self-management
            local vm_key_id=""
            if [ -f "/root/.credentials/semaphore_vm_key" ]; then
                local ssh_payload=$(jq -n \
                    --arg name "container-host" \
                    --arg type "ssh" \
                    --argjson pid "$project_id" \
                    --arg priv "$(cat /root/.credentials/semaphore_vm_key)" \
                    '{name: $name, type: $type, project_id: $pid, ssh: {private_key: $priv}}')
                
                local api_result=$(make_api_request "POST" \
                    "http://localhost:3000/api/project/$project_id/keys" \
                    "$ssh_payload" "$admin_session" "Creating VM SSH key")
                
                if [ $? -eq 0 ]; then
                    local status_code=$(get_api_status "$api_result")
                    local response_body=$(get_api_body "$api_result")
                    
                    if is_api_success "$status_code"; then
                        vm_key_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
                        log_info "✓ VM SSH key created with ID: $vm_key_id"
                    fi
                fi
            else
                log_warn "VM SSH key not found at /root/.credentials/semaphore_vm_key"
            fi
            
            # Create default inventory with SSH keys
            if [ -n "$vm_key_id" ] && [[ "$vm_key_id" =~ ^[0-9]+$ ]]; then
                create_default_inventory "PrivateBox" "$project_id" "$admin_session" "$vm_key_id"
            else
                create_default_inventory "PrivateBox" "$project_id" "$admin_session"
            fi
            
            # Create repository
            if ! create_repository "$project_id" "PrivateBox" "${PRIVATEBOX_GIT_URL}" "$admin_session"; then
                log_error "Failed to create PrivateBox repository"
            fi
            
            # Create password environment
            if ! create_password_environment "$project_id" "$admin_session"; then
                log_error "Failed to create password environment"
            fi
            
            # Create ProxmoxAPI environment
            if ! create_proxmox_api_environment "$project_id" "$admin_session"; then
                log_error "Failed to create ProxmoxAPI environment"
            fi
            
            # Setup template synchronization
            setup_template_synchronization "$project_id" "$admin_session"
            
            return 0
        else
            log_error "PrivateBox project created but couldn't extract project ID"
            return 1
        fi
    else
        log_error "Failed to create PrivateBox project. Status: $status_code"
        return 1
    fi
}

# Main entry point
create_default_projects() {
    log_info "Setting up default projects..."
    
    # Wait for API
    wait_for_semaphore_api || return 1
    
    # Get admin session
    local admin_session=$(get_admin_session "project setup")
    if [ $? -ne 0 ]; then
        log_error "Failed to get admin session for setup"
        return 1
    fi
    
    # Create PrivateBox project and add SSH keys
    create_infrastructure_project_with_ssh_key "$admin_session"
}

# Generate VM SSH key pair (for use during setup)
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
        log_error "Failed to generate VM SSH key pair"
        return 1
    fi
    
    # Set secure permissions
    chmod 600 "${vm_key_path}"
    chmod 644 "${vm_key_path}.pub"
    
    # Add public key to debian's authorized_keys
    local admin_home="/home/debian"
    if [ -d "$admin_home" ]; then
        mkdir -p "${admin_home}/.ssh"
        chmod 700 "${admin_home}/.ssh"
        cat "${vm_key_path}.pub" >> "${admin_home}/.ssh/authorized_keys"
        chmod 600 "${admin_home}/.ssh/authorized_keys"
        chown -R debian:debian "${admin_home}/.ssh"
        log_info "Added VM SSH public key to debian's authorized_keys"
    else
        log_warn "debian home directory not found, skipping authorized_keys update"
    fi
    
    log_info "VM SSH key pair generated and added to authorized_keys"
    return 0
}
