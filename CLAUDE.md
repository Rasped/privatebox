# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🚨 CRITICAL: ALWAYS USE CAVEMAN LANGUAGE 🚨

**THIS APPLIES TO EVERY RESPONSE. NO EXCEPTIONS.**

Short words. No fluff. Save tokens for real work.

### ❌ NEVER Write Like This (Verbose/Professional):
- "I'll help you with that. Let me examine the file contents to better understand the issue."
- "I've successfully completed the requested changes to the configuration."
- "I notice there's an error in the deployment. Let me investigate further."
- "Thank you for providing that information. I'll now proceed with the implementation."
- "Based on my analysis, I recommend the following approach..."

### ✅ ALWAYS Write Like This (Caveman):
- "Checking file."
- "Done. Fixed config."
- "Error found. Looking."
- "Got it. Starting now."
- "Best way: [solution]"

### More Examples:

| ❌ VERBOSE (BAD) | ✅ CAVEMAN (GOOD) |
|------------------|-------------------|
| "Let me search for that pattern in your codebase" | "Searching." |
| "I'll create a comprehensive plan for this feature" | "Making plan." |
| "The test suite has completed successfully" | "Tests pass." |
| "I've identified several issues that need attention" | "Found 3 bugs." |
| "Would you like me to proceed with the fix?" | "Fix now?" |
| "I understand your requirements" | "Got it." |
| "Here's what I found during my investigation" | "Found:" |
| "I'll need to examine multiple files" | "Checking files." |
| "The deployment appears to be failing" | "Deploy fails." |
| "Let me analyze the error messages" | "Reading errors." |

### Rules:
1. **No politeness** - Skip "please", "thank you", "I'll help", etc.
2. **No explanations** - Just facts and actions
3. **No filler words** - Remove "just", "actually", "basically", etc.
4. **Present tense** - "Doing X" not "I will do X"
5. **Lists > paragraphs** - Use bullets, not sentences
6. **Numbers > words** - "3 errors" not "several errors"

### Why This Matters:
- 50-70% shorter = More conversation history
- More history = Better context
- Better context = Smarter responses
- No confusion = Faster work

**REMINDER: This applies to EVERYTHING - explanations, error messages, status updates, questions, confirmations. CAVEMAN ALWAYS.**

## Table of Contents

1. [Code Delegation and Tool Access Policy](#code-delegation-and-tool-access-policy)
2. [Parallel Agent Usage and Model Selection](#parallel-agent-usage-and-model-selection)
3. [Project Overview](#project-overview)
4. [Quick Start](#quick-start)
5. [Architecture & Design](#architecture--design)
6. [Repository Structure](#repository-structure)
7. [Implementation Status](#implementation-status)
8. [Development Guide](#development-guide)
9. [Commands Reference](#commands-reference)
10. [Context7 Documentation System](#context7-documentation-system)
11. [Deep Thinking Requirements](#deep-thinking-requirements)
12. [Agent Architecture](#agent-architecture)
13. [Known Issues & Troubleshooting](#known-issues--troubleshooting)
14. [Lessons Learned](#lessons-learned)

---

## Main Claude = Full Access

### Tool Rules
| Tool | Main Claude | automation-engineer | Why |
|------|------------|-------------------|-----|
| Bash | ✅ Full access | ✅ Full access | Both: execute commands |
| Edit/Write | ✅ Yes | ✅ Yes | Both: write code |
| Read/Grep | ✅ Yes | ✅ Yes | Both: read files |
| Task | ✅ Delegate | ✅ Can delegate | Coordination allowed |
| TodoWrite | ✅ Yes | ✅ Yes | Track work |

### Workflow
1. User asks → Main Claude investigates
2. Simple tasks → Main Claude implements directly
3. Complex/multi-part → Delegate to specialized agents
4. Verify implementation with tests

### Examples
```bash
# Main Claude can do everything:
bash -c "systemctl status service"  # Check status
grep -r "error" /var/log/           # Find problems
curl http://VM:3000/api/status      # Test endpoint
edit file.yml                       # Edit files
write new-script.sh                 # Create files
```

### Handover Template
```
Task: [What to do]
Problem: [What's broken]
Fix: [Specific changes]
Test: [How to verify]
```

Example: "Fix AdGuard - port binds to VM IP not localhost"

---

## Parallel Agents = FAST

### Model Rules
- **Opus**: Complex work, debugging (ALWAYS), implementation
- **Sonnet**: Simple edits, basic docs

### Launch Multiple Agents
Independent tasks? Launch together:
```
User: "Fix DNS and document it"
→ Task 1: system-debugger (Opus) - investigate
→ Task 2: technical-writer (Opus) - document
BOTH RUN AT SAME TIME
```

More examples:
- Deploy 3 services? → 3 automation-engineers in parallel
- Debug + fix + test? → All three agents at once
- Research + implement? → Both together

---

## Project Overview

PrivateBox is a privacy-focused router product built on Proxmox VE. The project provides automated bootstrap infrastructure for VM creation and service deployment using a simple, service-oriented Ansible approach for deploying privacy-enhancing services including OPNSense firewall, AdGuard Home, and Unbound DNS.

**Target Infrastructure**: Proxmox VE on Intel N100 mini PCs with 8-16GB RAM

---

## Quick Start

### One-Line Installation

```bash
# Basic installation with auto-discovery
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash

# With custom IP
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash -s -- --ip 192.168.1.50

# Skip confirmation prompt
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash -s -- --yes
```

**⚠️ IMPORTANT**: The quickstart script automatically handles cleanup! It will:
- Stop and destroy any existing VM with ID 9000
- Clean up old disk images
- Remove stale configurations

**DO NOT manually clean up before running the script** - just run it directly. The script is designed to be idempotent and handles all cleanup internally.

---

## Architecture & Design

### Key Architecture Decisions

1. **Bootstrap Architecture**:
   - Ubuntu 24.04 LTS VM as management host
   - Cloud-init for unattended installation
   - Automatic network configuration detection
   - Pre-installed Portainer and Semaphore

2. **Service Architecture**: 
   - Service-oriented Ansible playbooks for each component
   - OPNSense will run in dedicated VM (template-based deployment)
   - Other services containerized using Podman Quadlet (systemd integration)
   - Semaphore provides web UI for Ansible execution with automatic template sync

3. **Network Features**:
   - Automatic IP detection and assignment
   - Support for static IP configuration
   - Network segregation (design TBD)

### Critical Implementation Notes

1. **Service-Oriented Architecture**: 
   - Each service has its own playbook in `ansible/playbooks/services/`
   - No complex role hierarchy - simple, direct playbooks
   - Services deployed as Podman containers with systemd integration
   - VM creation handled via template deployment playbooks

2. **Container Strategy**: Using Podman Quadlet for systemd-native container management

3. **Secrets Management**: Needs implementation before production deployment

4. **Bootstrap Philosophy**: Bash scripts create initial infrastructure (by design), then Ansible takes over for service deployment

---

## Repository Structure

```
bootstrap/                 # Bootstrap infrastructure (FULLY IMPLEMENTED)
├── scripts/              # Core installation scripts
│   ├── create-ubuntu-vm.sh      # Main VM creation with cloud-init
│   ├── network-discovery.sh     # Automatic network configuration
│   ├── initial-setup.sh         # Post-install setup (via cloud-init)
│   ├── portainer-setup.sh       # Container management installation
│   ├── semaphore-setup.sh       # Ansible UI installation
│   ├── fix-proxmox-repos.sh     # Proxmox repository fixes
│   ├── health-check.sh          # Service health monitoring
│   └── backup.sh               # Configuration backup
├── config/               # Configuration templates
│   └── privatebox.conf.example  # Example configuration
├── lib/                  # Shared libraries
│   ├── common.sh               # Common functions
│   └── validation.sh           # Input validation
├── deploy-to-server.sh   # Remote deployment tool
└── bootstrap.sh          # Main entry point

quickstart.sh             # One-line installer (downloads and runs bootstrap)

ansible/                  # Service-oriented Ansible automation
└── playbooks/           # Service deployment playbooks
    └── services/        # Individual service playbooks
        ├── adguard-deploy.yml   # AdGuard Home deployment (implemented)
        └── adguard-configure-dns.yml  # DNS configuration

documentation/           # Comprehensive planning and technical documentation
├── features/            # Feature-specific documentation
├── handovers/          # Agent handover documents
│   ├── active/         # Currently active tasks
│   ├── completed/      # Completed tasks
│   └── templates/      # Handover templates
└── archive/            # Historical documentation
```

### Key Files to Reference

#### Bootstrap Files
- `quickstart.sh` - One-line installer script
- `bootstrap/bootstrap.sh` - Main bootstrap entry point
- `bootstrap/scripts/create-ubuntu-vm.sh` - Core VM creation logic
- `bootstrap/scripts/network-discovery.sh` - Network auto-detection
- `bootstrap/config/privatebox.conf.example` - Configuration template
- `bootstrap/README.md` - Bootstrap documentation

#### Ansible Documentation
- `ansible/README.md` - Service-oriented architecture overview
- `ansible/playbooks/services/` - Service deployment playbooks
- `README.md` - Project overview and quick start guide

---

## Implementation Status

### Bootstrap (COMPLETE)
- ✅ **Quick Start Script**: One-line installer with auto-discovery
- ✅ **VM Creation**: Automated Ubuntu 24.04 VM provisioning
- ✅ **Network Discovery**: Automatic network configuration detection
- ✅ **Service Installation**: Portainer and Semaphore auto-installed
- ✅ **Cloud-Init**: Unattended setup via cloud-init
- ✅ **Remote Deployment**: Deploy to remote Proxmox servers
- ✅ **Health Monitoring**: Service health check scripts

### Current Implementation Status (2025-08-01)

**🎉 100% HANDS-OFF DEPLOYMENT ACHIEVED!**

#### Working Features
- ✅ **VM Creation**: Automated Ubuntu 24.04 VM provisioning with cloud-init
- ✅ **Alpine VM**: Automated Alpine Linux VM with integrated Caddy
- ✅ **Container Networking**: Podman Quadlet with proper port binding
- ✅ **AdGuard Deployment**: Fully automated with API configuration
- ✅ **Caddy Reverse Proxy**: Auto-installed on Alpine VM
- ✅ **Semaphore Integration**: Automatic template synchronization
- ✅ **SSH Management**: Automated key distribution for Proxmox and container hosts

#### Known Issues (Not Manual Steps!)
- 🐛 **DNS Config Playbook**: Fails due to missing auth headers
- 🐛 **Caddy Proxy**: Some backends return 503 (config issue)
- 🐛 **Port Bindings**: Inconsistent binding strategies

#### In Development
- 🚧 **OPNSense**: Template-based deployment being developed
- 🚧 **Additional Services**: Unbound DNS, WireGuard VPN planned
- 🚧 **Network Design**: Architecture decisions pending

See [documentation/DEPLOYMENT-STATUS.md](../documentation/DEPLOYMENT-STATUS.md) for detailed report.

---

## Dev Rules

### Bootstrap
- Test network discovery first
- Scripts = idempotent (run many times OK)
- Source `lib/common.sh` for utils
- Cloud-init = keep simple

### Ansible  
- One playbook per service in `ansible/playbooks/services/`
- Use Podman Quadlet (systemd containers)
- VM creation = SSH to Proxmox, not API
- Simple > complex

### Proxmox
- Root user = NO sudo needed
- Bootstrap = 5-10 min (WAIT FULL TIME)
- timeout=300000 = 5 minutes

---

## Work Tracking

### Use `/track` Command
Track all work in `documentation/WORK-LOG.md` and `documentation/CHANGELOG.md`:

```bash
/track  # Updates both files, commits, and pushes
```

### Work Log Structure
- **Critical (P1)**: v1 blockers
- **Important (P2)**: Should have
- **Nice to Have (P3)**: Can wait
- **Uncategorized**: Needs triage

### Rules
- Add new work to WORK-LOG
- Move completed to CHANGELOG with date
- Commit message = actual work done, not "update logs"
- Keep entries short and clear

---

## Commands Reference

### Bootstrap Commands

```bash
# Run complete bootstrap with auto-discovery
sudo ./bootstrap/bootstrap.sh

# Create VM with specific network settings
sudo ./bootstrap/scripts/create-ubuntu-vm.sh --ip 192.168.1.50 --gateway 192.168.1.1

# Test network discovery
sudo ./bootstrap/scripts/network-discovery.sh

# Deploy to remote server
./bootstrap/deploy-to-server.sh 192.168.1.10 root

# Deploy and run tests
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test

# Check service health
ssh privatebox@<VM-IP> 'sudo /opt/privatebox/scripts/health-check.sh'
```

### Ansible Commands

```bash
# Deploy a specific service (e.g., AdGuard Home)
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/services/adguard.yml

# Run with specific variables
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/services/adguard.yml \
  -e "adguard_data_path=/opt/adguard" -e "adguard_web_port=8080"

# Using Semaphore UI (recommended)
# Services are automatically available as job templates in Semaphore
```

### Semaphore API Authentication

**⚠️ IMPORTANT**: Semaphore uses cookie-based authentication.

1. **Login and save cookie**:
```bash
curl -c /tmp/semaphore-cookie -X POST \
  -H 'Content-Type: application/json' \
  -d '{"auth": "admin", "password": "YOUR_PASSWORD_HERE"}' \
  http://VM_IP:3000/api/auth/login
```

2. **Use the cookie for API requests**:
```bash
# List templates
curl -s -b /tmp/semaphore-cookie http://VM_IP:3000/api/project/1/templates | jq

# Run a task
curl -s -b /tmp/semaphore-cookie -X POST \
  -H 'Content-Type: application/json' \
  -d '{"template_id": TEMPLATE_ID, "project_id": 1}' \
  http://VM_IP:3000/api/project/1/tasks

# Check task status
curl -s -b /tmp/semaphore-cookie http://VM_IP:3000/api/project/1/tasks/TASK_ID | jq -r '.status'
```

**Key points:**
- `-c` saves the cookie to a file
- `-b` uses the saved cookie for requests
- Success returns HTTP 204 No Content
- The cookie contains a session token (starts with "semaphore=")

---

## Context7 = Real Docs, Not Hallucinations

### How to Use
1. Search: `mcp__context7__resolve-library-id("ansible")`
2. Load: `mcp__context7__get-library-docs("/ansible/ansible-documentation")`

### Project Libraries
- Ansible: `/ansible/ansible-documentation` (Trust: 9.3)
- Proxmox: `/proxmox/pve-docs` (Trust: 8.2)
- Proxmox Ansible: `/ansible-collections/community.proxmox`

### Rules
- ALWAYS load Context7 BEFORE coding
- Trust score > 7 = good
- More snippets = better
- Load multiple libraries for complex tasks

---

## Think First, Code Later

### STOP Protocol
Before ANY action:
1. PAUSE - What does user REALLY want?
2. Context7 - Load docs FIRST
3. Options - Consider 3+ approaches
4. Simple - Simplest solution wins

### Context7 First
```
User asks → Load Context7 → Read examples → THEN plan
```

Required loads:
- Ansible work → Load ansible docs
- Bash scripts → Load shell/coreutils
- Containers → Load docker/podman
- Proxmox → Load proxmox + qm commands

### Big Feature? Write First

Complex feature = Create docs in `documentation/features/[name]/`
- What problem?
- What options?  
- What chosen? Why?
- How test?

Simple fix = Just do it.

### TodoWrite = Think Tool
Break tasks until tiny (<15 min each). If can't break down = don't understand yet.

### Simplicity Check
1. First idea (usually complex)
2. Stupid simple version  
3. Right balance
Pick #3.

---

## 5 Agents

### Who Does What
| Agent | Purpose | Tools | When to use |
|-------|---------|-------|-------------|
| Main Claude | Daily tasks, investigate, delegate | Full access | DEFAULT - use for everything |
| privatebox-orchestrator | Complex planning only | Write .md only | Big multi-project coordination |
| automation-engineer | Write ALL code | Full access | Any coding/automation |
| system-debugger | Find problems | Read + Bash | Debug issues (ALWAYS Opus) |
| technical-writer | User docs (fluent) | Edit .md only | User guides, troubleshooting |
| internal-doc-writer | AI docs (caveman) | Edit .md only | CLAUDE.md, agent files |

### Key Rules
- Main Claude = default for EVERYTHING
- Need code? → automation-engineer
- Big project? → privatebox-orchestrator first
- Problem? → system-debugger (Opus)
- Docs? → technical-writer

### Examples

**Check only**: `Main Claude runs bash → reports`

**Need code**: `Main Claude → handover → automation-engineer → verify`

**Parallel**: `Debug + document = 2 agents at once`

**Big project**: `Main → orchestrator → engineer → debugger → writer`

### Agent Files
`.claude/agents/`:
- `privatebox-orchestrator.md` = Complex planning, no code
- `automation-engineer.md` = Writes ALL code/automation
- `system-debugger.md` = Finds problems, no fixes
- `technical-writer.md` = User docs (professional)
- `internal-doc-writer.md` = AI docs (caveman)

`documentation/handovers/` = task handoffs

---

## Known Issues & Troubleshooting

### Ansible SSH Authentication from Semaphore
**Status**: 🟡 Under Investigation

**Problem**: While the bootstrap completes successfully and all templates are created, Ansible playbooks fail to connect via SSH when run through Semaphore.

**Symptoms**:
- Task status shows "error" with exit code 4
- Ansible reports "unreachable" for container-host
- SSH key is properly added to authorized_keys during bootstrap
- Manual SSH from VM to itself works correctly

**Current Workaround**: 
- Run playbooks manually via ansible-playbook command
- Or deploy services using Podman directly

**Next Steps**: Investigating why Semaphore's Ansible execution cannot use the SSH key despite it being properly configured.

### Bootstrap Issues ✅ ALL RESOLVED (2025-07-21)
All critical bootstrap issues have been fixed:
- ✅ Inventory creation with SSH key association
- ✅ Template generation for all services  
- ✅ Password generation with JSON-safe characters
- ✅ SSH key added to ubuntuadmin's authorized_keys

The bootstrap now runs completely hands-off in ~3 minutes.

---

## Lessons Learned

See `documentation/archive/CLAUDE-HISTORICAL.md` for detailed lessons and fixes from previous phases.