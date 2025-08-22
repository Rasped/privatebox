# Proxmox API Integration Flow

## Current Integration Status

The Proxmox API token system is now integrated into the PrivateBox bootstrap flow with optional automatic setup.

## Integration Points

### 1. Bootstrap Script Enhancement
- `bootstrap.sh --setup-proxmox-api` - New option to create API tokens on Proxmox host
- Runs `scripts/setup-proxmox-api-token.sh` when invoked
- Creates token and saves to `/root/.proxmox-api-token`

### 2. Guest Setup Integration
- `setup-guest.sh` now checks for `/root/.proxmox-api-token` during VM setup
- If found, automatically runs `register-proxmox-api.sh`
- Registers ProxmoxAPI environment in Semaphore
- No manual intervention required if token file exists

### 3. File Transfer Methods

#### Option A: Manual Transfer (Recommended for security)
```bash
# After running on Proxmox host:
./bootstrap.sh --setup-proxmox-api

# Transfer token to VM:
scp /root/.proxmox-api-token debian@192.168.1.20:/tmp/
ssh debian@192.168.1.20 'sudo mv /tmp/.proxmox-api-token /root/'

# Re-run setup or manually register:
sudo /opt/privatebox/scripts/register-proxmox-api.sh
```

#### Option B: Automated Transfer (Future enhancement)
Could add to bootstrap flow:
- Copy token file during VM creation via cloud-init
- Or use Ansible to transfer after VM is up
- Security consideration: token in cloud-init user-data

## Complete Workflow

### Standard Flow (Without API)
1. Run `bootstrap.sh` on Proxmox
2. VM created with cloud-init
3. Services installed (Portainer, Semaphore)
4. Semaphore API configured
5. **Manual**: Create API token later if needed

### Enhanced Flow (With API)
1. Run `bootstrap.sh --setup-proxmox-api` first
2. Token created and saved
3. Run normal `bootstrap.sh`
4. VM created with cloud-init
5. Services installed
6. **Automatic**: If token file exists, registers in Semaphore

### Post-Bootstrap Addition
If you didn't set up API token initially:
```bash
# On Proxmox:
./bootstrap.sh --setup-proxmox-api

# On VM:
sudo /opt/privatebox/scripts/register-proxmox-api.sh
# Enter token details manually
```

## Files Involved

### Bootstrap Files
- `bootstrap/bootstrap.sh` - Main orchestrator with --setup-proxmox-api option
- `bootstrap/setup-guest.sh` - Guest configuration, now checks for API token
- `bootstrap/scripts/setup-proxmox-api-token.sh` - Creates Proxmox API token
- `bootstrap/scripts/register-proxmox-api.sh` - Registers in Semaphore

### Configuration Files
- `/root/.proxmox-api-token` - Token storage on Proxmox (mode 600)
- `/tmp/proxmox-api-env.json` - Temporary Semaphore config

### Ansible Integration
- Playbooks can use the ProxmoxAPI environment for VM operations

## Environment Variables

Once registered, these are available in Semaphore ProxmoxAPI environment:
- `PROXMOX_HOST` - Proxmox server IP/hostname
- `PROXMOX_NODE` - Node name (usually "pve")
- `PROXMOX_TOKEN_ID` - Full token ID (user@realm!tokenname)
- `PROXMOX_TOKEN_SECRET` - Token secret UUID

## Security Considerations

1. **Token File Security**
   - Created with mode 600 (root only)
   - Should be deleted after registration
   - Never commit to git

2. **Semaphore Storage**
   - Tokens stored encrypted in Semaphore
   - Only accessible to job execution context
   - Not visible in UI after creation

3. **Permission Scope**
   - Token has minimal required permissions
   - Cannot access root shell or system config
   - Limited to VM and storage operations

## Testing the Integration

### Verify Token Creation
```bash
# On Proxmox
./bootstrap.sh --setup-proxmox-api
cat /root/.proxmox-api-token  # Should show token details
```

### Verify Registration
```bash
# On VM
curl -s -c /tmp/cookie -X POST -H 'Content-Type: application/json' \
  -d '{"auth": "admin", "password": "PASSWORD"}' \
  http://localhost:3000/api/auth/login

curl -s -b /tmp/cookie http://localhost:3000/api/project/1/environment | \
  jq '.[] | select(.name=="ProxmoxAPI")'
```

### Test API Access
```bash
# Test that API tokens work from Semaphore templates
# Run any template that uses ProxmoxAPI environment
```

## Troubleshooting

### Token Not Registered Automatically
- Check `/var/log/privatebox-setup.log` on VM
- Ensure `/root/.proxmox-api-token` exists before setup-guest.sh runs
- Verify `register-proxmox-api.sh` has execute permissions

### Manual Registration Fails
- Verify Semaphore is running: `systemctl status semaphore`
- Check SERVICES_PASSWORD is set correctly
- Ensure token values are valid (test with curl)

### API Calls Fail in Playbooks
- Check environment is attached to job template
- Verify token has correct permissions on Proxmox
- Test token directly: `curl -sk -H "Authorization: PVEAPIToken=..." ...`