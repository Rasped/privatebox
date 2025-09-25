#!/bin/bash
# DNS Stack Validation Script
# Validates OPNsense Unbound and AdGuard DNS services

set -euo pipefail

echo "=== DNS Stack Validation ==="
echo "Time: $(date)"
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
OPNSENSE_IP="10.10.20.1"
OPNSENSE_PORT="5353"
ADGUARD_IP="10.10.20.10"
ADGUARD_PORT="53"
TEST_DOMAIN="google.com"
BLOCKED_DOMAIN="doubleclick.net"

# Function to check port connectivity
check_port() {
    local host=$1
    local port=$2
    local service=$3

    echo -n "Testing $service on $host:$port... "
    if timeout 2 nc -zv $host $port >/dev/null 2>&1; then
        echo -e "${GREEN}✓ LISTENING${NC}"
        return 0
    else
        echo -e "${RED}✗ NOT LISTENING${NC}"
        return 1
    fi
}

# Function to test DNS resolution
test_dns() {
    local server=$1
    local port=$2
    local domain=$3
    local service=$4

    echo -n "  DNS resolution test ($domain)... "
    if timeout 3 dig @$server -p $port $domain +short >/dev/null 2>&1; then
        local result=$(dig @$server -p $port $domain +short 2>/dev/null | head -1)
        if [ -n "$result" ]; then
            echo -e "${GREEN}✓ WORKING${NC} (resolved to: $result)"
            return 0
        else
            echo -e "${YELLOW}⚠ NO RESULT${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ FAILED${NC}"
        return 1
    fi
}

# Main validation
echo "1. OPNsense Unbound DNS Service"
echo "---------------------------------"
if check_port $OPNSENSE_IP $OPNSENSE_PORT "Unbound"; then
    test_dns $OPNSENSE_IP $OPNSENSE_PORT $TEST_DOMAIN "Unbound"

    # Additional Unbound checks from Proxmox
    echo -n "  Checking Unbound service status... "
    if ssh root@192.168.1.10 "ssh -i /root/.credentials/opnsense/id_ed25519 -o StrictHostKeyChecking=no root@$OPNSENSE_IP 'configctl unbound status'" 2>/dev/null | grep -q "is running"; then
        echo -e "${GREEN}✓ SERVICE RUNNING${NC}"
    else
        echo -e "${RED}✗ SERVICE NOT RUNNING${NC}"
    fi
fi
echo

echo "2. AdGuard Home DNS Service"
echo "----------------------------"
if check_port $ADGUARD_IP $ADGUARD_PORT "AdGuard"; then
    test_dns $ADGUARD_IP $ADGUARD_PORT $TEST_DOMAIN "AdGuard"

    # Test ad blocking
    echo -n "  Ad blocking test ($BLOCKED_DOMAIN)... "
    BLOCKED_RESULT=$(dig @$ADGUARD_IP -p $ADGUARD_PORT $BLOCKED_DOMAIN +short 2>/dev/null || echo "ERROR")
    if [[ "$BLOCKED_RESULT" == "0.0.0.0" ]] || [[ -z "$BLOCKED_RESULT" ]]; then
        echo -e "${GREEN}✓ BLOCKED${NC}"
    elif [[ "$BLOCKED_RESULT" == "ERROR" ]]; then
        echo -e "${RED}✗ DNS ERROR${NC}"
    else
        echo -e "${YELLOW}⚠ NOT BLOCKED${NC} (resolved to: $BLOCKED_RESULT)"
    fi
fi
echo

echo "3. Service Connectivity Tests"
echo "------------------------------"

# Test AdGuard to Unbound connectivity
echo -n "AdGuard → Unbound connectivity... "
if ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://$ADGUARD_IP:3000/api/user" 2>/dev/null | grep -q "admin"; then
    # From management VM perspective
    if ssh root@192.168.1.10 "ssh debian@$ADGUARD_IP 'nc -zv $OPNSENSE_IP $OPNSENSE_PORT'" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ CONNECTED${NC}"
    else
        echo -e "${RED}✗ NOT REACHABLE${NC}"
    fi
else
    # Direct test from Proxmox
    if ssh root@192.168.1.10 "nc -zv $OPNSENSE_IP $OPNSENSE_PORT" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ REACHABLE FROM PROXMOX${NC} (but not tested from AdGuard VM)"
    else
        echo -e "${RED}✗ NOT REACHABLE${NC}"
    fi
fi

# Check if old port 53 is still in use on OPNsense
echo -n "OPNsense port 53 status... "
if timeout 2 nc -zv $OPNSENSE_IP 53 >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ STILL LISTENING${NC} (should be free for other services)"
else
    echo -e "${GREEN}✓ NOT IN USE${NC} (as expected)"
fi
echo

echo "4. Configuration Verification"
echo "------------------------------"

# Check OPNsense config
echo -n "OPNsense config.xml port setting... "
CONFIG_PORT=$(ssh root@192.168.1.10 "ssh -i /root/.credentials/opnsense/id_ed25519 -o StrictHostKeyChecking=no root@$OPNSENSE_IP 'grep -A5 unboundplus /conf/config.xml | grep port | head -1'" 2>/dev/null | sed 's/.*<port>//;s/<\/port>.*//' | tr -d ' ')
if [[ "$CONFIG_PORT" == "$OPNSENSE_PORT" ]]; then
    echo -e "${GREEN}✓ CORRECT${NC} (port $OPNSENSE_PORT)"
else
    echo -e "${RED}✗ INCORRECT${NC} (found port $CONFIG_PORT, expected $OPNSENSE_PORT)"
fi

# Check for legacy unbound section
echo -n "Legacy <unbound> section... "
if ssh root@192.168.1.10 "ssh -i /root/.credentials/opnsense/id_ed25519 -o StrictHostKeyChecking=no root@$OPNSENSE_IP 'grep -q \"<unbound>\" /conf/config.xml'" 2>/dev/null; then
    echo -e "${YELLOW}⚠ PRESENT${NC} (should be removed)"
else
    echo -e "${GREEN}✓ NOT FOUND${NC} (clean config)"
fi
echo

echo "5. Summary"
echo "----------"
ISSUES=0

# Count issues
if ! timeout 2 nc -zv $OPNSENSE_IP $OPNSENSE_PORT >/dev/null 2>&1; then
    echo -e "${RED}✗ Critical: Unbound not listening on port $OPNSENSE_PORT${NC}"
    ((ISSUES++))
fi

if ! timeout 2 nc -zv $ADGUARD_IP $ADGUARD_PORT >/dev/null 2>&1; then
    echo -e "${RED}✗ Critical: AdGuard not listening on port $ADGUARD_PORT${NC}"
    ((ISSUES++))
fi

if timeout 2 nc -zv $OPNSENSE_IP 53 >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Warning: OPNsense still using port 53${NC}"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! DNS stack is properly configured.${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ISSUES issue(s) that need attention.${NC}"
    exit 1
fi