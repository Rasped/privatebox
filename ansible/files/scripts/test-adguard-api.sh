#!/bin/bash
#
# AdGuard Home API Test Script
# Tests various AdGuard API endpoints to verify functionality
#

set -euo pipefail

# Configuration
ADGUARD_HOST="${1:-localhost}"
ADGUARD_PORT="${2:-8080}"
ADGUARD_USER="${3:-admin}"
ADGUARD_PASS="${4:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "success")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "error")
            echo -e "${RED}✗${NC} $message"
            ;;
        "info")
            echo -e "${YELLOW}ℹ${NC} $message"
            ;;
    esac
}

# Function to test an endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3
    local expected_codes=$4
    local auth_required=${5:-false}
    local data=${6:-}
    
    echo ""
    print_info "Testing: $description"
    print_info "Endpoint: $method $endpoint"
    
    local curl_args="-s -w '\nHTTP_CODE:%{http_code}' -X $method"
    local url="http://${ADGUARD_HOST}:${ADGUARD_PORT}${endpoint}"
    
    # Add authentication if required
    if [ "$auth_required" = "true" ] && [ -n "$ADGUARD_PASS" ]; then
        curl_args="$curl_args -u ${ADGUARD_USER}:${ADGUARD_PASS}"
    fi
    
    # Add data if provided
    if [ -n "$data" ]; then
        curl_args="$curl_args -H 'Content-Type: application/json' -d '$data'"
    fi
    
    # Execute curl and capture output
    local response
    response=$(eval "curl $curl_args '$url'" 2>&1) || true
    
    # Extract HTTP code
    local http_code
    http_code=$(echo "$response" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
    
    # Remove HTTP code from response
    local body
    body=$(echo "$response" | sed '/HTTP_CODE:/d')
    
    # Check if code is expected
    if [[ " $expected_codes " =~ " $http_code " ]]; then
        print_status "success" "Got expected HTTP code: $http_code"
        if [ -n "$body" ]; then
            echo "Response body (truncated):"
            echo "$body" | head -5
        fi
    else
        print_status "error" "Unexpected HTTP code: $http_code (expected: $expected_codes)"
        if [ -n "$body" ]; then
            echo "Error response:"
            echo "$body"
        fi
    fi
}

# Main test sequence
echo "=========================================="
echo "AdGuard Home API Test Script"
echo "=========================================="
print_info "Host: ${ADGUARD_HOST}:${ADGUARD_PORT}"

# Test 1: Check if AdGuard is accessible
test_endpoint "GET" "/" "Basic connectivity" "200 302" false

# Test 2: Check status endpoint (pre-configuration)
test_endpoint "GET" "/control/status" "Status endpoint" "200 302" false

# Test 3: Check if configuration is needed
echo ""
print_info "Checking if AdGuard needs initial configuration..."
status_response=$(curl -s -L "http://${ADGUARD_HOST}:${ADGUARD_PORT}/control/status" 2>&1) || true

if [[ "$status_response" =~ "install.html" ]] || [[ "$status_response" == "" ]]; then
    print_status "info" "AdGuard needs initial configuration"
    
    # Test 4: Check configuration endpoint
    test_endpoint "POST" "/control/install/check_config" \
        "Configuration check" \
        "200" \
        false \
        '{"web":{"port":8080,"ip":"0.0.0.0"},"dns":{"port":53,"ip":"0.0.0.0","autofix":false},"set_static_ip":false}'
    
    # Test 5: Get installation addresses
    test_endpoint "GET" "/control/install/get_addresses" \
        "Get available addresses" \
        "200" \
        false
else
    print_status "info" "AdGuard is already configured"
    
    # Test authenticated endpoints
    if [ -z "$ADGUARD_PASS" ]; then
        print_status "error" "Password required for authenticated endpoints"
        print_info "Usage: $0 <host> <port> <username> <password>"
    else
        # Test 6: Check protection status
        test_endpoint "GET" "/control/protection/status" \
            "Protection status" \
            "200" \
            true
        
        # Test 7: Check DNS info
        test_endpoint "GET" "/control/dns_info" \
            "DNS configuration" \
            "200" \
            true
        
        # Test 8: Check filtering status
        test_endpoint "GET" "/control/filtering/status" \
            "Filtering status" \
            "200" \
            true
        
        # Test 9: Check stats
        test_endpoint "GET" "/control/stats" \
            "Statistics" \
            "200" \
            true
    fi
fi

echo ""
echo "=========================================="
print_status "info" "Test complete"
echo "=========================================="