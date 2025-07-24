# Handoff Prompt for Phase 2 Implementation Breakdown

## Context
You are continuing work on PrivateBox, a privacy-focused router product built on Proxmox VE. Phase 2 planning has been completed for implementing network segmentation using OPNsense. Now we need to break down the implementation into smaller, manageable tasks.

## Current Status
- **Phase 0**: ✅ Complete - AdGuard deployed with 100% automation
- **Phase 1**: ✅ Complete - All issues fixed
- **Phase 2**: ✅ Planning complete - Ready for implementation breakdown

## Key Decisions Made
1. **Pure Ansible approach** using `community.general.proxmox_kvm` module
2. **OPNsense deployment** via qcow2 VM images (confirmed as full installations)
3. **API-based configuration** using `ansibleguy.opnsense` Ansible collection
4. **100% hands-off deployment** - zero manual steps required
5. **Incremental migration** strategy for safety

## Key Documents to Review
1. `/documentation/phase-2-planning/comprehensive-plan.md` - Master plan
2. `/documentation/phase-2-planning/opnsense-final-automation-strategy.md` - Automation approach
3. `/documentation/phase-2-planning/firewall-rules-matrix.md` - Detailed firewall rules
4. `/documentation/phase-2-planning/migration-runbook.md` - Step-by-step migration

## Your Task
Break down the Phase 3 implementation into smaller tasks following this structure:

### 1. Ansible Playbook Development
Create individual playbook tasks for:
- OPNsense VM deployment (`opnsense-deploy.yml`)
- Network configuration (`opnsense-network.yml`)
- Firewall rules deployment (`opnsense-firewall.yml`)
- Service migration (`migrate-services.yml`)
- Client migration (`migrate-clients.yml`)

### 2. Semaphore Job Templates
Design templates for operator-friendly execution:
- Each playbook should have corresponding Semaphore template
- Include variable prompts for customization
- Add rollback templates

### 3. Testing Strategy
- Isolated test environment setup
- Validation playbooks
- Performance benchmarks

### 4. Documentation Updates
- Operator guides
- Troubleshooting procedures
- Architecture diagrams

## Implementation Priorities
1. **First**: Get OPNsense VM deploying successfully
2. **Second**: Configure networking and VLANs
3. **Third**: Implement firewall rules
4. **Fourth**: Migrate services
5. **Last**: Migrate clients

## Technical Details
- **Proxmox Host**: 192.168.1.10
- **Management VM**: Currently at 192.168.1.21 (will move to 10.0.20.21)
- **OPNsense**: Will be at 10.0.10.1 (management interface)
- **VLANs**: Management (10), Services (20), LAN (30), IoT (40)

## Output Expected
Create a detailed task breakdown with:
- Task descriptions
- Dependencies
- Time estimates
- Ansible code snippets where relevant
- Testing criteria
- Documentation requirements

Each task should be small enough to complete in 1-2 hours of focused work.

## Additional Context
- Project follows service-oriented Ansible approach (see `/ansible/playbooks/services/`)
- All provisioning happens via Ansible/Semaphore after bootstrap
- Existing patterns from AdGuard deployment should be followed
- Focus on maintainability and operator-friendliness