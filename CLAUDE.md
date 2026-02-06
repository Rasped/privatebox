# PrivateBox - CLAUDE.md (Trimmed LLM Guide)

Purpose: Repo-local guardrails for LLMs (Claude, etc.). Keep changes aligned with flow, security, and end state.

## Product context - CRITICAL
**PrivateBox is a commercial consumer appliance, NOT a homelab project.**

- **Business**: SubRosa ApS (Denmark) selling pre-configured firewall appliances to consumers
- **Hardware**: Intel N150 mini-PC (16GB RAM, 256GB SSD, dual NICs) - €399 retail
- **Target users**: Privacy-conscious consumers and technical enthusiasts who value time over DIY
- **Key selling points**: No subscriptions, fully open source, physical ownership, no cloud dependencies
- **Market**: Direct-to-consumer, EU/Denmark focus, launching late 2025

### Why this matters for design decisions
- **Recovery system is mandatory**: Customers need appliance-like factory reset without vendor support
- **Offline operation required**: Customer's network may be broken when they need recovery
- **Support must scale**: Documentation-first, no phone support, community-driven
- **Professional quality**: This competes with Firewalla ($229-459) and Ubiquiti - corner-cutting shows
- **Regulatory compliance**: CE marking, WEEE registration, 2-year EU warranty, GDPR by design
- **Physical console access**: Intel N150 hardware has VGA/HDMI, USB keyboard support guaranteed

### Design implications
1. Recovery infrastructure (7 partitions, encrypted vault, immutable OS) is **appropriately thorough**, not over-engineered
2. "Golden image timing" matters - customers expect consistent experience
3. Offline asset storage prevents dependency on GitHub/internet during recovery
4. Physical-only recovery prevents remote attacks on consumer devices
5. Every technical decision impacts support burden and customer satisfaction

## Golden rules
- Be concise and surgical; prefer small, verifiable diffs.
- Ansible-first; Bash only when modules fall short.
- Idempotent and deterministic; add retries/timeouts; write logs and markers.
- Never commit plaintext secrets. Use Ansible Vault and Semaphore environments.
- **Always commit and push changes immediately** - Semaphore pulls from GitHub; uncommitted code won't deploy.
- **On errors: investigate only** - Present problem clearly, ask for guidance. Don't attempt fixes without direction.
- **NO Claude attribution in commits** - Do not add "Generated with Claude Code" or "Co-Authored-By: Claude" to commit messages.

## Target end state
- One command on Proxmox boots a Debian 13 management VM.
- Inside VM: Portainer (:9000) and Semaphore (:3000) running.
- Semaphore: project, repo, SSH keys, environments, and a "Generate Templates" task present.
- Services deployed via Semaphore templates (AdGuard now; more later).
- DNS: AdGuard (10.10.20.10:53) → Quad9 (primary, port 53) → Unbound fallback (10.10.20.1:53).
- TLS: external domain, Caddy DNS‑01 wildcard, split‑horizon DNS (no public A records).
- All services exposed only on management VM IP (via Podman port mapping).

## Platform & constraints
- Proxmox: latest only. Hardware: Intel N150 with 16GB RAM.
- VM OS: Debian 13 cloud image.
- Bridges: `vmbr0` = WAN, `vmbr1` = LAN (VLAN-aware).
- Network design: See `/docs/architecture/network-architecture/overview.md` for complete architecture.
- OPNsense: use VM template approach (manual config → convert to template → store on GitHub).

## Infrastructure map
### VMs
- **VM 9000** - Management VM (Debian 13) at 10.10.20.10 - hosts all containerized services
- **VM 100** - OPNsense (firewall/router) at 10.10.20.1 (Services), 10.10.10.1 (Trusted LAN)
- **Proxmox Host** - at 10.10.20.20:8006 (not a VM, hypervisor itself)
- **Test Server** - `privatebox-test-102` (Intel N150 hardware, Proxmox VE) - bare-metal test box
  - Production IP: `10.10.20.102` (Services VLAN, no internet access)
  - **Workaround**: Server's single NIC is on a different L2 segment than 192.168.0.1 gateway. To get internet, temporarily move to `192.168.0.102/24` with gateway `192.168.0.1`:
    ```
    ssh root@10.10.20.102 "ip addr del 10.10.20.102/24 dev vmbr0; ip addr add 192.168.0.102/24 dev vmbr0; ip route replace default via 192.168.0.1; echo 'nameserver 192.168.0.1' > /etc/resolv.conf"
    ```
  - Then reconnect via `ssh root@192.168.0.102`
  - This is runtime only and resets on reboot. Access from workstation requires `10.10.20.250` alias on Mac's `en0`.

### Services (all on management VM)
**Web services:** All accessible via `https://*.lan` domains (privatebox, portainer, semaphore, adguard, opnsense, proxmox)
- See `ansible/files/caddy/Caddyfile.j2` for complete proxy configuration
- Caddy reverse proxy terminates TLS with self-signed certs
- Caddy health endpoint: `http://10.10.20.10/health` (monitoring)

**Non-web services:**
- **AdGuard DNS** - `10.10.20.10:53` - DNS filtering (web UI at adguard.lan)

### Domain access
- Current: all services use `.lan` domains (e.g., portainer.lan, semaphore.lan)
- DNS rewrites in AdGuard map `.lan` → 10.10.20.10 (Management VM)
- Caddy provides self-signed TLS certs for `.lan` domains
- Future: add customer deSEC.io domains (e.g., portainer.customer.dedyn.io) with Let's Encrypt certs via DNS-01

## Flow summary
1. Quickstart → `bootstrap/bootstrap.sh`.
2. Phase 1: detect network, generate config, Proxmox token, verify storage.
3. Phase 2: download image, write cloud‑init, create VM, set static IP, start.
4. Phase 3: install Podman; configure Portainer/Semaphore (Quadlet); seed admin; Semaphore API setup; template‑sync task.
5. Phase 4: health checks; output access; write logs/markers.

## Quickstart command
- Run from your workstation to bootstrap on a Proxmox host at `.10`:
  - `ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"`
  - Script auto-detects network and configures everything. Check `/tmp/privatebox-config.conf` if you need different settings.
  - **IMPORTANT**: Always run in foreground for at least 15 minutes. Expected completion: ~15 minutes.
  - Do NOT run in background - need to monitor progress and handle any interactive prompts.
  - **For Claude Code**: Use timeout of 1200000ms (20 minutes) minimum. The Bash tool documentation incorrectly states max is 600000ms (10 minutes) - ignore that, use 20+ minutes.

## TLS & DNS
- DNS Architecture: AdGuard (10.10.20.10:53) filters ads → Quad9 (primary, port 53) → Unbound fallback (10.10.20.1:53).
- Blocklists: OISD Basic + Steven Black Hosts (auto-configured).
- Use dedicated subdomain (e.g., `pb.example.com`) → wildcard `*.pb.example.com` via DNS‑01.
- Split‑horizon DNS: internal A records only (AdGuard); no public exposure.
- Store DNS API creds in Semaphore environments for Caddy.
- All services bind to management VM IP (see `/docs/architecture/network-architecture/overview.md`).

## Secrets
- Ansible Vault for static/encrypted repo data.
- Vault password in Semaphore env (e.g., `ANSIBLE_VAULT_PASSWORD`) → set `ANSIBLE_VAULT_PASSWORD_FILE` at job start.
- Generate runtime creds once; store in `/etc/privatebox/config.env`.
- Remove transient keys after upload.

## Semaphore integration
- Bootstrap creates project, repo, SSH keys, environments, and the “Generate Templates” task.
- `tools/generate-templates.py` reads `vars_prompt` with `semaphore_*` and builds typed templates.

## Semaphore API (cookie auth) - IMPORTANT
- Semaphore ONLY accessible via Services VLAN at https://10.10.20.10:2443 (not from workstation).
- Access requires double-hop: workstation → Proxmox (.10) → Semaphore (10.10.20.10).
- Use session cookies (not hardcoded tokens) when scripting against Semaphore.
- All API calls use HTTPS with `-k` flag (self-signed cert).

### Cookie management
- Check for existing cookie first: `ssh root@192.168.1.10 "test -f /tmp/sem.cookies && echo EXISTS"`
- If no cookie or expired, check for password:
  - From Proxmox: look in `/tmp/privatebox-config.conf` for SERVICES_PASSWORD
  - From workstation: may need to retrieve from Semaphore privatebox-env-passwords environment (if already have access)
  - Last resort: check bootstrap logs or ask user
- Login to get session cookie (from Proxmox):
  - `curl -sSk --cookie-jar /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"auth":"admin","password":"<SERVICES_PASSWORD>"}' https://10.10.20.10:2443/api/auth/login`
- Test cookie validity:
  - `curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/user | grep -q '"admin":true' && echo VALID`

### API access from workstation (Double-Hop)
- All commands via SSH to Proxmox: `ssh root@192.168.1.10 "curl ..."`
- Example: `ssh root@192.168.1.10 "curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/projects"`

### Curl examples (run from Proxmox)
- Login and store cookie:
  - `curl -sSk --cookie-jar /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"auth":"admin","password":"<SERVICES_PASSWORD>"}' https://10.10.20.10:2443/api/auth/login`
- Get project id (PID):
  - `curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/projects`
- List environments (metadata only, secrets hidden):
  - `curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/1/environment`
  - NOTE: Semaphore API does NOT expose secret values via API for security. Only names and structure are visible.
- List templates for a project:
  - `curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/<PID>/templates`
- Find a template id (TID) by name with jq:
  - `TID=$(curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/<PID>/templates | jq -r '.[] | select(.name=="Generate Templates") | .id')`
- Run a template (creates a task):
  - `curl -sSk --cookie /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"template_id":<TID>,"debug":false,"dry_run":false}' https://10.10.20.10:2443/api/project/<PID>/tasks`
- Check tasks/status:
  - `curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/<PID>/tasks`

Notes
- Semaphore NOT accessible from workstation directly (blocked by VLAN isolation).
- In Management VM: use `privatebox-local:3000` and `source /etc/privatebox/config.env`.
- In Ansible playbooks on Proxmox: delegate to privatebox-local or use shell commands with stored cookies.

## Coding checklist
- Idempotent? Retries/timeouts? Clear errors?
- Exposed only on VM IP (via Podman PublishAddress)?
- Secrets via Vault/Semaphore? No plaintext?
- Logs and completion markers written?
- Docs updated if flow/UX changed?

## Documentation
- User guides: `/docs/guides/getting-started/` and `/docs/guides/advanced/`
- Architecture & ADRs: `/docs/architecture/` (feature-specific folders with overview.md and adr-*.md files)
- Contributing: `/docs/contributing/`
- Style guide: `/docs/style-guide.md`

## See also
- Code: `bootstrap/*`, `ansible/playbooks/services/*`, `tools/*`
- Architecture docs: `/docs/architecture/` for design decisions and system details