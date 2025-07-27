# OPNsense ISO Remastering for 100% Hands-Off Deployment

This directory contains documentation and templates for deploying OPNsense with embedded configurations using pure Ansible automation.

## Deployment Architecture

- **Execution**: Ansible playbook runs from Semaphore on privatebox VM
- **Target**: All operations execute on Proxmox host via SSH
- **Approach**: Pure Ansible tasks - no scripts copied to target
- **Result**: 100% hands-off OPNsense deployment

## Files in This Directory

1. **OPNSENSE_ISO_REMASTER_GUIDE.md** - Comprehensive guide covering:
   - Deployment architecture and order of operations
   - Complete technical background and rationale
   - Pure Ansible implementation approach
   - Troubleshooting and advanced topics

2. **config-template.xml** - OPNsense configuration template with:
   - Static IP configuration (192.168.1.69/24)
   - Gateway configuration (192.168.1.3)
   - SSH enabled with key authentication
   - Basic firewall rules
   - Ready for Ansible templating

3. **remaster-opnsense.sh** - Reference script (for understanding only):
   - Shows the remastering process steps
   - Not used in production deployment
   - Production uses pure Ansible tasks instead

## Quick Start (Ansible Deployment)

1. **Set Variables** in your Ansible inventory:
   ```yaml
   opnsense_ssh_key: "ssh-rsa AAAAB3... your-key-here"
   opnsense_root_password: "YourSecurePassword"
   opnsense_lan_ip: "192.168.1.69"
   opnsense_lan_gateway: "192.168.1.3"
   ```

2. **Run the Playbook** from Semaphore:
   - Select "Deploy OPNsense ISO" template
   - Confirm deployment
   - Wait for completion (~10 minutes)

3. **Access OPNsense**:
   - Web UI: https://192.168.1.69
   - SSH: `ssh -i ~/.ssh/your_key root@192.168.1.69`

## Manual Process (Reference Only)

For understanding the process, here are the manual steps that Ansible automates:

1. Generate password hash:
   ```bash
   htpasswd -bnBC 10 "" "YourPasswordHere" | tr -d ':\n' | sed 's/$2y/$2b/'
   ```

2. The Ansible playbook then:
   - Downloads OPNsense ISO to Proxmox
   - Templates config.xml with your settings
   - Remasters ISO with embedded config
   - Creates and starts VM
   - Verifies deployment success

## Key Benefits

- **100% Hands-Off**: No console interaction required
- **Reliable**: No dependency on console automation or filesystem drivers
- **Repeatable**: Same ISO produces identical deployments
- **Version Controlled**: Track your infrastructure as code
- **Fast**: Deploy new instances in minutes

## Support

For issues or questions:
1. Check the comprehensive guide (OPNSENSE_ISO_REMASTER_GUIDE.md)
2. Review the troubleshooting section
3. Examine the script output for specific errors

## License

This documentation and associated scripts are part of the PrivateBox project and are released under the MIT License.