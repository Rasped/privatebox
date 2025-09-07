# Semaphore Dynamic Inventories

## Overview

PrivateBox uses **dynamic inventories** created automatically during bootstrap. This ensures the system works on any network configuration, not just 192.168.1.x.

## How It Works

1. **Network Detection** (Phase 1)
   - Bootstrap detects your network automatically (e.g., 192.168.2.x, 10.0.0.x)
   - Saves network configuration to `/tmp/privatebox-config.conf`

2. **Inventory Creation** (Phase 3)
   - Semaphore API creates inventories based on detected network
   - Three main inventories are created:
     - `container-host`: Management VM (detected-network.20)
     - `proxmox`: Proxmox host (detected from current host)
     - `localhost`: For local tasks within Semaphore

3. **Usage in Semaphore**
   - Templates automatically use the correct inventory
   - No hardcoded IPs - everything is dynamic

## Example Inventories

For a network detected as 192.168.2.0/24:

### container-host inventory:
```yaml
all:
  hosts:
    container-host:
      ansible_host: 192.168.2.20  # Dynamically set
      ansible_user: debian
      ansible_become: true
      ansible_become_method: sudo
```

### proxmox inventory:
```yaml
all:
  hosts:
    proxmox:
      ansible_host: 192.168.2.10  # Detected from host
      ansible_user: root
```

## Manual Testing

If you need to run playbooks manually (outside Semaphore), create a temporary inventory:

```bash
# Create dynamic inventory for your network
cat > /tmp/inventory.yml <<EOF
all:
  hosts:
    proxmox:
      ansible_host: $(hostname -I | awk '{print $1}')
      ansible_user: root
EOF

# Use it with ansible-playbook
ansible-playbook -i /tmp/inventory.yml playbook.yml
```

## Why No Static inventory.yml?

- **Network Agnostic**: Works on any network (192.168.1.x, 10.0.0.x, etc.)
- **No Maintenance**: No need to update IPs when network changes
- **Automatic**: Bootstrap handles everything
- **Consistent**: Same process for all deployments

## Viewing Inventories in Semaphore

1. Log into Semaphore UI
2. Navigate to your project
3. Click on "Key Store" → "Inventories"
4. You'll see the dynamically created inventories with correct IPs for your network

## API Access

To get inventory details via API:

```bash
# Login and get cookie
curl -c /tmp/cookies.txt -X POST \
  -H 'Content-Type: application/json' \
  -d '{"auth":"admin","password":"<password>"}' \
  http://<vm-ip>:3000/api/auth/login

# List inventories
curl -b /tmp/cookies.txt \
  http://<vm-ip>:3000/api/project/1/inventory
```

## Troubleshooting

### Wrong IP in Inventory?
- The inventory is created during bootstrap
- If network changed, re-run bootstrap or update via Semaphore UI

### Need to Update an Inventory?
- Use Semaphore UI → Key Store → Edit Inventory
- Or use the API to update programmatically

### Running Playbooks Manually?
- Always create a dynamic inventory based on your current network
- Never hardcode IPs in playbooks or inventories