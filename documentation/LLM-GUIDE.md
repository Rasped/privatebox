# PrivateBox — LLM Implementation Guide

This guide orients LLMs contributing to PrivateBox. It defines the flow, platform assumptions, security stances, and coding guardrails so changes converge on the intended end state without surprises.

## Scope & Intent

- Audience: LLMs drafting scripts, playbooks, or docs for PrivateBox.
- Goal: Hands-off bootstrap of a privacy router stack with clear defaults, strong security, and predictable UX.

## End State (Authoritative)

- Proxmox host runs one command to bootstrap a Debian 13 management VM.
- In-VM services are up: Portainer (container UI) and Semaphore (automation).
- Semaphore is pre-configured with project, repo, SSH keys, environments, and a “Generate Templates” task.
- Privacy services (e.g., AdGuard) are deployed via Semaphore templates (point-and-click). OPNsense has staged automation; Stage 3 is not implemented yet.
- TLS uses a real domain with DNS-01 wildcard via Caddy; split-horizon DNS is provided internally (no public A records for internal hosts).
- All services bind to the management VM IP (not 0.0.0.0). Access is limited to the trusted LAN VLAN.

## Platform Assumptions

- Proxmox: latest version only.
- Management VM: Debian 13 (cloud image).
- Hardware: Intel N100 target (others may work but are not primary).
- Bridges: `vmbr0` = WAN, `vmbr1` = LAN (standard layout).
- IPs: configurable; defaults derived from detected `BASE_NETWORK` (e.g., `.20` management VM), overridable via flags/config.

## High-Level Flow

- Quickstart: `quickstart.sh` fetches the repo and runs `bootstrap/bootstrap.sh`.
- Phase 1 (Host Prep): detect network/bridges; generate config; create Proxmox API token; verify storage.
- Phase 2 (VM Provision): download Debian image; generate cloud-init snippet; create VM; set static IP; start VM.
- Phase 3 (Guest Setup via cloud-init): install Podman; configure Portainer & Semaphore via Quadlet; seed admin; configure Semaphore via API; create template-sync task.
- Phase 4 (Verify): check service health; print access info; write logs and markers.

## Automation Principles

- Hands-off: minimal prompts; safe, sane defaults.
- Idempotent: re-runs converge; no destructive surprises.
- Deterministic: explicit steps over clever abstractions.
- Observable: verbose logs, clear errors, completion markers/artifacts.
- Bounded: retries with timeouts; fail with actionable messages.

## Tooling Preferences

- Ansible-first: use modules for infra/service work and Quadlet-based containers.
  - Self-contained playbooks (no external roles); sane defaults; override via `vars_prompt`/survey or `-e`.
  - Prefer: `apt`, `systemd`, `template`, `uri`, `wait_for`, `get_url`, `copy`, `assert`, `stat`.
  - Inventory: explicit groups (`proxmox`, `container-host`). Avoid hidden/global magic.
  - Podman Quadlet: default mechanism for long-running containers.
  - Template sync: annotate `vars_prompt` with `semaphore_*` for auto template generation.
- Shell where pragmatic: Proxmox `qm` lifecycle, cloud-init snippet writing, early-boot tasks, Semaphore API (curl), image handling, password generation. Scripts must be re-runnable and log to files.

## Networking & DNS

- Binding: bind services to the management VM IP, not `0.0.0.0`, to avoid cross-VLAN/WAN exposure and port conflicts.
- DNS: AdGuard publishes split-horizon records for internal names; no public A records for internal hosts.
- Default records: use a dedicated subdomain and wildcard (see TLS Strategy). Internal names (e.g., `semaphore.<subdomain>`, `portainer.<subdomain>`, `adguard.<subdomain>`, `proxmox.<subdomain>`, `opnsense.<subdomain>`) resolve to the appropriate internal IPs.

## TLS Strategy (External Domain — Default)

- Mode: real domain with DNS-01 + wildcard via Caddy (publicly trusted certs; no client CA distribution).
- Subdomain: dedicate a neutral subdomain (e.g., `pb.example.com`) and issue `*.pb.example.com`.
- Split-horizon: do not publish public A records; AdGuard serves internal answers only.
- Secrets: store DNS provider API credentials as Semaphore environment secrets; Caddy uses them to solve DNS-01.
- Privacy: wildcard name appears in Certificate Transparency logs, but individual hostnames do not.
- Fallback (optional): if no domain provided, use Caddy internal PKI with admin device CA distribution (documented but not the end state).

## Secrets & Credentials

- Ansible Vault: default for all static/encrypted repo data; keep plaintext secrets out of the repo.
- Vault Password: store in Semaphore environment secret (e.g., `ANSIBLE_VAULT_PASSWORD`), write a temp file at job start, set `ANSIBLE_VAULT_PASSWORD_FILE` accordingly.
- Runtime Secrets: generate credentials on first run and write to `/etc/privatebox/config.env` in the VM; avoid re-generating on subsequent runs unless explicitly rotated.
- Semaphore Environments: `ServicePasswords` (ADMIN_PASSWORD, SERVICES_PASSWORD), `SemaphoreAPI` (API token), DNS provider credentials for Caddy.
- Ephemeral Keys: remove transient keys after upload (e.g., Proxmox SSH private key if embedded for initial bootstrap).

## Semaphore Integration

- Bootstrap creates project “PrivateBox”, adds repository, uploads SSH keys, creates environments, and registers a “Generate Templates” task.
- Template Sync: `tools/generate-templates.py` scans `ansible/playbooks/services/*.yml` for `vars_prompt` items with `semaphore_*` metadata and creates/updates templates with typed survey variables.
- Template Naming: “Deploy: <service>”, “Configure: <component>”.

## OPNsense Roadmap

- Stage 1/2: FreeBSD VM creation and OPNsense bootstrap exist with artifacts/markers and IP discovery.
- Stage 3 (network configuration): do not implement yet. Reserve naming, variables, and outputs, but skip execution.

## Configurability Knobs

- Quickstart flags: `--dry-run`, `--branch`, `--yes`, `--cleanup`, `--verbose`.
- Host/VM vars: VM ID/cores/memory/disk/storage, bridges, static IP, domain/subdomain, TLS mode, generated passwords.
- Service vars: per-playbook defaults; surfaced via `vars_prompt` for Semaphore surveys.

## Coding Guidelines (For LLMs)

- Be surgical: minimal, targeted diffs; match repo style and patterns.
- Prefer Ansible modules; use Bash only when a module is impractical.
- Maintain idempotency; add retries/timeouts; emit clear error messages.
- Always bind services to the management VM IP; do not expose on `0.0.0.0`.
- Keep Proxmox “latest-only” assumption and Debian 13 base.
- Use Quadlet for containers; avoid docker-compose.
- Write logs and success markers; do not proceed to OPNsense Stage 3.
- Update docs when changing flow/UX; never commit plaintext secrets.

## Success Criteria

- After bootstrap: Portainer (`:9000`) and Semaphore (`:3000`) reachable on the management VM IP.
- TLS: valid certificates for `*.subdomain.example.com` via Caddy DNS-01; internal DNS resolves to internal IPs only.
- Credentials: generated, printed, and stored in `/etc/privatebox/config.env`; secrets managed via Semaphore environments and Vault.
- Templates: “Deploy: AdGuard” runs successfully via Semaphore and results are health-checked.
- Re-runs: converge without manual repair; artifacts/logs clearly indicate state and next steps.

---

If a design choice is not covered here, prefer simpler, observable, and idempotent approaches that preserve the flow above and align with security defaults.

