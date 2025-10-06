# HANDOVER: Deployment Sequence Documentation

**Date:** 2025-01-06
**Status:** In Progress (Steps 1-10 complete, Phase 1 done)

## Task

Document the complete PrivateBox deployment sequence by tracing through actual code execution from clean Proxmox to fully operational system.

## Current State

**File:** `documentation/DEPLOYMENT-SEQUENCE.md`

**Completed:** Steps 1-10 (Phase 1: Host Preparation)
- Entry point: quickstart.sh
- Bootstrap initialization
- Dependencies installation
- Network configuration (vmbr0, vmbr1, VLAN 20)
- HTTPS certificate generation
- Configuration file generation
- Proxmox API token setup

**Next:** Continue with Phase 2 (VM creation via `bootstrap/create-vm.sh`)

## Instructions for Next Context

1. Read `documentation/DEPLOYMENT-SEQUENCE.md` - it explains its own purpose at the top
2. Find where documentation stopped (currently: "Control returns to: bootstrap/bootstrap.sh")
3. Read `bootstrap/bootstrap.sh` to see what Phase 2 does
4. Read `bootstrap/create-vm.sh` line by line
5. Document steps 11-15 following the same pattern:
   - What script executes
   - What commands run
   - What files are created/modified
   - What state changes occur
6. Commit after every 5 steps
7. Repeat for remaining phases (Phase 3: setup-guest.sh, Phase 4: orchestration)

## Why This Matters

This document is the authoritative source for understanding deployment. It enables:
- Debugging deployment failures
- Understanding what actually happens (not assumptions)
- New contexts to continue work without re-learning codebase

## Approach

Trace actual code execution. Don't document what should happen - document what does happen by reading the scripts.

END HANDOVER
