# Migration Orchestration Fixes Applied

## Summary of Changes

### 1. Host Group Validation
Added pre-task validation to all migration playbooks to check for required host groups:
- `pre-migration-check.yml`: Validates proxmox-host group exists
- `configure-vlan-bridges.yml`: Validates proxmox-host group exists  
- `deploy-opnsense-vlans.yml`: Validates proxmox-host group exists
- `migrate-services.yml`: Validates container-host group exists
- `update-dns-dhcp.yml`: Validates proxmox-host group exists

All validations include clear error messages with instructions on how to add the missing groups to inventory.

### 2. Dynamic Network Interface Discovery
Fixed hardcoded 'ens18' interface in `migrate-services.yml`:
- Now uses `ansible_default_ipv4.interface` fact to discover primary interface
- Validates interface exists before use
- Updates all VLAN configurations to use discovered interface

### 3. Dynamic Service Discovery
Enhanced `migrate-services.yml` to discover running container services:
- Finds all systemd services matching container patterns
- Identifies both Podman and Docker containers
- Parses service names and types dynamically
- Updates configurations based on discovered services

### 4. VLAN Bridge Validation
Enhanced `configure-vlan-bridges.yml` with comprehensive validation:
- Tests VLAN tagging functionality on physical interface
- Verifies bridge isolation (confirms VLANs are properly separated)
- Creates connectivity test scripts
- Provides detailed validation results

### 5. Enhanced Credential Validation
Improved `update-dns-dhcp.yml` credential handling:
- Tests OPNsense API connectivity before attempting configuration
- Provides detailed manual configuration guide on API failure
- Validates AdGuard accessibility with clear error messages
- Includes fallback configuration for all failures

### 6. Network Discovery Integration
Added to `update-dns-dhcp.yml`:
- Checks for network discovery results file
- Loads discovered network configuration if available
- Falls back to default VLAN configuration if not found
- Uses discovered AdGuard IP dynamically

## Additional Improvements

### Rollback Support
- `migrate-services.yml`: Added automatic rollback script generation
- Scripts restore original network configuration and restart services

### Better Error Handling
- All API calls now have proper error handling with rescue blocks
- Detailed manual configuration guides generated on failures
- Clear success/failure messages throughout

### Testing Scripts
Created multiple test and verification scripts:
- `/opt/privatebox/scripts/verify-vlans.sh`: Check VLAN status
- `/opt/privatebox/scripts/test-vlan-connectivity.sh`: Test bridge connectivity
- `/opt/privatebox/scripts/test-dns-resolution.sh`: Verify DNS from all VLANs
- `/opt/privatebox/scripts/monitor-dhcp-leases.sh`: Monitor DHCP assignments

## Integration with Discovery Playbooks

The fixed playbooks now integrate with:
- `discover-environment.yml`: Results stored in `/opt/privatebox/network-discovery-results.yml`
- `plan-network.yml`: Network plan can override default VLAN configurations

This allows for dynamic adaptation to different network environments while maintaining backward compatibility with hardcoded defaults.

## Backward Compatibility

All changes maintain backward compatibility:
- Default values provided for all dynamic discoveries
- Existing configurations continue to work
- Manual overrides still possible via vars_prompt
- No breaking changes to existing deployments