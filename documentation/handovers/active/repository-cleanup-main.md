# Handover: Repository Cleanup Implementation

**Assigned to**: automation-engineer  
**Created by**: privatebox-orchestrator  
**Date**: 2025-01-25  
**Priority**: High  

## Objective

Execute the main repository cleanup tasks to organize files and remove clutter. This involves moving files to appropriate locations and creating necessary directory structures.

## Background

Repository analysis revealed several areas needing cleanup:
1. Root-level documentation files that should be archived
2. Test scripts scattered in multiple locations
3. Completed phase documentation that can be archived
4. Dev-notes requiring individual analysis (separate handovers created)

## Specific Tasks

### 1. Create Archive Structure
Create the following directory:
- `/documentation/archive/` - For historical/completed documentation

### 2. Move Root-Level Documentation
Move these files to `/documentation/archive/`:
- `privatebox-handoff-prompt-20250125-complete.md` - Completed YAML fixes handoff
- `privatebox-test-log-20250124.md` - Historical test execution log  
- `template-generation-investigation.md` - Investigation notes (likely resolved)

### 3. Consolidate Test Scripts
Move test scripts to `/ansible/playbooks/tests/`:
- `/test-proxmox-discovery.sh` - Currently at root level
- `/ansible/test-playbooks.sh` - Should be with other tests

Ensure scripts remain executable after moving.

### 4. Archive Completed Phase Documentation

**Phase 0 (COMPLETE)**:
- Move `/documentation/phase-0-completion-report.md` to `/documentation/archive/phase-0/`
- Move `/documentation/phase-0-implementation-summary.md` to `/documentation/archive/phase-0/`

**Phase 2 (COMPLETE - Planning Only)**:
- Move entire `/documentation/phase-2-planning/` directory to `/documentation/archive/`
- Move `/documentation/phase-2-handover.md` to `/documentation/archive/phase-2/`

**Phase 3 (KEEP FOR NOW)**:
- Leave `/documentation/phase-3-implementation/` in place
- Status unclear - may have incomplete tasks

### 5. Update References
After moving files:
- Check if any documentation references moved files
- Update paths in CLAUDE.md if needed
- Ensure no broken links

## Important Notes

1. **Playbook Cleanup**: Explicitly deferred by user - do not touch playbooks
2. **Handover Directories**: Leave `/documentation/handovers/` structure for future workflow
3. **Dev-Notes**: Being handled via separate handovers - do not move/delete yet

## Success Criteria

- Clean root directory (only essential files remain)
- Organized test directory with all test scripts
- Archived completed phase documentation
- No broken references to moved files
- Clear separation between active and historical docs

## Verification Steps

1. Run `ls -la /` to verify root is clean
2. Check all test scripts are executable in new location
3. Verify archive structure is logical and findable
4. Run a grep for old paths to ensure no broken references

## Output Expected

Brief summary of:
1. Files moved and their new locations
2. Any issues encountered
3. Any references that were updated
4. Confirmation that repository is now better organized