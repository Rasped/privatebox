# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PrivateBox is a privacy-focused router product built on Proxmox VE. The project provides automated bootstrap infrastructure for VM creation and service deployment using a simple, service-oriented Ansible approach for deploying privacy-enhancing services including OPNSense firewall, AdGuard Home, and Unbound DNS.

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
├── inventories/          # Environment-specific inventory configurations
│   └── development/      # Development environment
├── group_vars/           # Global variables and container configurations
│   └── all.yml          # Common settings for all hosts
└── playbooks/           # Service deployment playbooks
    └── services/        # Individual service playbooks
        ├── deploy-adguard.yml   # AdGuard Home deployment (implemented)
        └── ADGUARD_DEPLOYMENT_GUIDE.md  # Deployment documentation

documentation/           # Comprehensive planning and technical documentation
```

## Key Architecture Decisions

1. **Target Infrastructure**: Proxmox VE on Intel N100 mini PCs with 8-16GB RAM
2. **Bootstrap Architecture**:
   - Ubuntu 24.04 LTS VM as management host
   - Cloud-init for unattended installation
   - Automatic network configuration detection
   - Pre-installed Portainer and Semaphore
3. **Service Architecture**: 
   - Service-oriented Ansible playbooks for each component
   - OPNSense will run in dedicated VM (created via SSH to Proxmox)
   - Other services containerized using Podman Quadlet (systemd integration)
   - Semaphore provides web UI for Ansible execution with automatic template sync
4. **Network Features**:
   - Automatic IP detection and assignment
   - Support for static IP configuration
   - Multiple VLANs for service segregation (planned)

## Development Commands

### Quick Start (One-Line Installation)

```bash
# Basic installation with auto-discovery
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash

# With custom IP
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash -s -- --ip 192.168.1.50

# Skip confirmation prompt
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash -s -- --yes
```

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
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/services/deploy-adguard.yml

# Run with specific variables
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/services/deploy-adguard.yml \
  -e "adguard_data_path=/opt/adguard" -e "adguard_web_port=8080"

# Using Semaphore UI (recommended)
# Services are automatically available as job templates in Semaphore
```

## Implementation Status

### Bootstrap (COMPLETE)
- ✅ **Quick Start Script**: One-line installer with auto-discovery
- ✅ **VM Creation**: Automated Ubuntu 24.04 VM provisioning
- ✅ **Network Discovery**: Automatic network configuration detection
- ✅ **Service Installation**: Portainer and Semaphore auto-installed
- ✅ **Cloud-Init**: Unattended setup via cloud-init
- ✅ **Remote Deployment**: Deploy to remote Proxmox servers
- ✅ **Health Monitoring**: Service health check scripts

### Ansible (SERVICE-ORIENTED APPROACH)
- ✅ **Service Playbooks**: Individual playbooks for each service
- ✅ **AdGuard Deployment**: Fully implemented with Podman Quadlet
- ✅ **Semaphore Integration**: Automatic template synchronization
- ✅ **Inventory**: SSH-based access to management VM
- 🚧 **Additional Services**: OPNSense, Unbound DNS planned
- 🚧 **VM Creation**: Via SSH to Proxmox host (no API needed)
- ❌ **Secrets Management**: Needs implementation

## Critical Implementation Notes

1. **Service-Oriented Architecture**: 
   - Each service has its own playbook in `ansible/playbooks/services/`
   - No complex role hierarchy - simple, direct playbooks
   - Services deployed as Podman containers with systemd integration
   - VM creation handled via SSH commands to Proxmox host

2. **Container Strategy**: Using Podman Quadlet for systemd-native container management

3. **Secrets Management**: Needs implementation before production deployment

4. **Bootstrap Philosophy**: Bash scripts create initial infrastructure (by design), then Ansible takes over for service deployment

## When Working on This Project

### Bootstrap Development

1. **Test Network Discovery First**: Always verify network detection works in the target environment
2. **Use Common Libraries**: Source `lib/common.sh` for logging and utility functions
3. **Maintain Idempotency**: Bootstrap scripts should be safe to run multiple times
4. **Check Prerequisites**: Always verify Proxmox environment before proceeding
5. **Follow Cloud-Init Best Practices**: Keep cloud-init configs simple and reliable

### Ansible Development

1. **Service-Oriented Approach**: Create individual playbooks for each service in `ansible/playbooks/services/`
2. **Use Semaphore Metadata**: Add `semaphore_*` fields to `vars_prompt` for automatic UI template generation
3. **Container Deployment**: Use Podman Quadlet for systemd integration (see AdGuard example)
4. **VM Creation**: Use SSH commands to Proxmox host, not API calls
5. **Keep It Simple**: Avoid complex role hierarchies - direct, readable playbooks are preferred

## Key Files to Reference

### Bootstrap Files
- `quickstart.sh` - One-line installer script
- `bootstrap/bootstrap.sh` - Main bootstrap entry point
- `bootstrap/scripts/create-ubuntu-vm.sh` - Core VM creation logic
- `bootstrap/scripts/network-discovery.sh` - Network auto-detection
- `bootstrap/config/privatebox.conf.example` - Configuration template
- `bootstrap/README.md` - Bootstrap documentation

### Ansible Documentation
- `ansible/README.md` - Service-oriented architecture overview
- `ansible/playbooks/services/ADGUARD_DEPLOYMENT_GUIDE.md` - Example service deployment
- `ansible/group_vars/all.yml` - Common configuration and container settings
- `README.md` - Project overview and quick start guide

## Context7 Documentation Loading

**IMPORTANT**: Context7 is an MCP server that provides up-to-date, version-specific code documentation and examples directly from source libraries. This eliminates outdated or hallucinated code examples by fetching real-time documentation.

### What is Context7?

Context7 is a Model Context Protocol (MCP) server designed to provide:
- Real-time, accurate documentation pulled directly from source libraries
- Version-specific code examples and API references
- Current best practices and implementation patterns
- Support for multiple libraries and frameworks

### How to Use Context7 in Claude Code

1. **Search for Libraries**: Use `mcp__context7__resolve-library-id` to find available documentation
   ```
   Function: mcp__context7__resolve-library-id
   Parameter: libraryName (e.g., "ansible", "react", "fastapi")
   
   Returns: List of matching libraries with:
   - Library ID (Context7-compatible identifier)
   - Name and description
   - Number of code snippets available
   - Trust score (reliability indicator)
   - Available versions (if applicable)
   ```

2. **Load Documentation**: Use `mcp__context7__get-library-docs` with the library ID
   ```
   Function: mcp__context7__get-library-docs
   Parameters:
   - context7CompatibleLibraryID: The exact ID from resolve-library-id
   - tokens: Maximum tokens to retrieve (default: 10000)
   - topic: Optional topic focus (e.g., "hooks", "routing")
   
   Example: Load /ansible/ansible-documentation with 10000 tokens
   ```

### Best Practices for Using Context7

1. **Always Start with Context7**: When working on any technical task, immediately search for and load relevant documentation
2. **Choose Libraries Wisely**: Select libraries based on:
   - **Trust Score**: Prefer scores of 7-10 (more authoritative)
   - **Code Snippets**: More snippets = better coverage
   - **Name Match**: Exact matches are usually best
   - **Version**: Use specific versions if the user mentions them
3. **Load Multiple Sources**: For complex tasks, load documentation from multiple related libraries
4. **Use Topic Filtering**: When you need specific information, use the `topic` parameter to focus results

### Required Documentation for This Project

1. **Ansible Documentation**: 
   ```
   Library ID: /ansible/ansible-documentation
   Trust Score: 9.3
   Code Snippets: 2366
   Description: Core Ansible documentation with comprehensive examples
   ```

2. **Community Proxmox Collection**:
   ```
   Library ID: /ansible-collections/community.proxmox
   Description: Proxmox integration modules for Ansible
   ```

3. **Proxmox VE Documentation**:
   ```
   Library ID: /proxmox/pve-docs
   Trust Score: 8.2
   Code Snippets: 1486
   Description: Official Proxmox VE documentation
   ```

### Example Context7 Workflow

```
User: "Help me create a FastAPI application with authentication"

Claude Code Actions:
1. Search for FastAPI documentation:
   mcp__context7__resolve-library-id("fastapi")
   
2. Load FastAPI docs:
   mcp__context7__get-library-docs("/tiangolo/fastapi", tokens=10000)
   
3. Search for authentication libraries:
   mcp__context7__resolve-library-id("fastapi authentication")
   
4. Load specific auth documentation if found
5. Implement solution using current, accurate examples
```

### Common Technology Library IDs

Here are some commonly used library IDs for quick reference:
- Python: `/context7/python-3.9` (Trust: 10, Snippets: 13580)
- React: Search "react" for latest options
- Node.js: Search "node" or "nodejs"
- Docker: Search "docker"
- Kubernetes: Search "kubernetes"
- AWS: Search "aws" or specific service names

### Troubleshooting Context7

- **"Documentation not found"**: The library might not be finalized. Try searching for alternative names or related libraries
- **Empty results**: Some libraries are listed but not yet populated with documentation
- **Version-specific needs**: If a user needs a specific version, check the `Versions` field in search results

### For Future Agents

When any agent works on this codebase or discusses technical topics:
1. **Immediately search Context7** for relevant documentation before providing any code
2. **Load multiple libraries** if the task involves multiple technologies
3. **Reference loaded documentation** explicitly when implementing features
4. **Update this list** if you discover useful library IDs for this project

## Deep Thinking Requirements

### STOP AND THINK Protocol
Before ANY action (planning, coding, or responding), you MUST:

1. **PAUSE for 30-60 seconds** to consider:
   - What is the user REALLY asking for?
   - What are the hidden complexities?
   - What could go wrong?
   - Is there a simpler approach?

2. **Three Perspectives Analysis**:
   - **User Perspective**: What problem are they trying to solve?
   - **System Perspective**: How does this fit the architecture?
   - **Future Perspective**: How will this decision age?

3. **Document Your Thinking**:
   - Use the feature documentation structure (see below)
   - Write out ALL options considered
   - Explain WHY you rejected alternatives
   - This creates a decision trail

### Thinking Harder Checklist:
- [ ] Did I load Context7 docs BEFORE forming opinions?
- [ ] Did I consider at least 3 different approaches?
- [ ] Did I question every assumption?
- [ ] Did I look for existing solutions first?
- [ ] Did I consider the maintenance burden?
- [ ] Did I think about edge cases and failures?

## Context7-First Thinking

### RULE: No Assumptions Without Documentation
1. **ALWAYS start with Context7** - even for "simple" tasks
2. **Load multiple sources** to get different perspectives
3. **Read examples** before designing solutions
4. **Challenge your memory** - docs might have better ways

### Thinking With Context7:
```
User asks for feature X
↓
STOP - Load Context7 docs for X, related tools, and alternatives
↓
Read and analyze multiple approaches from docs
↓
ONLY THEN start thinking about implementation
```

### Required Context7 Loads by Task:
- **Any Ansible work**: Load ansible + relevant collections + best practices
- **Any scripting**: Load shell/bash + coreutils + error handling guides
- **Any container work**: Load docker + compose + security practices
- **Any Proxmox work**: Load proxmox + API + ansible integration

## Documentation-Driven Thinking

### MANDATORY: Create Feature Doc First
Path: `documentation/features/[feature-name]/`

Structure:
```
documentation/features/[feature-name]/
├── README.md           # Overview and current status
├── analysis.md         # Deep thinking documentation
├── implementation.md   # Chosen approach with rationale
├── alternatives.md     # Rejected approaches and why
└── testing.md         # How we'll verify it works
```

### analysis.md Template:
```markdown
# Deep Analysis: [Feature Name]

## Initial Thoughts (Before Research)
[Write your first instincts - these might be wrong!]

## Context7 Research Performed
- Loaded: [library 1] - Key insights: ...
- Loaded: [library 2] - Key insights: ...

## Problem Decomposition
1. Core problem: ...
2. Sub-problems: ...
3. Hidden complexities discovered: ...

## Stakeholder Analysis
- User needs: ...
- System constraints: ...
- Future implications: ...

## Risk Analysis
- What could break: ...
- Security concerns: ...
- Performance impacts: ...

## Simplicity Check
- Simplest possible solution: ...
- Why we can/cannot use it: ...
```

## Planning as Thinking Exercise

### TodoWrite as Thinking Tool
Don't just list tasks - use todos to THINK THROUGH the problem:

1. **Break Down Until It Hurts**:
   - Each todo should be <15 minutes of work
   - If unsure how to do it, break it down more
   - This forces you to think through details

2. **Question Each Todo**:
   - Is this necessary?
   - What depends on this?
   - What could go wrong?
   - Is there a simpler way?

3. **Order Reveals Dependencies**:
   - Arrange todos to surface hidden dependencies
   - This often reveals flawed assumptions

### Example Thinking Through Todos:
```
BAD: "Implement OPNsense deployment"

GOOD:
1. Research OPNsense VM requirements in docs
2. Analyze existing VM creation patterns
3. Document network architecture decisions
4. Create feature documentation structure
5. Design Ansible role variables
6. Plan testing approach
7. Consider rollback strategy
[... each todo forces specific thinking]
```

## Simplicity Through Deep Thinking

### The Simplicity Paradox
Simple solutions require the MOST thinking, not the least.

### Simplicity Thinking Process:
1. **First Solution**: What comes to mind immediately?
2. **Complex Solution**: What would "enterprise" do?
3. **Stupid Simple**: What would a bash one-liner do?
4. **Right Simple**: What's the sweet spot?

### Questions for Simpler Code:
- Can existing tools do this?
- Are we inventing problems?
- What if we just... didn't?
- Would a config file suffice?
- Is this flexibility actually needed?

### Document Simplicity Decisions:
In implementation.md, always include:
```markdown
## Simplicity Analysis
- Initial approach: [complex thing]
- Simplified to: [simpler thing]
- Because: [specific reason]
- Trade-offs accepted: [what we gave up]
```

## Thinking Accountability

### Every Significant Decision Requires:
1. **A Feature Documentation Set** (in documentation/features/[feature-name]/)
2. **Context7 Evidence** (what docs influenced this?)
3. **Alternative Analysis** (what else was considered?)
4. **Simplicity Justification** (why this level of complexity?)

### Thinking Review Checklist:
Before presenting ANY plan:
- [ ] Have I spent at least 5 minutes just thinking?
- [ ] Have I loaded and read relevant Context7 docs?
- [ ] Have I written out my thinking process?
- [ ] Have I considered simpler alternatives?
- [ ] Have I planned for failure cases?
- [ ] Would I be happy maintaining this in 6 months?

### Red Flags That Indicate More Thinking Needed:
- "This should work" → Think about failure modes
- "It's standard practice" → Load Context7 and verify
- "We'll figure it out later" → Think through it now
- "This is temporary" → Design it properly anyway

## Thinking Harder in Practice

### The Three-Read Rule:
1. Read the user's request
2. Read it again, looking for implicit requirements
3. Read it a third time, questioning your understanding

### The Five Whys for Features:
1. Why do they want this feature?
2. Why is that important?
3. Why now?
4. Why this way?
5. Why not something simpler?

### The Context7 Cascade:
1. Load primary documentation
2. Load related/alternative solutions
3. Load anti-patterns and what to avoid
4. Read examples of both good and bad approaches
5. Only THEN start forming opinions

### The Simplicity Test:
Can you explain your solution to someone unfamiliar with the project in under 2 minutes? If not, it might be too complex.