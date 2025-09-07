# PrivateBox — CLAUDE.md (Trimmed LLM Guide)

Purpose: Repo-local guardrails for LLMs (Claude, etc.). Keep changes aligned with flow, security, and end state.

## Golden Rules
- Be concise and surgical; prefer small, verifiable diffs.
- Ansible-first; Bash only when modules fall short.
- Idempotent and deterministic; add retries/timeouts; write logs and markers.
- Never commit plaintext secrets. Use Ansible Vault and Semaphore environments.

## Target End State
- One command on Proxmox boots a Debian 13 management VM.
- Inside VM: Portainer (:9000) and Semaphore (:3000) running.
- Semaphore: project, repo, SSH keys, environments, and a “Generate Templates” task present.
- Services deployed via Semaphore templates (AdGuard now; more later).
- TLS: external domain, Caddy DNS‑01 wildcard, split‑horizon DNS (no public A records).
- All services bind to the management VM IP (not 0.0.0.0).

## Platform & Constraints
- Proxmox: latest only. Hardware: Intel N100 target.
- VM OS: Debian 13 cloud image.
- Bridges: `vmbr0` = WAN, `vmbr1` = LAN (VLAN-aware).
- Network: Default LAN (untagged) = Trusted (10.10.10.0/24), VLAN 20 = Services (10.10.20.0/24).
- OPNsense: use VM template approach (manual config → convert to template → store on GitHub).

## Flow Summary
1. Quickstart → `bootstrap/bootstrap.sh`.
2. Phase 1: detect network, generate config, Proxmox token, verify storage.
3. Phase 2: download image, write cloud‑init, create VM, set static IP, start.
4. Phase 3: install Podman; configure Portainer/Semaphore (Quadlet); seed admin; Semaphore API setup; template‑sync task.
5. Phase 4: health checks; output access; write logs/markers.

## Quickstart Command
- Run from your workstation to bootstrap on a Proxmox host at `.10`:
  - `ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash -s -- --yes"`
  - Add `--dry-run` to generate config only; edit `/tmp/privatebox-config.conf` if you need a different VM IP.

## Networking & TLS
- Services on VLAN 20 (10.10.20.0/24): Proxmox, Management VM, AdGuard.
- Trusted devices on default LAN (10.10.10.0/24, untagged) for consumer router compatibility.
- Bind all services to the management VM IP (10.10.20.20).
- Use dedicated subdomain (e.g., `pb.example.com`) → wildcard `*.pb.example.com` via DNS‑01.
- Split‑horizon DNS: internal A records only (AdGuard); no public exposure.
- Store DNS API creds in Semaphore environments for Caddy.

## Secrets
- Ansible Vault for static/encrypted repo data.
- Vault password in Semaphore env (e.g., `ANSIBLE_VAULT_PASSWORD`) → set `ANSIBLE_VAULT_PASSWORD_FILE` at job start.
- Generate runtime creds once; store in `/etc/privatebox/config.env`.
- Remove transient keys after upload.

## Semaphore Integration
- Bootstrap creates project, repo, SSH keys, environments, and the “Generate Templates” task.
- `tools/generate-templates.py` reads `vars_prompt` with `semaphore_*` and builds typed templates.

## Semaphore API (Cookie Auth) — IMPORTANT
- Use session cookies (not hardcoded tokens) when scripting against Semaphore.
- Login to get a session cookie:
  - `curl -s -c cookies.txt -X POST -H 'Content-Type: application/json' -d '{"auth":"admin","password":"<SERVICES_PASSWORD>"}' http://<VM-IP>:3000/api/auth/login`
- Call APIs using the cookie:
  - `curl -s -b cookies.txt http://<VM-IP>:3000/api/projects`
- In-VM access uses localhost: `http://localhost:3000/…` and `SERVICES_PASSWORD` from `/etc/privatebox/config.env`.
- In Bash, prefer a helper that retries and returns `Cookie: semaphore=<value>`; see `bootstrap/lib/semaphore-api.sh` (functions `get_admin_session`, `make_api_request`).
- In Ansible, use `shell`/`command` with curl for cookie handling, or manage a `Cookie` header captured from the login step.

### Curl Examples
- Login and store cookie:
  - `curl -sS --cookie-jar /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"auth":"admin","password":"<SERVICES_PASSWORD>"}' http://<HOST>:3000/api/auth/login -i`
- Get project id (PID):
  - `curl -sS --cookie /tmp/sem.cookies http://<HOST>:3000/api/projects`
- List templates for a project:
  - `curl -sS --cookie /tmp/sem.cookies http://<HOST>:3000/api/project/<PID>/templates`
- Find a template id (TID) by name with jq:
  - `TID=$(curl -sS --cookie /tmp/sem.cookies http://<HOST>:3000/api/project/<PID>/templates | jq -r '.[] | select(.name=="Generate Templates") | .id')`
- Run a template (creates a task):
  - `curl -sS --cookie /tmp/sem.cookies -X POST -H 'Content-Type: application/json' -d '{"template_id":<TID>,"debug":false,"dry_run":false}' http://<HOST>:3000/api/project/<PID>/tasks -i`
- Check tasks/status:
  - `curl -sS --cookie /tmp/sem.cookies http://<HOST>:3000/api/project/<PID>/tasks`

Notes
- Use `<HOST>=192.168.1.20:3000` from outside, or `localhost:3000` inside the VM.
- Inside VM you can `source /etc/privatebox/config.env` and use `$SERVICES_PASSWORD`.

## Coding Checklist
- Idempotent? Retries/timeouts? Clear errors?
- Bound to VM IP (no `0.0.0.0`)?
- Secrets via Vault/Semaphore? No plaintext?
- Logs and completion markers written?
- Docs updated if flow/UX changed?

## See Also
- Extended guide: `documentation/LLM-GUIDE.md` (deeper details and rationale)
- Repo pointers: `bootstrap/*`, `ansible/playbooks/services/*`, `documentation/*`
