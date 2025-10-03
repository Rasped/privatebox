# PrivateBox Recovery Concept

## Problem
Consumer network appliances need factory reset capability, but PrivateBox runs on generic x86 hardware without reset buttons.

## Solution Discovery
Physical console access can be detected and restricted in Linux, enabling secure recovery options.

## Core Concept
- Create files/scripts that are ONLY accessible from physical console (not SSH)
- Use TTY detection: `[ "$SSH_CONNECTION" ]` and `tty | grep "^/dev/tty[0-9]"`
- Store recovery passwords and original config in console-only directory

## Implementation Ideas
1. **Recovery user**: Immutable account that only works at physical console
2. **Console-only directory**: `/root/.console-only/` with original configs and passwords
3. **Factory reset script**: Detects physical console, offers reset/restore options
4. **Recovery partition**: Small Alpine Linux partition that survives Proxmox reinstall

## Implementation Strategy

### Two-Phase Approach Adopted

**Phase 1: Offline Capability (Low Risk)**
- Store all required assets locally on dedicated partition
- Modify scripts to use local copies instead of internet downloads
- Enable completely offline operation after initial setup
- Safer to implement and test incrementally

**Phase 2: Recovery Infrastructure (High Risk)**
- Create encrypted password vault
- Generate golden Proxmox image (IMMEDIATELY after Proxmox install)
- Build recovery OS with console-only access
- Implement full factory reset capability

### Critical Insight: Timing Matters

Golden image must be captured BEFORE any PrivateBox components are installed, ensuring recovery restores to truly virgin Proxmox state.

## Current Status
- Core PrivateBox functionality complete (AdGuard, Homer, automation)
- Network isolation verified and working
- Ready to implement Phase 1 (offline capability)
- Detailed implementation plan documented in recovery-system.md

## Next Steps
1. **Phase 1**: Inventory all download operations in current scripts
2. **Phase 1**: Create asset download and storage system
3. **Phase 1**: Modify scripts to check local assets first
4. **Phase 1**: Test offline operation capability
5. **Phase 2**: Implement recovery partition structure
6. **Phase 2**: Create console-only recovery access system