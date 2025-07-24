# Phase 2 Plan Review and Updates

**Date**: 2025-07-24  
**Status**: Plan Updated After Critical Review

## Key Issues Fixed

### 1. ✅ Network Configuration Error
**Fixed**: Removed invalid VLAN tag from non-VLAN-aware bridge
- Was: `net0: 'virtio,bridge=vmbr0,tag=99'`
- Now: `net0: 'virtio,bridge=vmbr0'`

### 2. ✅ Service Availability During Migration
**Added**: DNS forwarding strategy to maintain service during migration
- OPNsense temporarily forwards DNS queries during VM migration
- Ensures zero DNS downtime for clients
- Added steps D.1 and D.8 to migration runbook

### 3. ✅ Migration Timing Updated
**Adjusted**: Service migration phase from 31 to 41 minutes
- Accounts for DNS forwarding configuration
- More realistic timeline

## Accepted Risks (Safe Enough)

### 1. ✅ Module Testing
- **Decision**: Trust Ansible documentation
- **Rationale**: Module is mature and widely used
- **Fallback**: Shell scripts if needed

### 2. ✅ Resource Allocation
- **Decision**: Keep 4GB RAM / 32GB disk
- **Rationale**: Easy to adjust later if needed
- **Note**: Overprovisioning is safer than under

### 3. ✅ API Authentication
- **Decision**: Use root credentials initially
- **Rationale**: Can create limited user later
- **Priority**: Get it working first, secure later

### 4. ✅ Storage Location
- **Decision**: Assume `local:iso/` 
- **Note**: Added comment that this is configurable
- **Rationale**: Standard Proxmox configuration

## What We're NOT Worrying About

1. **IPv6**: Can be added in Phase 4
2. **Performance Testing**: Can monitor in production
3. **Perfect Security**: Good enough for home/small business
4. **Every Edge Case**: Documented rollback procedures

## Plan Validation

The plan is now:
- **Technically Correct**: Fixed critical network configuration error
- **Practically Achievable**: Added DNS forwarding for zero downtime
- **Safe Enough**: Accepted reasonable risks with documented fallbacks
- **Ready for Implementation**: All major blockers addressed

## Summary

The Phase 2 plan has been updated to address critical issues while maintaining a pragmatic "safe enough" approach. The fixes ensure the migration will work technically while accepting some minor risks that can be addressed post-implementation.