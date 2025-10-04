# PrivateBox — CLAUDE.md (Trimmed LLM Guide)

Purpose: Repo-local guardrails for LLMs (Claude, etc.). Keep changes aligned with flow, security, and end state.

## Product Context — CRITICAL
**PrivateBox is a commercial consumer appliance, NOT a homelab project.**

- **Business**: SubRosa ApS (Denmark) selling pre-configured firewall appliances to consumers
- **Hardware**: Intel N150 mini-PC (16GB RAM, 256GB SSD, dual NICs) - €399 retail
- **Target users**: Privacy-conscious consumers and technical enthusiasts who value time over DIY
- **Key selling points**: No subscriptions, fully open source, physical ownership, no cloud dependencies
- **Market**: Direct-to-consumer, EU/Denmark focus, launching late 2025

### Why This Matters for Design Decisions
- **Recovery system is mandatory**: Customers need appliance-like factory reset without vendor support
- **Offline operation required**: Customer's network may be broken when they need recovery
- **Support must scale**: Documentation-first, no phone support, community-driven
- **Professional quality**: This competes with Firewalla ($229-459) and Ubiquiti - corner-cutting shows
- **Regulatory compliance**: CE marking, WEEE registration, 2-year EU warranty, GDPR by design
- **Physical console access**: Intel N150 hardware has VGA/HDMI, USB keyboard support guaranteed

### Design Implications
1. Recovery infrastructure (7 partitions, encrypted vault, immutable OS) is **appropriately thorough**, not over-engineered
2. "Golden image timing" matters - customers expect consistent experience
3. Offline asset storage prevents dependency on GitHub/internet during recovery
4. Physical-only recovery prevents remote attacks on consumer devices
5. Every technical decision impacts support burden and customer satisfaction

## Golden Rules
- Be concise and surgical; prefer small, verifiable diffs.
- Ansible-first; Bash only when modules fall short.
- Idempotent and deterministic; add retries/timeouts; write logs and markers.
- Never commit plaintext secrets. Use Ansible Vault and Semaphore environments.
- **Always commit and push changes immediately** - Semaphore pulls from GitHub; uncommitted code won't deploy.

## Target End State
- One command on Proxmox boots a Debian 13 management VM.
- Inside VM: Portainer (:9000) and Semaphore (:3000) running.
- Semaphore: project, repo, SSH keys, environments, and a "Generate Templates" task present.
- Services deployed via Semaphore templates (AdGuard now; more later).
- DNS: AdGuard (10.10.20.10:53) → Quad9 (primary, port 53) → Unbound fallback (10.10.20.1:53).
- TLS: external domain, Caddy DNS‑01 wildcard, split‑horizon DNS (no public A records).
- All services exposed only on management VM IP (via Podman port mapping).

## Platform & Constraints
- Proxmox: latest only. Hardware: Intel N150 with 16GB RAM.
- VM OS: Debian 13 cloud image.
- Bridges: `vmbr0` = WAN, `vmbr1` = LAN (VLAN-aware).
- Network design: See `documentation/network-architecture/vlan-design.md` for complete architecture.
- OPNsense: use VM template approach (manual config → convert to template → store on GitHub).

## Flow Summary
1. Quickstart → `bootstrap/bootstrap.sh`.
2. Phase 1: detect network, generate config, Proxmox token, verify storage.
3. Phase 2: download image, write cloud‑init, create VM, set static IP, start.
4. Phase 3: install Podman; configure Portainer/Semaphore (Quadlet); seed admin; Semaphore API setup; template‑sync task.
5. Phase 4: health checks; output access; write logs/markers.

## Quickstart Command
- Run from your workstation to bootstrap on a Proxmox host at `.10`:
  - `ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"`
  - Script auto-detects network and configures everything. Check `/tmp/privatebox-config.conf` if you need different settings.
  - **IMPORTANT**: Always run in foreground for at least 10 minutes. Expected completion: ~7 minutes.
  - Do NOT run in background - need to monitor progress and handle any interactive prompts.

## TLS & DNS
- DNS Architecture: AdGuard (10.10.20.10:53) filters ads → Quad9 (primary, port 53) → Unbound fallback (10.10.20.1:53).
- Blocklists: OISD Basic + Steven Black Hosts (auto-configured).
- Use dedicated subdomain (e.g., `pb.example.com`) → wildcard `*.pb.example.com` via DNS‑01.
- Split‑horizon DNS: internal A records only (AdGuard); no public exposure.
- Store DNS API creds in Semaphore environments for Caddy.
- All services bind to management VM IP (see `documentation/vlan-design.md`).

## Secrets
- Ansible Vault for static/encrypted repo data.
- Vault password in Semaphore env (e.g., `ANSIBLE_VAULT_PASSWORD`) → set `ANSIBLE_VAULT_PASSWORD_FILE` at job start.
- Generate runtime creds once; store in `/etc/privatebox/config.env`.
- Remove transient keys after upload.

## Semaphore Integration
- Bootstrap creates project, repo, SSH keys, environments, and the “Generate Templates” task.
- `tools/generate-templates.py` reads `vars_prompt` with `semaphore_*` and builds typed templates.

## Semaphore API (Cookie Auth) — IMPORTANT
- Semaphore ONLY accessible via Services VLAN at 10.10.20.10:3000 (not from workstation).
- Access requires double-hop: workstation → Proxmox (.10) → Semaphore (10.10.20.10).
- Use session cookies (not hardcoded tokens) when scripting against Semaphore.

### Cookie Management
- Check for existing cookie first: `ssh root@192.168.1.10 "test -f /tmp/sem.cookies && echo EXISTS"`
- If no cookie or expired, check for password:
  - From Proxmox: look in `/etc/privatebox/config.env` for SERVICES_PASSWORD
  - From workstation: may need to retrieve from Semaphore ServicePasswords environment (if already have access)
  - Last resort: check bootstrap logs or ask user
- Login to get session cookie (from Proxmox):
  - `curl -sS --cookie-jar /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"auth":"admin","password":"<SERVICES_PASSWORD>"}' http://10.10.20.10:3000/api/auth/login`
- Test cookie validity:
  - `curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/user | grep -q '"admin":true' && echo VALID`

### API Access from Workstation (Double-Hop)
- All commands via SSH to Proxmox: `ssh root@192.168.1.10 "curl ..."`
- Example: `ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/projects"`

### Curl Examples (Run from Proxmox)
- Login and store cookie:
  - `curl -sS --cookie-jar /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"auth":"admin","password":"<SERVICES_PASSWORD>"}' http://10.10.20.10:3000/api/auth/login`
- Get project id (PID):
  - `curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/projects`
- List environments (contains passwords):
  - `curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/environment`
- List templates for a project:
  - `curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/<PID>/templates`
- Find a template id (TID) by name with jq:
  - `TID=$(curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/<PID>/templates | jq -r '.[] | select(.name=="Generate Templates") | .id')`
- Run a template (creates a task):
  - `curl -sS --cookie /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"template_id":<TID>,"debug":false,"dry_run":false}' http://10.10.20.10:3000/api/project/<PID>/tasks`
- Check tasks/status:
  - `curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/<PID>/tasks`

Notes
- Semaphore NOT accessible from workstation directly (blocked by VLAN isolation).
- In Management VM: use `localhost:3000` and `source /etc/privatebox/config.env`.
- In Ansible playbooks on Proxmox: delegate to localhost or use shell commands with stored cookies.

## Coding Checklist
- Idempotent? Retries/timeouts? Clear errors?
- Exposed only on VM IP (via Podman PublishAddress)?
- Secrets via Vault/Semaphore? No plaintext?
- Logs and completion markers written?
- Docs updated if flow/UX changed?

## See Also
- Extended guide: `documentation/LLM-GUIDE.md` (deeper details and rationale)
- Repo pointers: `bootstrap/*`, `ansible/playbooks/services/*`, `documentation/*`
