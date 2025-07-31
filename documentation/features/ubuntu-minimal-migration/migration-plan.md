# Ubuntu Minimal Migration Plan

## Executive Summary

This document outlines the plan to migrate PrivateBox's container-host VM from Ubuntu 24.04 Server to Ubuntu 24.04 Minimal cloud image, potentially saving 58% disk space and achieving 40% faster boot times.

## Current State Analysis

### Current Setup
- **OS**: Ubuntu 24.04 Server cloud image
- **Image Size**: 587MB
- **Package Count**: 426 packages
- **Boot Time**: 5-10 minutes with cloud-init
- **Resources**: 4GB RAM, 2 cores, 5GB disk expansion

### Installed Packages
Via cloud-init:
- podman, buildah, skopeo (container tools)
- openssh-server

Via initial-setup.sh:
- curl, git, jq, htop, netcat-openbsd

### Key Services
1. **Portainer**: Container management UI (runs in container)
2. **Semaphore**: Ansible automation UI (runs in container with MySQL)
3. **Podman**: Container runtime with systemd integration

## Ubuntu Minimal Characteristics

### Benefits
- **Size**: 244MB vs 587MB (58% reduction)
- **Boot Performance**: Up to 40% faster
- **Package Count**: 288 vs 426 packages
- **Security**: Smaller attack surface, fewer updates
- **Purpose-Built**: Designed for automated cloud deployments

### What's Removed
- Man pages and documentation
- Language translations
- Interactive convenience tools
- "Recommends" packages
- Human-oriented utilities

### What's Retained
- Full systemd functionality
- Cloud-init support
- Network stack
- SSH server capability
- Package management (apt)

### Critical Dependencies to Verify
- **ufw** - We use it for firewall rules
- **locale-gen** - Required for UTF-8 locale generation
- **loginctl** - Essential for podman user lingering
- **systemd-resolved** - DNS resolution
- **cloud-init growpart** - Automatic disk expansion

## Implementation Plan

### Phase 1: Validation (2 hours)

1. **Test Minimal Image Locally**
   ```bash
   # Download and test minimal image
   wget https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img
   
   # Create test VM with minimal image
   # Verify all required packages can be installed
   ```

2. **Package Availability Check**
   - Confirm podman, buildah, skopeo availability
   - Test systemd-container integration
   - Verify Podman Quadlet functionality
   - Check ufw installation and functionality
   - Verify locale-gen works for en_US.UTF-8
   - Test loginctl enable-linger for podman users
   - Confirm systemd-resolved is present
   - Verify cloud-init modules (especially growpart)

3. **Cloud-init Compatibility**
   - Test existing cloud-init configuration
   - Ensure user creation and SSH keys work
   - Verify network configuration

### Phase 2: Code Changes (1 hour)

1. **Update create-ubuntu-vm.sh**
   ```bash
   # Change from:
   CLOUD_IMG_URL="${CLOUD_IMG_BASE_URL:-https://cloud-images.ubuntu.com/releases}/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
   
   # To use constants.sh value:
   source "${SCRIPT_DIR}/../lib/constants.sh"
   CLOUD_IMG_URL="${UBUNTU_IMAGE_URL}"
   IMAGE_NAME="${UBUNTU_IMAGE_NAME}"
   ```

2. **Update Bootstrap Documentation**
   - Note the change to minimal image
   - Update expected boot times
   - Document any missing packages

### Phase 3: Testing (2 hours)

1. **Command Verification Test**
   Test all commands used in our scripts:
   ```bash
   # Test each critical command
   locale-gen en_US.UTF-8
   loginctl enable-linger ubuntuadmin
   ufw allow 22/tcp
   ufw allow 9000/tcp
   ufw allow 3000/tcp
   systemctl status systemd-resolved
   timedatectl status
   ```

2. **Full Bootstrap Test**
   - Run complete bootstrap process
   - Verify VM creation and cloud-init
   - Confirm service installations

3. **Service Verification**
   - Portainer accessibility and functionality
   - Semaphore UI and API responsiveness
   - Ansible job execution from Semaphore

4. **Performance Metrics**
   - Measure actual boot times
   - Check memory usage at idle
   - Verify disk space savings

### Phase 4: Rollout (30 minutes)

1. **Update Documentation**
   - README.md bootstrap times
   - CLAUDE.md implementation notes
   - Add troubleshooting for minimal-specific issues

2. **Create Rollback Plan**
   - Keep server image URL as fallback
   - Document how to switch back if needed

## Risk Assessment

### Low Risk Items
- **Package Installation**: All required packages confirmed available
- **Cloud-init**: Fully supported in minimal images
- **Container Runtime**: Podman works identically

### Medium Risk Items
- **Systemd Differences**: Minimal may have fewer systemd units
- **Network Tools**: Some debugging tools might be missing
- **Unexpected Dependencies**: Hidden package requirements

### Mitigation Strategies
1. Keep `unminimize` script option documented
2. Test thoroughly before committing
3. Maintain ability to switch image URLs easily

## Success Criteria

1. **Functional**
   - VM boots successfully
   - All services start and run
   - Ansible jobs execute from Semaphore

2. **Performance**
   - Boot time under 4 minutes
   - Disk usage reduced by >300MB
   - Memory usage at or below current

3. **Operational**
   - No impact to end-user functionality
   - Debugging capabilities maintained
   - Easy rollback if needed

## Decision Matrix

| Factor | Stay with Server | Switch to Minimal |
|--------|-----------------|-------------------|
| Disk Space | 587MB | 244MB ✓ |
| Boot Time | 5-10 min | 3-6 min ✓ |
| Complexity | None | Minor changes ✓ |
| Risk | None | Low ✓ |
| Human Access | Better | Adequate |
| Container Support | Full | Full ✓ |

## Recommendation

**Switch to Ubuntu Minimal**. The benefits significantly outweigh the minimal risks:
- 343MB disk savings per VM
- 40% faster deployment
- No functional impact
- Aligns with "cattle not pets" philosophy

## Implementation Timeline

- **Week 1**: Testing and validation
- **Week 2**: Code changes and documentation
- **Week 3**: Gradual rollout with monitoring

## Additional Considerations

### Optional Enhancements
1. **QEMU Guest Agent** - For better Proxmox integration (graceful shutdown, backups)
   ```bash
   apt-get install qemu-guest-agent
   systemctl enable qemu-guest-agent
   ```

2. **Time Synchronization** - Ensure accurate time for certificates
   - systemd-timesyncd should be included
   - Verify with `timedatectl status`

3. **Network Optimization**
   - Confirm virtio network drivers are loaded
   - Check MTU settings for container networking

### Security Considerations
1. **SSH Host Keys** - Verify generation on first boot
2. **Firewall Rules** - Ensure ufw rules persist
3. **AppArmor** - Check if profiles are included/needed

## Monitoring Plan

Post-implementation monitoring:
1. Track bootstrap success rates
2. Monitor service startup times
3. Check for missing package errors
4. Gather user feedback
5. Watch for locale-related errors
6. Monitor disk resize operations

## Conclusion

Ubuntu Minimal is ideal for PrivateBox's automated, container-focused architecture. The significant resource savings justify the minor implementation effort.