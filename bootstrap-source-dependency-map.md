# Bootstrap Source Dependency Map

## Overview

This document maps out all the source dependencies in the PrivateBox bootstrap scripts, showing which files source which other files and identifying circular dependencies.

## Main Entry Points

### 1. quickstart.sh (standalone)
- **Sources**: Nothing (self-contained)
- **Purpose**: Downloads and runs bootstrap.sh

### 2. bootstrap.sh
- **Sources**:
  - `lib/bootstrap_logger.sh`
  - `lib/constants.sh` ⚠️ (already sourced by bootstrap_logger.sh)
  - `config/privatebox.conf` (if exists)

### 3. deploy-to-server.sh
- **Sources**:
  - `lib/common.sh` (if available)

## Library Files (`lib/`)

### constants.sh
- **Sources**: Nothing
- **Sourced by**:
  - bootstrap_logger.sh
  - common.sh
  - config_manager.sh
  - error_handler.sh
  - service_manager.sh
  - ssh_manager.sh
  - bootstrap.sh ⚠️ (redundant)

### bootstrap_logger.sh
- **Sources**:
  - constants.sh
- **Sourced by**:
  - common.sh
  - config_manager.sh
  - error_handler.sh
  - service_manager.sh
  - ssh_manager.sh
  - bootstrap.sh

### common.sh
- **Sources** (in order):
  1. constants.sh
  2. bootstrap_logger.sh
  3. error_handler.sh
  4. validation.sh
  5. service_manager.sh
  6. ssh_manager.sh
  7. config_manager.sh
- **Sourced by**:
  - All scripts in `scripts/` directory
  - deploy-to-server.sh

### validation.sh
- **Sources**: Nothing
- **Sourced by**:
  - common.sh
  - config_manager.sh
  - network-discovery.sh (directly)

### error_handler.sh
- **Sources**:
  - bootstrap_logger.sh
  - constants.sh ⚠️ (already sourced by bootstrap_logger.sh)
- **Sourced by**:
  - common.sh

### service_manager.sh
- **Sources**:
  - bootstrap_logger.sh
  - constants.sh ⚠️ (already sourced by bootstrap_logger.sh)
- **Sourced by**:
  - common.sh

### ssh_manager.sh
- **Sources**:
  - bootstrap_logger.sh
  - constants.sh ⚠️ (already sourced by bootstrap_logger.sh)
- **Sourced by**:
  - common.sh

### config_manager.sh
- **Sources**:
  - bootstrap_logger.sh
  - constants.sh ⚠️ (already sourced by bootstrap_logger.sh)
  - validation.sh
- **Sourced by**:
  - common.sh

## Script Files (`scripts/`)

All scripts in the `scripts/` directory follow the same pattern:
- **Source**: `../lib/common.sh`

Scripts include:
- backup.sh
- create-ubuntu-vm.sh
- fix-proxmox-repos.sh
- health-check.sh
- initial-setup.sh
- network-discovery.sh
- portainer-setup.sh
- privatebox-deploy.sh
- semaphore-setup.sh

### Special Cases

#### initial-setup.sh
- Sources common.sh (like others)
- Also sources:
  - `/usr/local/bin/portainer-setup.sh`
  - `/usr/local/bin/semaphore-setup.sh`

#### network-discovery.sh
- Sources common.sh
- Also directly sources `validation.sh` before common.sh

## Problems Identified

### 1. Multiple Sourcing of constants.sh
The file `constants.sh` is sourced multiple times in the dependency chain:
- `bootstrap.sh` → `bootstrap_logger.sh` → `constants.sh`
- `bootstrap.sh` → `constants.sh` (redundant)
- `common.sh` → `constants.sh`
- `common.sh` → `bootstrap_logger.sh` → `constants.sh`
- `common.sh` → `error_handler.sh` → `constants.sh`
- `common.sh` → `service_manager.sh` → `constants.sh`
- `common.sh` → `ssh_manager.sh` → `constants.sh`
- `common.sh` → `config_manager.sh` → `constants.sh`

### 2. Readonly Variable Conflicts
Since `constants.sh` uses `readonly` for all variables, attempting to source it multiple times causes errors like:
```
/tmp/privatebox-quickstart-20250702-155404/bootstrap/lib/constants.sh: line 8: PRIVATEBOX_VERSION: readonly variable
```

### 3. Redundant Sourcing
Many library files source both `bootstrap_logger.sh` and `constants.sh`, but `bootstrap_logger.sh` already sources `constants.sh`.

## Dependency Tree

```
bootstrap.sh
├── lib/bootstrap_logger.sh
│   └── lib/constants.sh
└── lib/constants.sh ⚠️ REDUNDANT

deploy-to-server.sh
└── lib/common.sh
    ├── lib/constants.sh
    ├── lib/bootstrap_logger.sh
    │   └── lib/constants.sh ⚠️ ALREADY SOURCED
    ├── lib/error_handler.sh
    │   ├── lib/bootstrap_logger.sh
    │   │   └── lib/constants.sh ⚠️ ALREADY SOURCED
    │   └── lib/constants.sh ⚠️ ALREADY SOURCED
    ├── lib/validation.sh
    ├── lib/service_manager.sh
    │   ├── lib/bootstrap_logger.sh
    │   │   └── lib/constants.sh ⚠️ ALREADY SOURCED
    │   └── lib/constants.sh ⚠️ ALREADY SOURCED
    ├── lib/ssh_manager.sh
    │   ├── lib/bootstrap_logger.sh
    │   │   └── lib/constants.sh ⚠️ ALREADY SOURCED
    │   └── lib/constants.sh ⚠️ ALREADY SOURCED
    └── lib/config_manager.sh
        ├── lib/bootstrap_logger.sh
        │   └── lib/constants.sh ⚠️ ALREADY SOURCED
        ├── lib/constants.sh ⚠️ ALREADY SOURCED
        └── lib/validation.sh ⚠️ ALREADY SOURCED

scripts/*.sh
└── lib/common.sh
    └── [see common.sh tree above]
```

## Recommendations

1. **Add source guards**: Add a check at the beginning of `constants.sh` to prevent multiple sourcing:
   ```bash
   [[ -n "${CONSTANTS_SOURCED:-}" ]] && return 0
   CONSTANTS_SOURCED=true
   ```

2. **Remove redundant sources**: 
   - Remove `source constants.sh` from bootstrap.sh (line 15)
   - Remove `source constants.sh` from all lib files except bootstrap_logger.sh

3. **Simplify dependency chain**: Since `common.sh` sources everything, individual lib files don't need to source each other.

## Proposed Dependency Structure

### Design Principles

1. **Single Source Rule**: Each file should be sourced only once in any execution path
2. **Centralized Dependencies**: `common.sh` acts as the central dependency manager for library files
3. **Minimal Direct Dependencies**: Library modules should not source each other directly
4. **Clear Entry Points**: Distinguish between standalone scripts and library modules

### Proposed Structure

#### Entry Points

**quickstart.sh** (standalone)
- No dependencies (self-contained with its own color definitions)

**bootstrap.sh**
- Sources: `lib/common.sh` only
- Config: `config/privatebox.conf` (if exists)

**deploy-to-server.sh**
- Sources: `lib/common.sh` only

#### Library Organization

**lib/constants.sh**
- Sources: Nothing
- Contains: All constants, colors, and configuration defaults
- Guard: Prevents multiple sourcing with `CONSTANTS_SOURCED` check

**lib/common.sh** (Central dependency manager)
- Sources in order:
  1. `constants.sh` (first, provides all constants)
  2. `bootstrap_logger.sh` (needs constants for colors)
  3. `validation.sh` (standalone, no dependencies)
  4. `error_handler.sh` (uses logging functions)
  5. `service_manager.sh` (uses logging and error handling)
  6. `ssh_manager.sh` (uses logging and error handling)
  7. `config_manager.sh` (uses all above functions)

**Other lib files**
- `bootstrap_logger.sh`: No sources (gets constants from common.sh)
- `validation.sh`: No sources (pure functions)
- `error_handler.sh`: No sources (gets everything from common.sh)
- `service_manager.sh`: No sources (gets everything from common.sh)
- `ssh_manager.sh`: No sources (gets everything from common.sh)
- `config_manager.sh`: No sources (gets everything from common.sh)

#### Scripts Directory

All scripts in `scripts/` follow the same pattern:
- Source: `../lib/common.sh` only
- This provides all necessary functions and constants

### Clean Dependency Tree

```
quickstart.sh
└── [self-contained]

bootstrap.sh
└── lib/common.sh
    ├── lib/constants.sh (with guard)
    ├── lib/bootstrap_logger.sh
    ├── lib/validation.sh
    ├── lib/error_handler.sh
    ├── lib/service_manager.sh
    ├── lib/ssh_manager.sh
    └── lib/config_manager.sh

deploy-to-server.sh
└── lib/common.sh
    └── [same as above]

scripts/*.sh
└── lib/common.sh
    └── [same as above]
```

### Implementation Steps

1. Add source guard to `constants.sh`
2. Remove all source statements from library files (except common.sh)
3. Update `common.sh` to source `constants.sh` first
4. Update `bootstrap.sh` to source only `common.sh`
5. Test all entry points to ensure proper functionality

### Benefits

- **No Circular Dependencies**: Clear hierarchical structure
- **No Redundant Sourcing**: Each file sourced exactly once
- **Simplified Maintenance**: Changes to dependencies only need updates in common.sh
- **Consistent Environment**: All scripts get the same set of functions and constants
- **Faster Execution**: Reduced file parsing and variable definition