# Repository Guidelines

## Project structure & module organization
- `quickstart.sh` is the entrypoint for full deployments on Proxmox.
- `bootstrap/` hosts provisioning scripts (`prepare-host.sh`, `create-vm.sh`, `setup-guest.sh`) and validation helpers.
- `ansible/` holds service playbooks under `playbooks/services/` and infrastructure runs under `playbooks/infrastructure/`, with supporting assets in `files/` and `templates/`.
- `tools/` stores Python orchestration utilities that Semaphore runs to chain playbooks.
- `docs/` captures user and contributor docs; align with `docs/style-guide.md` when updating prose.
- `collections/` tracks vendored Ansible Galaxy content.

## Build, test, and development commands
- `bash bootstrap/validate-files.sh` verifies required images, checksums, and template placeholders before a run.
- `bash bootstrap/test-bootstrap.sh` rehearses the full flow on a Proxmox lab host (VMID 9000).
- `bash bootstrap/verify-install.sh` runs post-install smoke checks from the management VM.
- `bash tools/validate-dns-stack.sh` confirms AdGuard DNS rewrites and related services.
- `ansible-playbook ansible/playbooks/services/adguard-deploy.yml -i <inventory.ini> --check` dry-runs a service once your inventory defines `privatebox-management`.

## Coding style & naming conventions
Use Bash with `#!/bin/bash`, `set -euo pipefail`, two-space indentation, and kebab-case filenames (`deploy-opnsense.sh`). Python utilities in `tools/` follow PEP 8 with four-space indentation; keep dependencies limited to the `requests` stack. Ansible YAML uses two-space indentation, descriptive play names (`Service N: Action`), and `service-action.yml` filenames as shown in `ansible/README.md`. Templates and static assets belong in `ansible/templates/` or `ansible/files/quadlet/`; never commit host-specific secrets.

## Testing guidelines
Favor reproducible shell scripts over ad-hoc commands. New validation helpers should live beside `bootstrap/validate-files.sh`, emit clear status lines, and respect `set -euo pipefail`. When touching Ansible playbooks, run them with `--check` and capture output logs for review. For DNS or TLS changes, pair `ansible-playbook` runs with `bash tools/validate-dns-stack.sh` to confirm downstream effects.

## Commit & pull request guidelines
Follow Conventional Commits (`feat:`, `fix:`, `docs:`, etc.) as enforced in `CONTRIBUTING.md`; keep commits focused and rebase onto `main` before opening a PR. Pull requests should link related issues, describe the environment used for testing (e.g., Proxmox version, dry-run logs), and include screenshots or command output when UI or DNS behavior changes. Request reviews early if bootstrapping or playbook sequencing is affected.

## Agent coordination
Read `CLAUDE.md` before coordinating with other automation agents; follow its handoff rules when updating Semaphore workflows.

## Security & configuration tips
Redact all tokens, passwords, and IPs from committed files; use the `.j2` templates under `ansible/templates/` for sample configurations. Run `debug-semaphore-passwords.sh` and `verify-semaphore-passwords.sh` only on trusted hosts.
