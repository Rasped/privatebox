#!/bin/bash
# Test script to verify Proxmox discovery functionality

echo "=== Testing Proxmox Discovery ==="

# Source the common library for logging functions
if [[ -f "./bootstrap/lib/common.sh" ]]; then
    source "./bootstrap/lib/common.sh"
else
    # Simple logging fallback
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

# Copy the discover_proxmox_host function from initial-setup.sh
discover_proxmox_host() {
    log_info "Attempting to discover Proxmox host IP..."
    
    # Get the VM's default gateway as the most likely Proxmox host IP
    local gateway_ip=$(ip route | grep default | awk '{print $3}' | head -n1)
    
    if [[ -z "$gateway_ip" ]]; then
        log_warn "Unable to determine default gateway IP"
        return 1
    fi
    
    log_info "Checking if $gateway_ip is a Proxmox host (port 8006)..."
    
    # Use timeout and nc to check if port 8006 is open
    if timeout 5 nc -z "$gateway_ip" 8006 2>/dev/null; then
        log_info "Found Proxmox web interface on $gateway_ip:8006"
        
        # Double-check by trying to fetch the Proxmox API endpoint
        if curl -k -s --connect-timeout 5 "https://$gateway_ip:8006/api2/json" >/dev/null 2>&1; then
            log_info "Confirmed: Proxmox host discovered at $gateway_ip"
            
            # Store the discovered IP
            echo "$gateway_ip" > /tmp/test-proxmox-host
            chmod 644 /tmp/test-proxmox-host
            
            log_success "Proxmox host IP saved to /tmp/test-proxmox-host"
            return 0
        fi
    fi
    
    # If gateway isn't Proxmox, scan the local network
    log_info "Gateway is not Proxmox host, scanning local network..."
    
    # Get network prefix (assuming /24 for simplicity)
    local network_prefix=$(echo "$gateway_ip" | cut -d. -f1-3)
    
    # Scan common Proxmox IPs in the network
    for i in {1..254}; do
        local test_ip="${network_prefix}.$i"
        
        # Skip if it's our own IP
        if ip addr show | grep -q "$test_ip"; then
            continue
        fi
        
        # Check if port 8006 is open (with very short timeout)
        if timeout 1 nc -z "$test_ip" 8006 2>/dev/null; then
            log_info "Found potential Proxmox host at $test_ip, verifying..."
            
            # Verify it's actually Proxmox
            if curl -k -s --connect-timeout 2 "https://$test_ip:8006/api2/json" >/dev/null 2>&1; then
                log_info "Confirmed: Proxmox host discovered at $test_ip"
                
                # Store the discovered IP
                echo "$test_ip" > /tmp/test-proxmox-host
                chmod 644 /tmp/test-proxmox-host
                
                log_success "Proxmox host IP saved to /tmp/test-proxmox-host"
                return 0
            fi
        fi
    done
    
    log_warn "Unable to discover Proxmox host automatically"
    log_info "You can manually create /etc/privatebox-proxmox-host with the Proxmox IP"
    return 1
}

# Run the test
echo "Testing discovery function..."
discover_proxmox_host

if [[ -f /tmp/test-proxmox-host ]]; then
    echo ""
    echo "Discovery result: $(cat /tmp/test-proxmox-host)"
    rm -f /tmp/test-proxmox-host
else
    echo ""
    echo "Discovery failed - no Proxmox host found"
fi

echo ""
echo "=== Test Complete ==="