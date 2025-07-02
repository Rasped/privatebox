# Network Discovery Integration Test

This document contains all commands to test the network discovery integration from start to finish.

## Test Environment
- Proxmox Host: 192.168.1.10
- Expected Network: 192.168.1.0/24
- Expected Gateway: 192.168.1.3

## Step 1: Copy Bootstrap to Test Server

```bash
# Copy the entire bootstrap directory to the test server
rsync -avz --delete /Users/rasped/Privatebox/bootstrap/ root@192.168.1.10:/tmp/privatebox-bootstrap-test/

# Make all scripts executable
ssh root@192.168.1.10 "chmod +x /tmp/privatebox-bootstrap-test/scripts/*.sh"
```

## Step 2: Test Network Discovery Standalone

```bash
# Test network discovery in dry-run mode
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-test && ./scripts/network-discovery.sh --auto --dry-run"

# Test network discovery for real (generates config)
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-test && rm -f config/privatebox.conf && ./scripts/network-discovery.sh --auto"

# Verify generated configuration
ssh root@192.168.1.10 "cat /tmp/privatebox-bootstrap-test/config/privatebox.conf | grep -E 'STATIC_IP|GATEWAY|NET_BRIDGE|PROXMOX_HOST'"
```

## Step 3: Test VM Creation with Auto-Discovery

```bash
# Clean up any existing VM 9000
ssh root@192.168.1.10 "qm stop 9000 2>/dev/null; qm destroy 9000 2>/dev/null"

# Test with auto-discovery flag (removes existing config first)
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-test && rm -f config/privatebox.conf && ./scripts/create-ubuntu-vm.sh --auto-discover"
```

## Step 4: Verify VM Creation

```bash
# Check VM status
ssh root@192.168.1.10 "qm status 9000"

# Check VM configuration
ssh root@192.168.1.10 "qm config 9000 | grep -E 'ipconfig0|memory|cores'"

# List running VMs
ssh root@192.168.1.10 "qm list | grep 9000"
```

## Step 5: Test Without Config File (Should Auto-Discover)

```bash
# Clean up for fresh test
ssh root@192.168.1.10 "qm stop 9000 2>/dev/null; qm destroy 9000 2>/dev/null"

# Remove config to test automatic discovery
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-test && rm -f config/privatebox.conf"

# Run without flags - should auto-discover
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-test && ./scripts/create-ubuntu-vm.sh"
```

## Step 6: Test with Existing Config (Should Use Config)

```bash
# Create custom config
ssh root@192.168.1.10 "cat > /tmp/privatebox-bootstrap-test/config/privatebox.conf << 'EOF'
VMID=9000
UBUNTU_VERSION=\"24.04\"
VM_USERNAME=\"ubuntuadmin\"
VM_PASSWORD=\"Changeme123\"
VM_MEMORY=4096
VM_CORES=2
STATIC_IP=\"192.168.1.25\"
GATEWAY=\"192.168.1.3\"
NET_BRIDGE=\"vmbr0\"
NETMASK=\"24\"
STORAGE=\"local-lvm\"
VM_DISK_SIZE=\"40G\"
PROXMOX_HOST=\"192.168.1.10\"
EOF"

# Run with existing config - should use IP .25
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-test && ./scripts/create-ubuntu-vm.sh"
```

## Expected Results

### Network Discovery Output
- Should detect vmbr0 interface
- Should find available IP (likely 192.168.1.20)
- Should detect gateway 192.168.1.3
- Should save complete privatebox.conf

### VM Creation
- VM ID 9000 created successfully
- Network configured with discovered settings
- Services accessible at discovered IP

## Troubleshooting Commands

```bash
# Check logs
ssh root@192.168.1.10 "tail -f /tmp/privatebox-bootstrap-test/vm_creation_9000.log"

# Debug network discovery
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-test && LOG_LEVEL=DEBUG ./scripts/network-discovery.sh --auto --debug"

# Check generated cloud-init
ssh root@192.168.1.10 "cat /var/lib/vz/snippets/user-data-9000.yaml"

# Access VM console if needed
ssh root@192.168.1.10 "qm terminal 9000"
```

## Cleanup

```bash
# Remove test VM
ssh root@192.168.1.10 "qm stop 9000; qm destroy 9000"

# Remove test directory
ssh root@192.168.1.10 "rm -rf /tmp/privatebox-bootstrap-test"
```