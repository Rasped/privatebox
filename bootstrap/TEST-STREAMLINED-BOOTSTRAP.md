# Streamlined Bootstrap Test Instructions

This document contains the exact steps to test the new streamlined bootstrap process.

## Test Environment
- Proxmox Host: 192.168.1.10

## Complete Test Process

### Step 1: Clean up any existing test
```bash
ssh root@192.168.1.10 "qm stop 9000 2>/dev/null; qm destroy 9000 2>/dev/null"
```

### Step 2: Copy bootstrap folder to test server
```bash
rsync -avz /Users/rasped/Privatebox/bootstrap/ root@192.168.1.10:/tmp/privatebox-bootstrap-final/
```

### Step 3: Make bootstrap.sh executable and run it
```bash
ssh root@192.168.1.10 "cd /tmp/privatebox-bootstrap-final && chmod +x bootstrap.sh && ./bootstrap.sh"
```

## Expected Behavior

The bootstrap.sh script will:

1. **Make all scripts executable** automatically
2. **Run network discovery** to detect:
   - Network interface (vmbr0)
   - Available IP address
   - Gateway
3. **Create the VM** with discovered settings
4. **Wait for cloud-init** to complete (5-10 minutes)
   - Shows progress updates every 60 seconds
   - Waits for SSH to be available
   - Waits for completion marker file
   - Verifies services are running
5. **Display access information** when complete

## What to Monitor

During the process, you should see:
- Network discovery finding an available IP
- VM creation progress
- "Waiting for SSH to become available..."
- "Waiting for cloud-init to finish configuration..."
- Progress updates every 60 seconds
- Final success message with access details

## Success Criteria

The test is successful when:
- Script completes without errors
- Shows "All services are running successfully!"
- Displays access information
- You can access Portainer at http://<IP>:9000
- You can access Semaphore at http://<IP>:3000

## Troubleshooting

If the script fails:
```bash
# Check VM console
ssh root@192.168.1.10 "qm terminal 9000"

# Check if VM is running
ssh root@192.168.1.10 "qm status 9000"

# Check cloud-init logs (from VM)
ssh ubuntuadmin@<VM_IP> "sudo cloud-init status --long"
ssh ubuntuadmin@<VM_IP> "sudo journalctl -u cloud-init"

# Check for completion marker
ssh ubuntuadmin@<VM_IP> "cat /etc/privatebox-cloud-init-complete"
```

## Cleanup After Test
```bash
ssh root@192.168.1.10 "qm stop 9000 && qm destroy 9000"
ssh root@192.168.1.10 "rm -rf /tmp/privatebox-bootstrap-final"
```