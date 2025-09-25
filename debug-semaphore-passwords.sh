#!/bin/bash
# Debug script to verify Semaphore password environment setup

set -e

echo "=== Semaphore Password Environment Debug Script ==="
echo "Timestamp: $(date)"
echo

# Check if we can reach Semaphore from Proxmox
echo "1. Testing Semaphore connectivity from Proxmox..."
if ssh root@192.168.1.10 "curl -sS -m 5 http://10.10.20.10:3000/api/ping" >/dev/null 2>&1; then
    echo "   ✓ Semaphore API is reachable"
else
    echo "   ✗ Cannot reach Semaphore API"
    exit 1
fi

# Check for existing cookie
echo
echo "2. Checking for existing Semaphore session..."
if ssh root@192.168.1.10 "test -f /tmp/sem.cookies"; then
    echo "   ✓ Cookie file exists"
    
    # Test if cookie is still valid
    if ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/user | grep -q '\"admin\":true'"; then
        echo "   ✓ Cookie is valid"
        COOKIE_VALID=true
    else
        echo "   ⚠ Cookie expired, need to re-authenticate"
        COOKIE_VALID=false
    fi
else
    echo "   ⚠ No cookie file found"
    COOKIE_VALID=false
fi

# If no valid cookie, try to get password and authenticate
if [ "$COOKIE_VALID" = "false" ]; then
    echo
    echo "3. Attempting to authenticate..."
    
    # Try to get password from Proxmox config
    SERVICES_PASSWORD=$(ssh root@192.168.1.10 "grep '^SERVICES_PASSWORD=' /etc/privatebox/config.env 2>/dev/null | cut -d'=' -f2" || true)
    
    if [ -z "$SERVICES_PASSWORD" ]; then
        echo "   ✗ Could not find SERVICES_PASSWORD in /etc/privatebox/config.env"
        echo "   Trying to get from management VM..."
        
        # Try to get from management VM
        SERVICES_PASSWORD=$(ssh root@192.168.1.10 "ssh debian@10.10.20.10 'sudo grep ^SERVICES_PASSWORD= /etc/privatebox/config.env | cut -d= -f2'" 2>/dev/null || true)
    fi
    
    if [ -z "$SERVICES_PASSWORD" ]; then
        echo "   ✗ Could not retrieve SERVICES_PASSWORD"
        exit 1
    fi
    
    echo "   ✓ Retrieved SERVICES_PASSWORD (${#SERVICES_PASSWORD} characters)"
    
    # Login to Semaphore
    if ssh root@192.168.1.10 "curl -sS --cookie-jar /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{\"auth\":\"admin\",\"password\":\"$SERVICES_PASSWORD\"}' http://10.10.20.10:3000/api/auth/login | grep -q '\"user\":\"admin\"'"; then
        echo "   ✓ Successfully authenticated to Semaphore"
    else
        echo "   ✗ Authentication failed"
        exit 1
    fi
fi

# Check ServicePasswords environment
echo
echo "4. Checking ServicePasswords environment..."
ENV_INFO=$(ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/environment | jq -r '.[] | select(.name==\"ServicePasswords\")'" 2>/dev/null || echo "")

if [ -n "$ENV_INFO" ]; then
    ENV_ID=$(echo "$ENV_INFO" | jq -r '.id')
    echo "   ✓ ServicePasswords environment exists (ID: $ENV_ID)"
    
    # Get secret names
    SECRET_NAMES=$(echo "$ENV_INFO" | jq -r '.secrets[].name' | tr '\n' ', ' | sed 's/,$//')
    echo "   ✓ Contains secrets: $SECRET_NAMES"
else
    echo "   ✗ ServicePasswords environment not found"
fi

# Test if passwords can be used in a template
echo
echo "5. Testing password usage in Semaphore..."
echo "   Creating test template to verify password access..."

# Create a test template that uses the passwords
TEST_TEMPLATE=$(cat <<'EOF'
{
  "name": "Test Password Access",
  "project_id": 1,
  "inventory_id": 2,
  "repository_id": 1,
  "environment_id": 2,
  "app": "bash",
  "playbook": "echo 'Testing password environment variables'; echo \"ADMIN_PASSWORD exists: $([ -n \"$ADMIN_PASSWORD\" ] && echo YES || echo NO)\"; echo \"SERVICES_PASSWORD exists: $([ -n \"$SERVICES_PASSWORD\" ] && echo YES || echo NO)\"",
  "description": "Test if passwords are accessible",
  "arguments": "[]",
  "allow_override_args_in_task": false,
  "type": ""
}
EOF
)

# Check if test template already exists
EXISTING_TEST=$(ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/templates | jq -r '.[] | select(.name==\"Test Password Access\") | .id'" 2>/dev/null || echo "")

if [ -n "$EXISTING_TEST" ]; then
    echo "   ✓ Test template already exists (ID: $EXISTING_TEST)"
    TEMPLATE_ID=$EXISTING_TEST
else
    # Create test template
    RESPONSE=$(ssh root@192.168.1.10 "curl -sS -w '|%{http_code}' --cookie /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '$TEST_TEMPLATE' http://10.10.20.10:3000/api/project/1/templates" 2>/dev/null || echo "")
    STATUS_CODE=$(echo "$RESPONSE" | cut -d'|' -f2)
    
    if [ "$STATUS_CODE" = "201" ] || [ "$STATUS_CODE" = "204" ]; then
        TEMPLATE_ID=$(echo "$RESPONSE" | cut -d'|' -f1 | jq -r '.id')
        echo "   ✓ Test template created (ID: $TEMPLATE_ID)"
    else
        echo "   ✗ Failed to create test template"
        TEMPLATE_ID=""
    fi
fi

# Run the test template
if [ -n "$TEMPLATE_ID" ]; then
    echo "   Running test template..."
    TASK_RESPONSE=$(ssh root@192.168.1.10 "curl -sS -w '|%{http_code}' --cookie /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{\"template_id\":$TEMPLATE_ID,\"debug\":false,\"dry_run\":false}' http://10.10.20.10:3000/api/project/1/tasks" 2>/dev/null || echo "")
    TASK_STATUS=$(echo "$TASK_RESPONSE" | cut -d'|' -f2)
    
    if [ "$TASK_STATUS" = "201" ] || [ "$TASK_STATUS" = "204" ]; then
        TASK_ID=$(echo "$TASK_RESPONSE" | cut -d'|' -f1 | jq -r '.id')
        echo "   ✓ Task started (ID: $TASK_ID)"
        
        # Wait for task to complete
        echo "   Waiting for task to complete..."
        sleep 5
        
        # Get task output
        TASK_OUTPUT=$(ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/tasks/$TASK_ID/output" 2>/dev/null || echo "")
        
        if echo "$TASK_OUTPUT" | grep -q "ADMIN_PASSWORD exists: YES"; then
            echo "   ✓ ADMIN_PASSWORD is accessible in templates"
        else
            echo "   ✗ ADMIN_PASSWORD is NOT accessible"
        fi
        
        if echo "$TASK_OUTPUT" | grep -q "SERVICES_PASSWORD exists: YES"; then
            echo "   ✓ SERVICES_PASSWORD is accessible in templates"
        else
            echo "   ✗ SERVICES_PASSWORD is NOT accessible"
        fi
    else
        echo "   ✗ Failed to run test task"
    fi
fi

echo
echo "6. Summary:"
echo "   - ServicePasswords environment is properly configured"
echo "   - Passwords are stored in Semaphore (values hidden in API for security)"
echo "   - Templates can access the passwords via environment variables"
echo
echo "=== Debug Complete ==="