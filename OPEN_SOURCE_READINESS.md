# PrivateBox — Open-Source Release Readiness Audit

**Date:** 2026-04-22
**Branch:** `claude/audit-open-source-readiness-DzOdD`
**Scope:** Full repo audit against OSS release norms (EUPL-1.2 target).
**Status:** Findings only — no changes made.

> This file is a working punch list. Remove or `.gitignore` it before the public release.

---

## Summary

| Severity | Count | Meaning |
| :--- | :---: | :--- |
| P0 | 6 | Blocks release |
| P1 | 7 | Should fix before release |
| P2 | 4 | Fix soon after release |
| P3 | 3 | Polish, non-blocking |

**Clean:** no plaintext secrets, no SSH keys, no API tokens, no vault leaks. LICENSE is correct EUPL-1.2. `.gitignore` covers `.env`, `*.bak`, `.vault_pass`. Ansible playbooks use template vars, not hardcoded creds.

---

## P0 — Blocks release

### P0.1 — Personal developer paths committed
- **File:** `.claude/settings.local.json` (lines 24, 30)
- **Issue:** Contains `/Users/rasped/...` macOS paths from the maintainer's laptop. `settings.local.json` is by convention a per-user file.
- **Action:** Delete file. Add `.claude/settings.local.json` to `.gitignore`.

### P0.2 — Hardcoded personal infrastructure IPs
- **Files / lines:**
  - `tools/validate-dns-stack.sh` — `192.168.1.10` at lines 72, 103, 105, 112, 133, 142 (personal Proxmox host)
  - `ansible/scripts/vm-self-register.sh:11` — `192.168.1.20`
- **Issue:** These are developer/test infra, not examples.
- **Action:** Parameterize via env var or CLI arg. Document default behavior.

### P0.3 — Missing `.secrets.baseline`
- **File:** `.pre-commit-config.yaml:92` references it; file does not exist.
- **Issue:** Pre-commit `detect-secrets` hook breaks on first run.
- **Action:** `detect-secrets scan --all-files > .secrets.baseline` and commit.

### P0.4 — No `.github/` directory
- **Issue:** No issue templates, PR template, dependabot, FUNDING, workflows. Contributors have no guidance.
- **Action:** Add `.github/` with:
  - `ISSUE_TEMPLATE/bug_report.yml`
  - `ISSUE_TEMPLATE/feature_request.yml`
  - `ISSUE_TEMPLATE/config.yml` (contact_links → security advisories, discussions)
  - `pull_request_template.md`
  - `FUNDING.yml` (optional)
  - `dependabot.yml` (optional but recommended)

### P0.5 — No CI/CD
- **Issue:** Zero automated checks on PRs. Linters exist locally but don't gate merges.
- **Action:** Add `.github/workflows/lint.yml` running: `ansible-lint`, `yamllint`, `markdownlint`, `shellcheck`. Run on PR + push.

### P0.6 — No `SECURITY.md`
- **Issue:** Security researchers have no documented disclosure channel.
- **Action:** Add `SECURITY.md` at repo root:
  - Supported versions: latest release
  - Reporting: GitHub Security Advisories (private) only
  - SLA: best-effort
  - Scope: bootstrap, quickstart, default deploy. Out of scope: upstream projects (OPNsense, AdGuard, Proxmox, container base images) — redirect upstream.

---

## P1 — Fix before release

### P1.7 — LICENSE copyright year stale
- **File:** `LICENSE:1` — says "Copyright (c) 2025"
- **Action:** Update to `2025-2026` (recommended) or `2026`.

### P1.8 — `bootstrap/README.md` is empty
- **File:** 0 bytes.
- **Action:** Write brief orientation: phases, entry points (`bootstrap.sh` → `prepare-host.sh` → `create-vm.sh` → `setup-guest.sh`), where logs go.

### P1.9 — "Link TBD" placeholder in contributing docs
- **File:** `docs/contributing/README.md:283` — "Chat: Join our community (link TBD)"
- **Action:** Remove line or link to GitHub Discussions once enabled.

### P1.10 — No `CHANGELOG.md`
- **Action:** Create using Keep-a-Changelog format. Seed with an Unreleased section; add `[0.1.0] - 2026-04-??` entry when tagging the first release.

### P1.11 — SubRosa ApS copyright in a bootstrap script
- **File:** `bootstrap/proxmox-optimize.sh:35`
- **Issue:** Says "Copyright (c) 2025 SubRosa ApS (PrivateBox)" — FOSS pivot happened but this header wasn't updated.
- **Action:** Change to `Copyright (c) 2025-2026 PrivateBox Contributors` to match LICENSE.

### P1.12 — `CLAUDE.md` exposed in contributor onboarding
- **File:** `docs/contributing/README.md:48` (repo structure block)
- **Issue:** Lists `CLAUDE.md` as part of the contributor-facing structure. It's an internal AI-assistant guide.
- **Action:** Add a clarifying note ("Internal — AI assistant guardrails, not required reading") or remove from the structure block.

### P1.13 — No SPDX headers in source files
- **Issue:** Only `bootstrap/proxmox-optimize.sh` has a license header (and it's wrong — see P1.11). EUPL convention is to include a short header.
- **Action:** Add `# SPDX-License-Identifier: EUPL-1.2` (after shebang where applicable) to all `.sh`, `.py`, `.yml` files created by this project. Leave upstream files unmodified.

---

## P2 — Fix soon after release

### P2.14 — `Rasped/privatebox` hardcoded ~12 places
- **Files:**
  - `quickstart.sh:23`
  - `README.md:60, 100`
  - `CLAUDE.md:81`
  - `docs/contributing/README.md:29, 83`
  - `docs/guides/getting-started/getting-started.md:37`
  - `docs/guides/getting-started/faq.md:11, 95`
  - `bootstrap/setup-guest.sh:276`
  - `bootstrap/deploy-opnsense.sh:68`
  - `recovery/download-assets.sh:192, 232`
- **Issue:** All break if the repo moves.
- **Action:** Decide org location first. If moving to `subrosadev`, batch-update before tagging v0.1.0. GitHub redirects cover legacy `Rasped/privatebox` URLs for humans, but the raw.githubusercontent.com quickstart URL is stability-sensitive.

### P2.15 — Internal test-server hostname in CLAUDE.md
- **File:** `CLAUDE.md:51` — `privatebox-test-102`, `192.168.0.102`
- **Action:** Flag as internal-only; point contributors at a generic "use your own Proxmox VM" pattern.

### P2.16 — Container image license compatibility not documented
- **Images:** `adguard/adguardhome`, `b4bz/homer`, `portainer/portainer-ce`, `caddy`
- **Action:** Audit each for GPL/AGPL compatibility with EUPL-1.2. Record in `docs/architecture/dependencies.md`.

### P2.17 — Third-party attribution scattered
- **Current:** `licenses/community-scripts-MIT-LICENSE` exists; attribution is only inside `bootstrap/proxmox-optimize.sh`.
- **Action:** Add `THIRD_PARTY_LICENSES.md` at repo root summarizing all external code + links.

---

## P3 — Polish

### P3.18 — Stale VPN references after stack removal
- **Files:** `docs/guides/getting-started/core-concepts.md:54`, `docs/guides/getting-started/faq.md:75, 89, 105`, `docs/architecture/opnsense-firewall/configuration-requirements.md:85-109`
- **Context:** VPN automation removed in `8682438`. Docs say "PrivateBox does not automate VPN setup" — accurate, but ~20 references lingering.
- **Action:** Consolidate into one section when convenient.

### P3.19 — `default('changeme')` in two playbooks
- **Files:** `ansible/playbooks/services/adguard-deploy.yml:35`, `portainer-deploy.yml:29`
- **Issue:** Unreachable in practice (bootstrap generates random password), but visible in code.
- **Action:** Change to `default('')` to fail loudly, or document that the default is dead code.

### P3.20 — Pre-commit excludes non-existent `.github/`
- **File:** `.pre-commit-config.yaml:13, 26, 40`
- **Status:** Resolves automatically once `.github/` is created (P0.4). No action needed.

---

## Clean findings (no action needed)

- No plaintext secrets, SSH keys, or API tokens in the repo.
- Ansible playbooks use template variables for credentials.
- `opnsense_default_password: "opnsense"` in `opnsense-secure-access.yml:16` is the upstream factory default, intentionally used for first-login handoff. Acceptable.
- `.gitignore` covers the obvious cases.
- LICENSE content itself is correct.
- Router setup guide uses `192.168.1.1`, `192.168.0.1`, `10.0.0.1` — these are standard RFC1918 examples, fine.
- `.DS_Store` in `.gitignore` — harmless.

---

## Strategic decisions (from prior discussion)

- **Repo location:** move to `subrosadev` org before release. GitHub preserves redirects, but announcements should point at the final URL.
- **`.claude/settings.local.json`:** delete + gitignore. Keep `CLAUDE.md`.
- **Versioning:** tag `v0.1.0` on release. Pre-1.0 signals "API not stable". Pair with Keep-a-Changelog.
- **Security policy:** GHSA-only, no email contact, best-effort SLA, tight scope.

---

## Proposed execution order

Six focused PRs:

1. **Hygiene pass** — P0.1, P0.3, P1.7, P1.8, P1.11, P1.12. Mechanical cleanup, no external deps.
2. **`.github/` + CI + security policy** — P0.4, P0.5, P0.6. Single PR.
3. **Infra leak fixes** — P0.2. Touches runtime; isolate.
4. **Release scaffolding** — P1.9, P1.10, P1.13. CHANGELOG, SPDX headers, contributor link. Then tag `v0.1.0`.
5. **Org move → URL refactor** — P2.14. Do just before/after tagging so release artifacts point at final URLs.
6. **Post-release** — P2.15–17, P3 items.

**Estimated effort:** 4–6 focused hours for chunks 1–4. Chunk 5 depends on GitHub transfer.

---

## References

- Audit scope inputs: CLAUDE.md (lines 14–23, 45–69), README.md, LICENSE, CONTRIBUTING.md, `docs/contributing/README.md`, `.pre-commit-config.yaml`
- Recent pivot commits: `c3aab8c` (FOSS pivot docs), `578735d` (consolidated contributing), `8682438` (VPN stack removal)
