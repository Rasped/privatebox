# Contributing to PrivateBox

Thank you for your interest in contributing to PrivateBox! This guide will help you get started.

## Code of conduct

PrivateBox is a commercial open-source project. We expect all contributors to:
- Be respectful and professional
- Focus on technical merit
- Respect the project's commercial goals and architectural decisions

## Getting started

### Development environment

1. **Hardware requirements**
   - Proxmox VE server (or development VM)
   - Minimum: 16GB RAM, 4 cores, 100GB storage
   - Recommended: Intel N150 or equivalent for testing

2. **Software requirements**
   - Git
   - Ansible 2.15+
   - Python 3.11+
   - SSH access to Proxmox host

3. **Setup**
   ```bash
   git clone https://github.com/Rasped/privatebox.git
   cd privatebox
   # Follow quickstart guide for bootstrap
   ```

### Repository structure

```
privatebox/
├── ansible/              # Ansible playbooks and roles
│   ├── playbooks/       # Service deployment playbooks
│   ├── files/           # Configuration templates
│   └── inventory/       # Inventory files (git-ignored)
├── bootstrap/           # Initial bootstrap scripts
├── tools/               # Helper scripts
├── docs/                # Documentation (you are here)
│   ├── guides/         # User documentation
│   ├── architecture/   # Technical architecture
│   └── contributing/   # This guide
└── CLAUDE.md           # AI assistant guidelines
```

## How to contribute

### 1. Reporting issues

Before creating an issue:
- Check existing issues for duplicates
- Verify the issue on latest version
- Collect relevant logs and configuration

Include:
- PrivateBox version
- Hardware specs (Intel N150, custom, VM)
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs

### 2. Suggesting features

Feature requests should:
- Align with product vision (privacy-focused consumer appliance)
- Consider support burden (documentation-first support model)
- Include use cases and user stories
- Propose implementation approach (optional)

### 3. Contributing code

#### Workflow

1. **Fork and clone**
   ```bash
   git clone https://github.com/YOUR-USERNAME/privatebox.git
   cd privatebox
   git remote add upstream https://github.com/Rasped/privatebox.git
   ```

2. **Create feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make changes**
   - Follow coding standards (see below)
   - Write/update tests
   - Update documentation

4. **Test thoroughly**
   - Test on clean Proxmox install
   - Verify idempotency (run playbook twice)
   - Check for errors in logs

5. **Commit**
   ```bash
   git add .
   git commit -m "Add feature: brief description"
   ```

6. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   # Open PR on GitHub
   ```

#### Code standards

**Ansible playbooks:**
- Idempotent - safe to run multiple times
- Use handlers for service restarts
- Include error handling and retries
- Add descriptive task names
- Use variables for configurability
- Document non-obvious logic

**Bash scripts:**
- Use `set -euo pipefail`
- Quote all variables
- Validate inputs
- Log progress and errors
- Use functions for clarity
- Include usage/help message

**Python scripts:**
- Follow PEP 8
- Type hints for function signatures
- Docstrings for modules and functions
- Use context managers (`with` statements)
- Handle errors gracefully

**General:**
- No hardcoded secrets (use Ansible Vault)
- No hardcoded IPs (use variables)
- Include comments for complex logic
- Write self-documenting code

### 4. Contributing documentation

Documentation contributions are highly valued!

#### User guides

Located in `/docs/guides/`:
- Write for non-technical users
- Include screenshots where helpful
- Provide step-by-step instructions
- Test instructions on fresh install

#### Architecture documentation

Located in `/docs/architecture/`:
- Use feature overview template
- Include frontmatter metadata
- Document decisions with ADRs
- Link to related documentation

#### Creating an ADR

When making architectural decisions:

1. **Copy template**
   ```bash
   cp docs/architecture/adr-template.md \
      docs/architecture/[feature]/adr-NNNN-title.md
   ```

2. **Fill in sections**
   - Context: Why is this decision needed?
   - Decision: What are we doing?
   - Consequences: Positive, negative, neutral
   - Alternatives: What else did we consider?

3. **Update index**
   - Add to `docs/architecture/README.md`
   - Link from feature overview

## Development guidelines

### Testing

**Before submitting PR:**
- [ ] Tested on clean Proxmox install
- [ ] Ran playbook/script twice (idempotency check)
- [ ] Checked logs for errors
- [ ] Verified services start correctly
- [ ] Tested recovery/rollback (if applicable)
- [ ] Updated documentation

### Commit messages

Format:
```
Category: Brief description (50 chars max)

Detailed explanation if needed. Wrap at 72 characters.

- Bullet points for multiple changes
- Reference issues: Fixes #123
```

Categories:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `refactor:` Code restructuring (no behavior change)
- `test:` Adding/updating tests
- `chore:` Maintenance tasks

Examples:
```
feat: Add Headscale VPN service deployment

Implements Headscale control server for self-hosted Tailscale
alternative. Includes Headplane web UI and Caddy reverse proxy
configuration.

Fixes #42
```

```
fix: Resolve AdGuard port conflict with Unbound

Changed AdGuard web UI port from 3000 to 3080 to avoid conflict
with Semaphore. Updated Caddyfile accordingly.
```

### Pull request process

1. **PR Title:** Same format as commit messages
2. **Description:**
   - What does this PR do?
   - Why is it needed?
   - How was it tested?
   - Related issues/PRs
3. **Checklist:**
   - [ ] Code follows project standards
   - [ ] Tests pass
   - [ ] Documentation updated
   - [ ] No merge conflicts
   - [ ] Commits are clean and descriptive

### Review process

- PRs require approval from maintainer
- Address feedback promptly
- Be open to suggestions
- Keep discussions technical and respectful

## Architecture decisions

Major architectural decisions require:
1. Discussion in GitHub issue or PR
2. Architecture Decision Record (ADR)
3. Update to architecture documentation
4. Consideration of commercial implications

Areas requiring extra scrutiny:
- Security changes (encryption, authentication, firewall rules)
- Recovery system changes (customer experience impact)
- Network architecture changes (backward compatibility)
- Service dependencies (offline operation requirement)

## Commercial considerations

PrivateBox is open-source but commercially sold. Consider:

**Support Impact:**
- Will this increase support burden?
- Can customers troubleshoot this themselves?
- Does documentation need updates?

**Customer Experience:**
- Does this maintain appliance-like simplicity?
- Is it optional or mandatory?
- Does it affect existing users?

**Regulatory:**
- EU compliance (CE, WEEE, GDPR)
- Does this affect data privacy?
- Any export control concerns?

## Getting help

- **Questions:** Open a GitHub Discussion
- **Bugs:** Open a GitHub Issue
- **Chat:** Join our community (link TBD)
- **Email:** contribute@privatebox.io (for sensitive issues)

## License

By contributing, you agree that your contributions will be licensed under the same license as the PrivateBox project.

## Recognition

All contributors will be acknowledged in release notes and documentation.

Thank you for contributing to PrivateBox!
