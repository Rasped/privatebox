#!/bin/bash
# Semaphore API interaction library

# Global variable for automation user password
AUTOMATION_USER_PASSWORD=""

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
    
    # Get VM IP dynamically
    local vm_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$vm_ip" ]]; then
        vm_ip="${STATIC_IP:-192.168.1.20}"
    fi
    
    log_info "Creating SemaphoreAPI environment for project $project_id..." >&2
    log_info "API Token (FULL): $api_token" >&2
    
    # Create environment payload - Semaphore stores variables and secrets separately
    # The json field expects a JSON string, not an object
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
    
    log_info "Creating Generate Templates task..." >&2
    log_info "Project ID: $project_id, Repository ID: $repository_id, Inventory ID: $inventory_id, Environment ID: $environment_id" >&2
    
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
    
    log_info "Template payload: $(echo "$template_payload" | jq -c .)" >&2
    
    local api_result=$(make_api_request "POST" \
        "http://localhost:3000/api/project/$project_id/templates" \
        "$template_payload" "$admin_session" "Creating template generator task")
    
    if [ $? -ne 0 ]; then
        log_error "API request failed for template creation"
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    log_info "Template creation response - Status: $status_code" >&2
    
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
    local inv_id=$(get_inventory_id_by_name "http://localhost:3000" "$admin_session" "$project_id" "container-host")
    
    if [ -z "$repo_id" ]; then
        log_error "❌ Failed to find PrivateBox repository"
        log_info "Template sync setup FAILED at step 3 - repository not found"
        return 1
    fi
    if [ -z "$inv_id" ]; then
        log_error "❌ Failed to find container-host inventory"
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
}

# Ensure required tools are installed
ensure_semaphore_tools() {
    if ! command -v jq &> /dev/null; then
        log_info "Installing required tools..."
        if command -v dnf &> /dev/null; then
            dnf install -y jq curl
        elif command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y jq curl sshpass
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

# Get SSH key ID by name
get_ssh_key_id_by_name() {
    local project_id="$1"
    local key_name="$2"
    local admin_session="$3"
    
    log_info "Looking up SSH key '$key_name' in project $project_id..." >&2
    
    local api_result=$(make_api_request "GET" \
        "http://localhost:3000/api/project/$project_id/keys" "" "$admin_session" "Getting SSH keys")
    
    if [ $? -eq 0 ]; then
        local status_code=$(echo "$api_result" | cut -d'|' -f1)
        local keys=$(echo "$api_result" | cut -d'|' -f2-)
        
        if [ "$status_code" -eq 200 ]; then
            local key_id=$(echo "$keys" | jq -r ".[] | select(.name==\"$key_name\") | .id" 2>/dev/null)
            if [ -n "$key_id" ] && [ "$key_id" != "null" ]; then
                log_info "Found SSH key '$key_name' with ID: $key_id" >&2
                echo "$key_id"
            else
                log_info "WARNING: SSH key '$key_name' not found in project" >&2
            fi
        else
            log_error "Failed to list SSH keys. Status: $status_code"
        fi
    else
        log_error "Failed to get SSH keys list"
    fi
}

# Create default inventory for a project
create_inventory() {
    local project_id="$1"
    local admin_session="$2"
    local inventory_name="$3"
    local inventory_content="$4"
    local ssh_key_id="$5"
    
    log_info "Creating inventory: $inventory_name"
    
    # Build the inventory payload
    local inventory_payload=$(jq -n \
        --arg name "$inventory_name" \
        --arg type "static" \
        --argjson pid "$project_id" \
        --arg inv "$inventory_content" \
        --argjson ssh_key_id "$ssh_key_id" \
        '{name: $name, type: $type, project_id: $pid, inventory: $inv, ssh_key_id: $ssh_key_id}')
    
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/project/$project_id/inventory" "$inventory_payload" "$admin_session" "Creating $inventory_name")
    if [ $? -ne 0 ]; then
        log_error "Failed to create $inventory_name"
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local inv_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        log_info "$inventory_name created successfully (ID: $inv_id)"
        return 0
    else
        log_error "Failed to create $inventory_name. Status: $status_code"
        return 1
    fi
}

create_default_inventory() {
    local project_name="$1"
    local project_id="$2"
    local admin_session="$3"
    local vm_ssh_key_id="${4:-}"  # VM SSH key ID
    
    log_info "Creating inventories for project '$project_name'..."
    
    # Get the VM IP address dynamically
    local vm_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$vm_ip" ]]; then
        # Fallback to configured IP if hostname -I fails
        vm_ip="${STATIC_IP:-192.168.1.20}"
    fi
    log_info "Using VM IP: $vm_ip"
    
    # Create VM inventory first
    if [ -n "$vm_ssh_key_id" ] && [[ "$vm_ssh_key_id" =~ ^[0-9]+$ ]]; then
        local vm_inventory="all:
  hosts:
    container-host:
      ansible_host: ${vm_ip}
      ansible_user: ubuntuadmin
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
            
            # Get the Proxmox SSH key ID (should be key ID 2 based on earlier creation)
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

# Function to create SSH key in Semaphore via API
create_semaphore_ssh_key() {
    local project_id="$1"
    local key_name="$2"
    local key_type="${3:-ssh}"  # Default to ssh type
    local admin_session="${4:-}"  # Optional parameter
    local key_path="${5:-$SSH_PRIVATE_KEY_PATH}"  # Use provided path or default
    local ssh_login="${6:-root}"  # SSH login user (default: root)
    
    log_info "Creating SSH key '$key_name' for project ID $project_id (login: $ssh_login)..." >&2
    
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
        log_info "ERROR: SSH private key not found at $key_path" >&2
        return 1
    fi
    
    private_key_content=$(cat "$key_path")
    if [ -z "$private_key_content" ]; then
        log_info "ERROR: Failed to read SSH private key content" >&2
        return 1
    fi
    
    # Create SSH key payload for Semaphore API
    # SSH keys require a nested ssh object with login, passphrase, and private_key fields
    # Use rawfile for proper multiline string handling
    local ssh_key_payload=$(jq -n \
        --arg name "$key_name" \
        --arg type "$key_type" \
        --arg login "$ssh_login" \
        --rawfile private_key "$key_path" \
        --argjson pid "$project_id" \
        '{name: $name, type: $type, project_id: $pid, ssh: {login: $login, passphrase: "", private_key: $private_key}}')
    
    # Debug logging
    log_info "DEBUG: SSH private key path: $key_path" >&2
    log_info "DEBUG: Private key content length: ${#private_key_content}" >&2
    log_info "DEBUG: First 50 chars of key: ${private_key_content:0:50}..." >&2
    log_info "DEBUG: Payload preview: $(echo "$ssh_key_payload" | jq -c '{name, type, project_id, ssh: {login: .ssh.login, passphrase: .ssh.passphrase, private_key: (.ssh.private_key | .[0:50] + "...")}}')" >&2
    
    log_info "Sending SSH key to Semaphore API..." >&2
    local api_result=$(make_api_request "POST" "http://localhost:3000/api/project/$project_id/keys" "$ssh_key_payload" "$admin_session" "Creating SSH key $key_name")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local status_code=$(echo "$api_result" | cut -d'|' -f1)
    local response_body=$(echo "$api_result" | cut -d'|' -f2-)
    
    if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 200 ]; then
        local key_id=$(echo "$response_body" | jq -r '.id' 2>/dev/null)
        if [ -n "$key_id" ] && [ "$key_id" != "null" ]; then
            log_info "SSH key '$key_name' created successfully with ID: $key_id" >&2
            # Store the key ID for potential later use
            echo "SSH Key ID: $key_id" >> /root/.credentials/semaphore_credentials.txt
            # Return the key ID
            echo "$key_id"
        else
            log_info "SSH key '$key_name' created successfully" >&2
        fi
        return 0
    elif [ -n "$response_body" ] && (echo "$response_body" | jq -e '.error' 2>/dev/null | grep -q "already exists" || \
         echo "$response_body" | jq -e '.message' 2>/dev/null | grep -q "already exists"); then
        log_info "SSH key '$key_name' already exists. Looking up ID..." >&2
        # Get the existing key ID
        local existing_id=$(get_ssh_key_id_by_name "$project_id" "$key_name" "$admin_session")
        if [ -n "$existing_id" ]; then
            echo "$existing_id"
        fi
        return 0
    else
        log_info "ERROR: Failed to create SSH key '$key_name'. Status: $status_code" >&2
        if [ -n "$response_body" ]; then
            log_info "Response body: $response_body" >&2
            local error_message=$(echo "$response_body" | jq -r '.error // .message // "Unknown error"' 2>/dev/null)
            if [ "$error_message" != "null" ] && [ -n "$error_message" ]; then
                log_info "Error details: $error_message" >&2
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
            
            # Create SSH key for this project first (before inventory)
            local proxmox_key_id=""
            if [ -f "/root/.credentials/proxmox_ssh_key" ]; then
                proxmox_key_id=$(create_semaphore_ssh_key "$project_id" "proxmox" "ssh" "$admin_session" "/root/.credentials/proxmox_ssh_key" "root")
                
                # Delete the Proxmox SSH key from VM for security after uploading to Semaphore
                if [ -n "$proxmox_key_id" ] && [ "$proxmox_key_id" != "null" ]; then
                    log_info "Removing Proxmox SSH key from filesystem for security..."
                    rm -f /root/.credentials/proxmox_ssh_key
                    log_info "✓ Proxmox SSH key removed from VM filesystem"
                else
                    log_info "WARNING: Failed to upload Proxmox key to Semaphore, keeping key file"
                fi
            else
                log_info "WARNING: Proxmox SSH key not found at /root/.credentials/proxmox_ssh_key - skipping Proxmox SSH key creation"
            fi
            
            # Create SSH key for VM self-management (with ubuntuadmin as the SSH user)
            local vm_key_id=""
            if [ -f "/root/.credentials/semaphore_vm_key" ]; then
                vm_key_id=$(create_semaphore_ssh_key "$project_id" "container-host" "ssh" "$admin_session" "/root/.credentials/semaphore_vm_key" "ubuntuadmin")
            else
                log_info "WARNING: VM SSH key not found at /root/.credentials/semaphore_vm_key - skipping VM SSH key creation"
            fi
            
            # Debug: Log the captured key ID
            log_info "DEBUG: Captured VM SSH key ID: '$vm_key_id'" >&2
            
            # Create default inventory with the VM SSH key
            if [ -n "$vm_key_id" ] && [[ "$vm_key_id" =~ ^[0-9]+$ ]]; then
                log_info "Creating inventory with SSH key ID: $vm_key_id" >&2
                create_default_inventory "$project_name" "$project_id" "$admin_session" "$vm_key_id"
            else
                log_info "WARNING: Invalid or missing VM SSH key ID (captured: '$vm_key_id'), creating inventory without SSH key association" >&2
                create_default_inventory "$project_name" "$project_id" "$admin_session"
            fi
            
            # Create repository for the project
            if ! create_repository "$project_id" "PrivateBox" "$PRIVATEBOX_GIT_URL" "$admin_session"; then
                log_error "Failed to create PrivateBox repository - template sync will not work"
                # Continue anyway to set up other components
            fi
            
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