# Bootstrap Scripts Review — 2026-04-22

Consolidated findings from six parallel agent reviews of the bootstrap flow. Paths reference script locations in the repo (review text originally used `/home/user/privatebox/...`).

Scope reviewed:
1. Orchestration: `quickstart.sh`, `bootstrap/bootstrap.sh`, `bootstrap/validate-files.sh`
2. Phase 1: `bootstrap/prepare-host.sh`
3. Phase 2: `bootstrap/deploy-opnsense.sh`
4. Phase 3: `bootstrap/create-vm.sh`
5. Phase 4: `bootstrap/setup-guest.sh`, `bootstrap/verify-install.sh`
6. Libraries: `bootstrap/lib/password-generator.sh`, `bootstrap/lib/semaphore-api.sh`

---

## 1. Orchestration (quickstart.sh + bootstrap.sh + validate-files.sh)

### Good
- `set -euo pipefail` applied consistently in both orchestrators (quickstart.sh:20, bootstrap.sh:7) — strict failure semantics throughout.
- TTY vs pipe detection is thoughtful: bootstrap.sh:17 degrades spinner to periodic dots over SSH pipes (bootstrap.sh:128-134), avoiding tput garbage.
- Locale workaround for Perl-based Proxmox tools (`export LC_ALL=C`, bootstrap.sh:10) prevents noisy `qm`/`pvesm` warnings.
- Fail-closed SSH options for guest polling (bootstrap.sh:279): `ConnectTimeout=5`, `StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`, `LogLevel=ERROR` — correct for fresh-VM scenario.
- Config file removed after successful run (bootstrap.sh:430-433) since it contains passwords.
- Phase 4 progress is streamed incrementally from the VM marker file (bootstrap.sh:318-333), not just a spinner — the user sees actual progress.
- quickstart.sh handles both `.list` and DEB822 `.sources` formats for disabling enterprise repos (quickstart.sh:159-179) — correctly anticipates Trixie format change.
- TEMP_DIR is wiped before re-clone (quickstart.sh:230-232), so rerun works.

### Bad
- **quickstart.sh:183 hardcodes `bookworm`** in the no-subscription apt source, but the script explicitly detects Debian 13 (Trixie) at quickstart.sh:149. On Proxmox 9 this writes an incorrect repo line — Proxmox 9's no-subscription repo is `trixie pve-no-subscription`, not `bookworm`. Script claims to support both but misconfigures PVE 9.
- **quickstart.sh:305 uses unquoted `$bootstrap_cmd`** in `bash $bootstrap_cmd` — relies on word-splitting to pass args. Works today because args have no spaces, but this is the classic shell antipattern; any future arg with a path would break. Should use an array.
- **quickstart.sh:218** connectivity check only tests GitHub — but bootstrap later pulls Debian cloud images, Proxmox repos, OPNsense bits. Passing this test doesn't imply the rest will work; `--connect-timeout 5` against a single host isn't a real internet check.
- **quickstart.sh:267 `read -p "...yes/no"` is unreachable over piped invocations** but the gate `PIPED_INPUT` (line 31) checks stdin only. If a user runs it under `nohup`/`tmux` with stdin redirected to `/dev/null`, `read` returns empty and user is silently declined at line 273.
- **bootstrap.sh:240 `bash "${SCRIPT_DIR}/deploy-opnsense.sh" $opnsense_args`** — unquoted expansion again. Same issue at bootstrap.sh:261 for create-vm.sh.
- **bootstrap.sh:231-245 OPNsense script is "optional"** — if `deploy-opnsense.sh` is missing, bootstrap prints a warning and continues. Per CLAUDE.md, OPNsense is 10.10.20.1, the gateway for the management VM. Continuing without it will break Phase 4. Either fail hard, or the warning is a lie.
- **bootstrap.sh:278 `SSH_KEY_PATH:-/root/.ssh/id_ed25519`** — path comes from the sourced config file, but if the key doesn't exist, `ssh_opts` just omits `-i` (line 280) and SSH will try agent/default keys. On a fresh Proxmox there is no agent and no default key — SSH will fail silently for 120s at line 288-295 and the script emits `"VM not accessible yet"` (line 378) and skips to verification. Should hard-error if the key that `create-vm.sh` just provisioned is not readable.
- **bootstrap.sh:289 `ssh ... "${VM_USERNAME}@${STATIC_IP}"`** but `VM_USERNAME` may be unset when config didn't define it. Elsewhere uses `${VM_USERNAME:-debian}` (line 407, 410). Inconsistent — under `set -u` an unset `VM_USERNAME` here would abort. Brittle.
- **bootstrap.sh:311-316 `ssh ... cat /etc/privatebox-install-complete || echo PENDING`** — if SSH itself fails (transient network, VM reboot), the output becomes "PENDING" and the loop silently treats it as "not done yet" for up to 25 minutes. No distinction between "VM says not done" and "VM unreachable".
- **bootstrap.sh:315 `tail -1 | sed ...`** on `$file_content` — if the marker file's final line happens to contain the literal word `PROGRESS:xxx` and nothing ever writes `SUCCESS`/`ERROR`, the loop hangs until timeout. No liveness check on the marker file (e.g., mtime bounded).
- **bootstrap.sh:374 timeout is `error_exit` only**; no diagnostic dump. User gets "timeout after 1500 seconds" and a 3000-line log to spelunk.
- **bootstrap.sh:411 prints `ADMIN_PASSWORD` to the terminal**, then line 430-433 removes the config file. If the user was `ssh ... | tee`ing, password leaks.
- **bootstrap.sh:165 `display "❌ Bootstrap failed..."`** uses UTF-8 emoji while earlier the code exports `TERM=dumb`. Inconsistent ANSI/UTF policy.
- **validate-files.sh:22 iterates `$file` as relative paths** with no `cd` — must be run from the `bootstrap/` directory. No guard. Fragile.
- **validate-files.sh:81 references `./test-bootstrap.sh`** which is not in the validated list. Dead instruction.
- **validate-files.sh:82 references `bootstrap2/`** — stale naming from a refactor.
- **validate-files.sh is not called by anything** — orphaned dev tool masquerading as a pre-flight check. Either wire it in or move it to `tools/`.
- **validate-files.sh does grep-based "API integration" checks** (lines 37-70) that only verify string presence, not correctness. False-confidence risk.
- **quickstart.sh:235 `git clone --depth 1 --branch "$REPO_BRANCH"`** — shallow clone means no commit hash/ref is recorded. `/tmp/privatebox-bootstrap.log` never records which commit was deployed. For a security appliance, that's a real traceability gap.
- **quickstart.sh:311-317 cleanup trap runs on every EXIT, including failure** — so when bootstrap fails, the repo is wiped and the user can't inspect post-mortem. Should keep TEMP_DIR on non-zero exit.
- **bootstrap.sh:161-167 cleanup trap** only prints a message; doesn't kill child SSH processes if the script is Ctrl-C'd mid-Phase-4 poll. Orphan SSH connections can linger.

### Parameterization
**Should be hardcoded (currently configurable, adds complexity):**
- quickstart.sh:24 `REPO_BRANCH="main"` + `--branch` flag — developer-facing; drop from `--help`.
- bootstrap.sh:31 `VMID=9000` — declared as a variable implying configurability; move to `readonly VMID=9000`.
- quickstart.sh:15 `--no-cleanup` flag — users never need this.
- quickstart.sh:14 `--dry-run` + bootstrap.sh:36 `--dry-run` — feature creep for end users; keep but don't advertise.

**Should be configurable (currently hardcoded, user hardware varies):**
- quickstart.sh:211 `for cmd in curl wget qm` — no check that a usable storage pool exists. User finds out at Phase 3.
- bootstrap.sh has no RAM/CPU pre-flight. CLAUDE.md says "8GB+ RAM" but nothing asserts it.
- bootstrap.sh:300 `phase4_timeout=1500` — should be env-overridable (`PHASE4_TIMEOUT`).
- bootstrap.sh:288 `while [[ $elapsed -lt 120 ]]` — 2 min to first SSH is tight for cold cloud-init on slow SSDs. Bump to 300 or gate on cloud-init completion.
- Nothing parameterizes upstream image URL or checksum. No pinning despite "offline-capable" principle.

**Correctly parameterized:**
- VMID=9000, VM IP 10.10.20.10, service domains — correctly hardcoded.
- `--verbose`, `--quiet` — correct UX affordance.
- `LC_ALL=C`, `TERM=dumb` fallback — correct non-configurable defaults.

### Cross-script concerns
- **Argument passthrough is lossy.** quickstart.sh:291-302 builds a bootstrap invocation but does not forward `--no-cleanup`, can't forward a future `--vmid`, and doesn't propagate a trace ID. bootstrap.sh in turn passes only `--quiet` to sub-phases, dropping `--verbose`.
- **Duplication of arg parsing.** Both scripts parse `--dry-run`, `--verbose`, `--help`, `--branch` independently with slightly different semantics.
- **No shared lib.** Color codes, `error_exit`, `success_msg`, `warning_msg`, `info_msg` reimplemented with divergent formatting. `lib/` exists per bootstrap.sh:23 but isn't sourced by the orchestrators.
- **Race: `CONFIG_FILE` at `/tmp/privatebox-config.conf` is world-readable** by default umask and contains `ADMIN_PASSWORD`, `SERVICES_PASSWORD`. No `chmod 600` enforced at orchestration boundary.
- **Handoff between Phase 3 and Phase 4 is implicit.** No explicit contract that create-vm.sh has finished cloud-init writeout. 120s SSH timeout is the only backstop.
- **Marker-file protocol is ad-hoc.** Uses inline `PROGRESS:`, `SUCCESS`, `ERROR` sentinels parsed by tail+grep. No version field, no timestamps, no structured format.
- **Idempotency hole on rerun.** quickstart.sh:230-232 wipes TEMP_DIR but bootstrap.sh:430-433 wipes CONFIG_FILE only on success. Stale config with stale passwords sits at `/tmp/privatebox-config.conf` after failure.
- **Opposite cleanup traps:** bootstrap preserves on failure (correct); quickstart wipes on failure (wrong). Not coordinated.
- **Inconsistent error-exit formatting.** quickstart.sh prints ANSI red; bootstrap.sh plain text with extra "Check log file" line. Wrappers can't pattern-match error classes.
- **No lock file.** Two concurrent `quickstart.sh | bash` invocations race on TEMP_DIR, CONFIG_FILE, and `qm create 9000`. A simple `flock /var/lock/privatebox-bootstrap.lock` at the top of bootstrap.sh would prevent the whole class.

---

## 2. Phase 1 — prepare-host.sh

### Good
- Pre-flight root + Proxmox env checks are explicit and fail fast (lines 89–104).
- Dependency installer is batched and uses `DEBIAN_FRONTEND=noninteractive` (line 73).
- WAN bridge is detected from the actual default route rather than assumed (lines 151–162), with sensible `vmbr0` fallback.
- Ed25519/ECDSA P-256 chosen for SSH and TLS — modern, no knobs (lines 194–199, 356).
- Existing VM 9000 is torn down cleanly with stop→destroy→purge (lines 110–127).
- Duplicated `10.10.20.20/24` on untagged `vmbr1` is actively detected and stripped (lines 579–583).
- Token recreation path removes the prior token before issuing a new one (lines 237–241), so retries don't wedge on "already exists".
- Cert key is generated to `/etc/privatebox/certs` with 10-year validity — no renewal surprises mid-flow (line 194).

### Bad
- **Cert key is world-readable** (line 201): `chmod 644 "$cert_dir/privatebox.key"`. Private keys should be `600`.
- **API token secret is written to `/tmp/privatebox-config.conf` with no chmod** (lines 280–319). Default umask (likely `644`) — world-readable. `ADMIN_PASSWORD`, `SERVICES_PASSWORD`, `PROXMOX_TOKEN_SECRET` all sit in there.
- **Token creation failure is swallowed to a warning** (lines 256–260): `proxmox_token_secret=""` and the script continues. Should `error_exit`.
- **`error_exit` used for dual-NIC requirement while `set -euo pipefail` is active, inside a multi-line string with leading tabs/spaces** (lines 449–456). Wall-of-text error instead of clear single-line.
- **Node name = `hostname -s`** (line 216). If operator ran `hostnamectl set-hostname` after Proxmox install, `hostname -s` diverges from actual PVE node name and every API call keyed on node will 500. Use `pvesh get /nodes --output-format=json | jq -r '.[0].node'`.
- **`detect_wan_bridge` assumes default route traverses a `vmbr*`** (line 155). On fresh Proxmox where user hasn't migrated physical NIC into `vmbr0`, the `vmbr0` fallback kicks in silently with a non-working bridge.
- **Storage is hardcoded to `local-lvm`** (line 16) but never checked to exist. On ZFS-root Proxmox (increasingly common), there is no `local-lvm` — only `local-zfs`. Error message doesn't hint at real problem.
- **`pvesm status` output parsed by column position** (line 130). Column order has changed between 7.x and 8.x; fragile. JSON output via `pvesh` is robust path.
- **Token grep uses Unicode box-drawing `│`** (line 237): `grep -q "│ ansible "`. Depends on `pveum`'s pretty-printed table rendering which varies with version and `LC_ALL`/`LANG`.
- **`grep -oP '"value"\s*:\s*"\K[^"]+'`** (line 247) on raw JSON. Parse as JSON, not regex.
- **`sed` over `/etc/network/interfaces` to inject VLAN-aware lines** (line 410): targets `bridge-fd 0` literally. If the stanza was reformatted, this silently does nothing and script declares success.
- **Unassigned-NIC search is regex on `/etc/network/interfaces*`** (lines 428–430), not on kernel bridge membership (`bridge link` / `/sys/class/net/*/brif`). Can grab an already-in-use NIC.
- **`ethtool "$nic"` link check logs a warning but uses the NIC anyway** (line 439). Pointless noise.
- **`generate_ssh_keys` appends pubkey to `authorized_keys` every run** (line 374) without dedup check. Re-running grows the file linearly.
- **`configure_services_network` appends duplicate `auto vmbr1.20` stanza** if the interface has the right IP but no config file entry (lines 531–541).
- **`ping -I vmbr1.20 -c 1 -W 2 10.10.20.1`** (line 594) is advisory only; nothing gates Phase 1 success on Services VLAN actually being up.
- **`optimize_proxmox` runs *after* `run_preflight_checks`** (lines 609–612) even though comment at line 37 says "early (before password generator sources which overwrites SCRIPT_DIR)". `apt-get update` runs first — which is exactly what optimize is presumably fixing (enterprise repo). Order is backwards.
- **`source "${SCRIPT_DIR}/lib/password-generator.sh"`** at top level (line 182), not inside a function. Comment and code don't match.
- **`15GB` disk space check is hardcoded** (line 137) while VM disk is `10G` (line 300). No headroom comment.
- **`$token_output` logged on failure** (line 258) — if Proxmox echoes partial token into stderr, secret lands in world-readable log.

### Parameterization
**Should be hardcoded:**
- Line 16 `STORAGE="local-lvm"` — either commit to hardcoded or detect between `local-lvm` / `local-zfs` / `local`. Currently worst of both.
- Lines 298–301 `VM_MEMORY`, `VM_CORES`, `VM_DISK_SIZE` — written as if tunable; drop from config file surface.
- Line 291 `SERVICES_NETMASK="24"` — part of network design, not a knob.

**Should be configurable:**
- Line 15 `VMID=9000` — no env override. Rare collision case has no escape hatch.
- Lines 269–272 Services VLAN IPs — pre-flight check against upstream network would help.
- Line 216 Node name detection — use authoritative source, not `hostname -s`.

### Phase-specific risks
**Network detection fragility**
- USB NICs on N150 appear as `enx<mac>` — regex `(enp|eno|eth)` misses them. Reports "requires dual NICs" and fails (line 449).
- Bonded interfaces / vlan-on-physical / OVS bridges invisible to detection logic.
- Default route on WireGuard/tap → `grep -o 'vmbr[0-9]*'` returns empty; fallback silently picks `vmbr0`.

**Token generation idempotency**
- Re-running rotates the secret. Anything that cached the old secret breaks silently. No "reuse if already valid" path.
- `sleep 1` after token removal (line 240) is race-condition band-aid.

**Storage pool detection across Proxmox versions**
- Hard dependency on `local-lvm` name. ZFS-on-root creates `local-zfs`. Directory-storage has only `local`. Ceph-backed has neither.

**Phase 1 partial success / re-run**
- Config file at `/tmp/privatebox-config.conf` overwritten every run — passwords rotate. If Phase 2 consumed old values, things diverge.
- SSH authorized_keys accumulates duplicates.
- `/etc/network/interfaces` accumulates duplicate `auto vmbr1.20` stanzas.
- VM 9000 destroyed on every run — Phase 1 re-run after Phase 4 success wipes production management VM with no confirmation.
- No completion marker at end of Phase 1 — violates CLAUDE.md "logs and completion markers" rule.

**Secret surface**
- `/tmp/privatebox-config.conf` world-readable. `/tmp/privatebox-bootstrap.log` unchmod'd and logs token JSON on failure. Both should be `chmod 600` on first write; `/etc/privatebox/` is the right home (already used for certs).

---

## 3. Phase 2 — deploy-opnsense.sh

### Good
- MD5 verification of downloaded template, 3-attempt retry, 30s backoff (lines 341-382).
- Template caching at `/var/tmp/opnsense-template` avoids redundant 767MB downloads (lines 322-334).
- Local template fallback at `/tmp/${TEMPLATE_FILENAME}` supports offline/dev (lines 306-320).
- Pre-flight disk space, Proxmox version, storage pool, bridge existence checks before doing work (lines 212-240).
- Idempotent cleanup via `CLEANUP_DONE_MARKER` prevents double-cleanup from ERR trap + error_exit (lines 155-158).
- Pre-flight blocks early if VM 100 exists with clear operator options (lines 200-209).
- Reboot state machine waits for DOWN then UP rather than sleeping blindly (lines 687-720).
- `version_compare` uses `sort -V` instead of shelling to bc/python (lines 178-187).
- Auto-installs missing tools with proper package name mapping for `nc`/`md5sum` (lines 256-282).

### Bad
- **Secret leaked to world-readable log (lines 502-507, 520-525, 888-912):** `OPNSENSE_DEFAULT_PASSWORD` written into VM description via `qm set --description` and into `DEPLOYMENT_INFO_FILE` under `/var/log/privatebox/`. Well-known default (`opnsense`), but pattern is wrong; parameterizing later leaks a real secret.
- **`qm set` failures silently ignored in quiet mode (lines 492-507):** Six sequential calls use `>> "$DEPLOYMENT_INFO_FILE" 2>&1` with no `|| error_exit`. If one fails, script proceeds — VM may come up on wrong bridge.
- **`qm reboot` exit-on-failure** at line 681 uses `|| error_exit` without logging stderr and no retry. Transient failure aborts whole deployment.
- **Duplicated quiet/verbose blocks (lines 421-485 and 490-526):** Same `qmrestore`, `qm clone`, `qm destroy`, `qm set` sequences copy-pasted twice. ~60 lines. A `run_logged()` helper would cut this and eliminate drift.
- **Duplicated spinner block (lines 548, 594, 689, 752):** Same `spinner_chars=(...)` array re-declared four times.
- **Duplicated VLAN check (lines 760-766 and 820-826):** Identical SSH+ifconfig+grep in `apply_custom_config` and `validate_deployment`.
- **`apply_custom_config` uses `error_exit` only for scp (line 672), treats backup failure and reboot-never-went-down as warnings** (lines 659, 724). Inconsistent: broken config + silent backup failure → hard recovery.
- **`test_ssh_connectivity` returns 1 on auth failure (line 636), but main() just prints "Skipping custom config due to SSH issues" and continues** (lines 964-969). OPNsense with broken SSH still "succeeds" — no VLAN 20, no Services IP. Phase 3 then fails to reach 10.10.20.10. Should be fatal.
- **Overlapping failure handling:** `set -e` + `trap 'cleanup_on_failure' ERR` + explicit `error_exit` (which also calls `cleanup_on_failure`). Three mechanisms; double-call guarded by marker but easy to break.
- **`pvesm status --enabled` output parsed assuming header row** (line 221). If no enabled storage, `awk 'NR>1'` gives nothing and user gets "Available: " — truncated, confusing.
- **Hard 45s sleep after VM status=running (lines 570-582)** with no readiness check. Redundant given 300s SSH wait that follows.
- **`nc -zv ... -w 5` (line 871)** — `-w` flag isn't guaranteed to work with `netcat-traditional` (installed at line 276). Different semantics from openbsd variant. Latent bug.
- **`spinner_chars` uses UTF-8 braille glyphs** — will render as garbage in non-UTF locales or logs. `IS_TTY` gate helps but `log()` still writes spinner-adjacent lines.
- **No verification that template contains VM 105 before `qm clone`** (line 446). Coupled to MD5 match.

### Parameterization
**Should be hardcoded:**
- Line 61 `OPNSENSE_VMID` — VM 100 referenced throughout CLAUDE.md and codebase.
- Line 62 `OPNSENSE_VM_NAME` — never meaningful to customize.
- Line 64 `OPNSENSE_START` / `START_AFTER_RESTORE` — conditional path only matters to developers.
- Line 30 `VERBOSE` / `--quiet` — source of all duplicated code (~60 lines). Pick one mode.

**Should be configurable:**
- Line 63 `VM_STORAGE="local-lvm"` — wrong default for ZFS (`local-zfs`) / file-based (`local`) installs. Phase 1's detected value should be written to config and read here.
- Line 68 `TEMPLATE_URL` / line 70 `TEMPLATE_MD5` — pinned to one GitHub release. No env override for air-gapped mirroring.

**Correctly parameterized:**
- `OPNSENSE_LAN_IP`, `OPNSENSE_SERVICES_IP`, `OPNSENSE_DEFAULT_USER/PASSWORD` (template invariants), timeouts, bridge names.

### Structural concerns
**986 lines is too much.** Real work: download ~40 lines, restore+configure ~50, wait-for-SSH ~30, upload config+reboot ~40. Everything else is UX and duplicated code.

Natural split points:
- Spinner/display helpers (112-145) → `bootstrap/lib/display.sh`.
- `display_summary` (886-946) → HEREDOC to log; bootstrap.sh prints summary anyway.
- Dual verbose/quiet branches (421-526) → single `run_logged()` helper.
- Validation (792-883) → separate script. Phase 3 re-checks OPNsense anyway.

**Template approach: contradiction.** Lines 641-790 apply custom config.xml from `bootstrap/configs/opnsense/config.xml`, then reboot. CLAUDE.md says "manual config → convert to template → store on GitHub" — implying template should have final config baked in. VLANs 20/30/40/50/60/70 being added post-restore suggests template was NOT configured with them. Either:
1. Template is captured pre-VLAN and config.xml is source of truth (then why have the template beyond saving install time?), or
2. Template should have VLANs, and config.xml is redundant drift.

Resolve this — either bake full config into template and drop `apply_custom_config`, or document why two-stage exists.

**Upstream-change failure modes:**
- GitHub release URL: if release deleted or tag moves, download fails cleanly — acceptable.
- `qmrestore --help | grep "\.zst"`: if Proxmox changes help text, script falsely assumes no zst support. Low risk.
- Decompression fallback writes to `${template_path%.zst}` but never cleans it up — ~2GB dead file.
- config.xml format is OPNsense-version-specific. Stale config against newer OPNsense → firewall bricks, no automated recovery.

### Phase-specific risks
- **No explicit wait for WAN DHCP lease before declaring success.** `validate_deployment` pings 8.8.8.8 but treats failure as non-critical.
- **Race: Phase 3 starts immediately after completion marker.** Services stabilize wait is only 30s. OPNsense pf/unbound/DHCP can take 60-90s after SSH.
- **No ARP/neighbor-table check on Services VLAN from Proxmox.** Line 808 pings 10.10.20.1 from Proxmox, but Proxmox needs `vmbr1.20` with 10.10.20.20. If Phase 1 didn't set up, ping fails for Proxmox reasons, not OPNsense.
- **Re-run with existing VM 100: pre-flight fails hard** (line 208). No `--force`/`--recreate`. Operator must manually destroy.
- **Credential handling:** `OPNSENSE_DEFAULT_PASSWORD="opnsense"` used unchanged for all subsequent SSH. Password never rotated. Default password on a firewall in production. Fix: one-time password change via config.xml (PBKDF2 hash).
- **`sshpass` with `StrictHostKeyChecking=no`** and `/dev/null` known_hosts means no host key pinning. MITM on Services VLAN during bootstrap captures `opnsense` password.
- **Cleanup leaves cached template and decompressed `.vma`** in `/var/tmp/opnsense-template/` — feature for re-run, bad on disk-full.
- **Completion marker created even when `validate_deployment` reported failures** — `all_good=false` only prints warnings, never returns non-zero.

---

## 4. Phase 3 — create-vm.sh

### Good
- Idempotent image cache check (line 114): reuses existing image instead of re-downloading.
- Ensures `snippets` content type enabled on `local` storage (line 183), correctly idempotent.
- VM network tagged with VLAN 20 on `vmbr1` (line 302) matches Services VLAN architecture.
- QEMU agent enabled at create time (line 305), required for Phase 4 guest polling.
- SSH public key embedded into cloud-init users block (line 227) enables keyless ops from Proxmox.
- `snippets/privatebox-${VMID}.yml` namespaced by VMID (line 216), avoiding cross-VM collisions.
- Snippet file intentionally NOT cleaned up (line 411 comment) — required since cloud-init reads on each boot.
- Uses `--cicustom user=` (line 331), correctly overrides only user-data.

### Bad
- **No checksum verification of downloaded image** (lines 119–124). Debian publishes `SHA512SUMS` + `SHA512SUMS.sign`. Only 1MB size sanity check. Corrupted mirror or MITM silently yields broken/poisoned base image. For a "network security project" this is a real issue.
- **`wget -q --show-progress`** — a truncated/partial download that still exits 0 would pass. No checksum.
- **Password piped through `openssl passwd -6` in command-substitution inside heredoc** (line 226). If `ADMIN_PASSWORD` contains `$`, backtick, `"`, or newline, shell interpolates first — wrong hash or broken YAML. Same risk on lines 150–163 where `$VAR`s get written into `config.env`.
- **`setup-guest.sh` content embedded via `sed 's/^/      /'` then splatted into YAML** (lines 168, 240). If script contains line starting with `---`, `...`, tabs, trailing whitespace on blank line, or CRLF, cloud-init silently rejects user-data. No `yamllint`/`cloud-init schema` validation.
- **`proxmox_private_key` pre-indented to 6 spaces (line 200), then `echo "$proxmox_private_key"`** (line 247). Brittle with backslash escapes on non-default shells. Use `printf '%s\n'`.
- **Certificates read from `/etc/privatebox/certs/privatebox.{crt,key}`** (lines 268, 274) with no existence check. If Phase 1/2 didn't create them, heredoc `$(sed ...)` fails and the whole snippet gets written with empty `content:` block (or `set -e` aborts mid-write).
- **`privatebox.key` written with mode `0644`** (line 271). TLS private key should be `0600`.
- **No VMID collision check** (line 297). `qm create 9000` fails opaquely if VM exists. Common rerun scenario — needs explicit precheck.
- **Partial-creation cleanup missing** (lines 297–332). If `qm importdisk` fails (line 309), VM shell from line 297 is left behind; next run hits collision.
- **`cleanup()` defined twice** (lines 371 and 410) and `trap cleanup EXIT` set twice (lines 383 and 419). Second wins — misleading.
- **`qm importdisk` is deprecated** in recent Proxmox versions in favor of `qm disk import`. Will eventually break.
- **`--nameserver ${SERVICES_GATEWAY}`** (line 330) points VM at OPNsense for DNS before AdGuard exists. Fine at bootstrap but no comment explaining it's deliberate-for-bootstrap.
- **`VM_STORAGE` used without verification it exists** (line 294).
- **`manage_etc_hosts: true` + hostname `privatebox-management`** (lines 218) — no FQDN, no domain. Future Caddy/cert assumes `.lan` suffix.
- **`max_wait=30` in `start_vm`** (line 347) only checks `qm status` returns "running" — the QEMU process, not the guest being usable.
- **Log of heredoc-rendered cloud-init is only the path** (line 285), not content. No pre-flight `cloud-init schema --config-file` check.
- **Banner says "Phase 2"** (lines 3, 380, 406) but this is Phase 3. Stale comments.
- **`create_setup_tarball()` no longer creates a tarball** (line 137) — function name is lying.

### Parameterization
**Should be hardcoded:**
- Lines 294, 297–319 — `VM_STORAGE`, `VM_DISK_SIZE`, `VM_MEMORY`, `VM_CORES` config-sourced. Target hardware has one sane spec.
- Line 150 `VM_USERNAME` — `debian` is conventional; hardcoding removes footgun.

**Should be configurable:**
- Line 23 `IMAGE_CACHE_DIR="/var/lib/vz/template/cache"` — assumes default `local` storage path. Derive from `pvesm path local:...`.
- Lines 186, 216, 331 snippet path `/var/lib/vz/snippets/` hardcoded even though script enables snippets on `local`. Use `$(pvesm path local:snippets/foo)`.
- Line 22 `DEBIAN_IMAGE_URL` hardcoded to `trixie/latest`. `latest` is a moving target — reproducibility problem. Pin to dated snapshot or record hash in `/etc/privatebox/install.log`.

**Correctly parameterized:**
- Hardcoded: VMID 9000, hostname, VLAN tag 20, bridge `vmbr1`, cloud-init drive bus, scsihw, CPU type.
- Configurable: `STATIC_IP`, `SERVICES_GATEWAY`, `SERVICES_NETMASK`, passwords, Proxmox token fields.

### Phase-specific risks
**Cloud-init injection:**
- Shell `$VAR` expansion inside bash heredoc, not YAML. Special chars in passwords break either bash or YAML. Needs `python3 -c 'import yaml; yaml.safe_dump(...)'` or deliberate `printf %q` + YAML double-quote rules.
- `SETUP_SCRIPT_CONTENT` inlined un-validated. Bare tab-indented heredoc or `\` line-continuation at column 0 breaks user-data silently. Phase 4 times out without pointer here.
- `ssh_pwauth: true` (line 229) intended for recovery, but admin password is auto-generated and stored in `/tmp/privatebox-config.conf`. Attack surface on VLAN 20.

**Image download idempotency / integrity:**
- Cached image trusted forever — no re-check against upstream `SHA512SUMS`.
- `wget` with no `--tries`, no `--timeout`, no resume.
- No GPG verification of `SHA512SUMS.sign` against Debian signing key.
- Partial download on disk full: wget exits nonzero, `rm -f` runs, but OOM-killed wget skips cleanup.

**VM 9000 id collision:**
- No `qm status $VMID` pre-flight. Failure buried in log. Rerun scenario guaranteed.

**Debian 13 image URL stability:**
- `/latest/` rotates. 6-month-old bootstrap can't be reproduced.
- If upstream 404s `/latest/` during cutover, whole bootstrap bricked.

---

## 5. Phase 4 — setup-guest.sh + verify-install.sh

### Good
- Fail-fast on missing config and missing SERVICES_PASSWORD before any work (setup-guest.sh:10-29).
- Logging to `/var/log/privatebox-guest-setup.log` with timestamped `log()` and `tee` (setup-guest.sh:19-24).
- Writes `ERROR` to marker on failure via `error_exit` so Proxmox polling can bail out (setup-guest.sh:25).
- Semaphore config uses per-install random `cookie_hash`, `cookie_encryption`, `access_key_encryption` (setup-guest.sh:104-106) — not static.
- TLS enabled in Semaphore config pointing at provisioned cert (setup-guest.sh:119-123).
- Semaphore volume dir `chown 1001:1001` matches container uid (setup-guest.sh:68).
- Removal of transient `proxmox_ssh_key` after API upload (setup-guest.sh:288-291) aligns with CLAUDE.md secrets rule.
- Admin-user creation filters "already exists" output with `|| true` making re-runs non-fatal (setup-guest.sh:252).
- Marker uses staged PROGRESS/SUCCESS/ERROR lines consumed by verify-install (setup-guest.sh:32, 97-98, 222, 306; verify-install.sh:97, 117-136).
- Health check defined in Quadlet with start-period (setup-guest.sh:170-175).
- Semaphore readiness loop gates the admin seed (setup-guest.sh:227-233).

### Bad
- **Portainer completely missing from setup-guest.sh.** No quadlet, no image pull. Yet verify-install.sh checks `https://${vm_ip}:1443/api/status` (verify-install.sh:151) and `systemctl is-active portainer` (verify-install.sh:172). Either Portainer lives elsewhere, or Phase 4 cannot pass.
- **`PublishPort=2443:3000` binds to all interfaces** (setup-guest.sh:154). CLAUDE.md requires services on management VM IP only via `PublishAddress`. Should be `PublishPort=10.10.20.10:2443:3000`.
- **`SEMAPHORE_ADMIN_PASSWORD=${SERVICES_PASSWORD}` in Quadlet unit file** (setup-guest.sh:158). Unit is world-readable at `/etc/containers/systemd/semaphore.container`; rendered systemd unit in `/run/systemd/generator/`. Anyone on VM (or `systemctl cat semaphore`) sees admin password. Use `EnvironmentFile=` pointing at 0600 file, or drop env var since admin is seeded via `semaphore user add`.
- **`ACCESS_KEY_ENCRYPTION` base64 of 32 random bytes truncated to 32 chars** (setup-guest.sh:106). Same for `COOKIE_ENCRYPTION`. Semaphore expects base64-encoded 32-byte key; truncated base64 yields ~24 bytes entropy and may not decode to valid length. `cookie_hash` at 44 chars happens to be exact base64 of 32 bytes. Use `openssl rand -base64 32` without truncation.
- **`apt-get upgrade -y` on every run** (setup-guest.sh:42) — non-deterministic runtime, can pull new kernel requiring reboot. Not needed on fresh Debian 13.
- **`podman build` has no retry and no offline fallback** (setup-guest.sh:98). Pulls `docker.io/semaphoreui/semaphore:latest` and `pip3 install proxmoxer requests` every install. Transient Hub/PyPI hiccup bricks Phase 4.
- **Image tag `:latest` in two places** (setup-guest.sh:87, 144) plus daily rebuild timer (setup-guest.sh:200-210). Three install sessions three days apart get three Semaphore versions. Contradicts "deterministic". Pin tag.
- **Stop/run/start dance to seed admin has ~4-8 second window where bolt DB could be held** (setup-guest.sh:240-254). `sleep 2` is a guess. Intermittent `database is locked` silently swallowed by `|| true`.
- **`error_exit` uses `>` on marker (clobbers) but success uses `>>` (appends)** (setup-guest.sh:25 vs 306). On late failure, marker loses PROGRESS history.
- **API-config failure path appends `ERROR` after PROGRESS history** (setup-guest.sh:296). Two different failure semantics in same file.
- **`grep -v "already exists" | true` discards all stderr** (setup-guest.sh:252). Genuine errors invisible.
- **`create_default_projects` optional** (setup-guest.sh:270, 300-301). Phase 4 exits SUCCESS with no project / no templates / no SSH keys — yet verify-install.sh requires `PrivateBox` project (verify-install.sh:197).
- **`verify-install.sh:16` calls `error_exit` before it's defined** (function at line 34). Missing config → `command not found`.
- **verify-install.sh parses `set-cookie` from login response by `grep 'semaphore'`** (verify-install.sh:185-187). Fragile. Use `-c /tmp/sem.cookies` + `-b` per CLAUDE.md.
- **verify `check_services` Portainer check uses `:1443` hardcoded** (verify-install.sh:151), setup-guest never configures Portainer — always fails.
- **verify `systemctl is-active portainer semaphore`** (verify-install.sh:172) — quadlet-generated units are typically `semaphore.service`. `is-active` tolerates bare name, but Portainer absent → always false.
- **`$all_healthy` at verify-install.sh:211 is bare variable used as command.** Works because `true`/`false` are binaries, but brittle and undocumented.
- **setup-guest.sh:238 uses `{{.ImageName}}`** — newer Podman returns `{{.Image}}`. Fallback masks this; seed could use mismatched image.

### Parameterization
**Should be hardcoded:**
- `VMID="${VMID:-9000}"` (verify-install.sh:21) — documented management VM.
- `TIMEOUT="${VERIFY_TIMEOUT:-900}"` (verify-install.sh:22) — override unused.
- `CHECK_INTERVAL=10` (verify-install.sh:23).
- `SSH_KEY_PATH` (verify-install.sh:24) — Proxmox host convention.
- `ADMIN_PASSWORD="${ADMIN_PASSWORD:-$SERVICES_PASSWORD}"` (setup-guest.sh:278) — fallback always hits; delete.

**Should be configurable:**
- `PublishPort=2443:3000` (setup-guest.sh:154) — bind address templated from `STATIC_IP` / `MANAGEMENT_VM_IP`. Correctness, not customizability.
- Semaphore image tag (setup-guest.sh:87) — pinned version constant at top so upgrades intentional.

### Phase-specific risks
- **Admin seeding idempotency:** stop → `semaphore user add` → start relies on `grep -v "already exists" || true`. Exit status discarded. DB corruption, disk full, wrong config → silently ignored. `SEMAPHORE_ADMIN_PASSWORD` via container env is secondary path — if `SERVICES_PASSWORD` rotates between installs, env sets new password but bolt hash doesn't update.
- **Secret handling:**
  - `/etc/privatebox/config.env` perms not set here. Expected from earlier phase; verify elsewhere.
  - `/etc/containers/systemd/semaphore.container` contains plaintext admin password via `Environment=` (line 158). Default 0644. High-impact leak.
  - `/root/.credentials/` created (line 65) without `chmod 700`. Relies on root umask.
  - Cert file perms not verified here.
- **Quadlet unit correctness:**
  - `PublishPort=2443:3000` doesn't bind to `10.10.20.10` — violates CLAUDE.md.
  - `[Install] WantedBy=multi-user.target default.target` (line 182) — quadlets typically not enabled via `[Install]`; may be ignored or warn.
- **Completion-marker race:**
  - `error_exit` clobbers marker with `>` erasing PROGRESS — operator loses trail.
  - Setup-guest fails silently before writing marker → `check_marker_file` returns `PENDING` until 15-min timeout.
- **Verify-install false positives/negatives:**
  - **False positive:** `check_services` returns `all_healthy` but `main` only warns on failure (verify-install.sh:247-250). Install with Portainer unreachable + Semaphore project missing still exits 0.
  - **False positive:** Login check greps for literal `semaphore` in cookie jar. Response body may contain word even on failure.
  - **False negative:** Portainer check at `:1443` always fails.
  - **False negative:** `curl -sfk https://localhost:2443/api/ping` uses `-f` (fails on 4xx). Path may move between versions (`:latest`). Silent 120s loop then proceeds anyway.
  - **False negative:** `check_marker_file` 60-second timeout when `PHASE4_PROGRESS_SHOWN=true` too short if still at `PROGRESS:Building custom Semaphore image` stage.

---

## 6. Libraries — password-generator.sh + semaphore-api.sh

### Good
- `password-generator.sh:7-8` uses `LIB_DIR` (not `SCRIPT_DIR`) to avoid clobbering parent's variable when sourced.
- `password-generator.sh:131-142` fallback uses `/dev/urandom` (cryptographically sound), guarantees one of each required class before shuffle.
- Word file loaded safely via `while IFS= read -r line`; comments/blanks skipped (`:72-77`). 7,776 words (EFF Large).
- `semaphore-api.sh` uses `jq -n --arg/--argjson` throughout — no sed/grep payload synthesis, no shell-quoting vulnerabilities in bodies (`:45-55, :138-154, :340-378, :434-458, :689, :879, :1120-1124, :1146-1151`).
- `:918-954` centralized `make_api_request` with `-m 45` timeout and retry loop; callers use `get_api_status`/`get_api_body` helpers.
- `:29-32` `is_api_success` correctly treats 200/201/204 as success (covers Semaphore's mixed codes).
- `:1166` Proxmox SSH private key file deleted after upload.
- `:1272-1289` SSH keygen creates `~/.credentials` with `700`, private `600`, public `644`.
- `:199-266` `create_python_template` factored out; reused by four `create_orchestrate_*_task` wrappers.

### Bad
- **`:314-325, 381-385` — secret leakage to disk:** `PROXMOX_TOKEN_SECRET` and full payload appended in plaintext to `/tmp/proxmox-api-debug.log`. `/tmp` world-readable by default. Never cleaned up. Single largest secret-leak risk in these files.
- **`:107` logs API token itself:** `log_info "Extracted API token: $token"`. Lands in bootstrap stdout/logs. Full Semaphore API access.
- **`:624-626` `get_admin_session` passes `$admin_password` via `-d`** — JSON in argv, visible in `ps`. If `set -x` upstream, password echoed. Use `--data @-` or 0600 temp file.
- **`:19-26, 949` `status|body` encoding fragile.** `cut -d'|' -f2-` preserves pipes but convention is fragile when `jq` is already there.
- **`:79, 178, 255, 410, 482` idempotency detection uses `grep -q "already exists"`.** Wording change breaks every path. Use HTTP 400/409 status.
- **`:76-78` repo created but ID not extractable → returns 0 with no `echo "$repo_id"`.** Same pattern `:410-413`.
- **`:519-521` `repo_id=1` and `inv_id=1` hardcoded magic numbers** assuming first-created resource. No lookup by name.
- **`:524, 533, 542, 551, 560` step labels say "Step 4/9"..."Step 5/9"** but function at `:500` starts with "Step 1/8". Mismatch 8 vs 9.
- **`:269-302`** four near-identical wrappers differ only in three strings.
- **`:597` `curl -sSfk` with `-f`** causes silent failure on HTTP errors; combined with retry loop this works, but not symmetric.
- **`:927-951` retry loop has no exponential backoff, doesn't retry 401.** Session cookie may expire mid-orchestration (20 min at `:760`) — all subsequent calls 401, no re-auth logic.
- **`:936-943` only retries on empty response.** Non-empty errors (500, timeout-with-body) return "success" from `make_api_request`. No retry on transient 5xx.
- **`:967-981` `get_ssh_key_id_by_name` never returns non-zero on "not found".** Callers at `:1083-1085` re-validate with regex. Different contract from `get_template_id_by_name` at `:665-670` which does return 1.
- **`:972, 665` `jq -r ".[] | select(.name==\"$key_name\") | .id"` embeds shell vars directly in filter.** Name with `"` or `\` breaks jq. Use `--arg name "$key_name"`.
- **`:497, 561, 812, 866, 904, 1107, 1145, 1209, 1215` progress events written as plain `echo ... >> /etc/privatebox-install-complete`.** Re-run accumulates stale lines — never truncated at start.
- **`:800` `jq 'length' ... || echo "0"` hides malformed JSON;** `line_count="0"` keeps loop spinning without surfacing issue.
- **`:1150, 1181` `--arg priv "$(cat /root/.credentials/...)"` passes full SSH private key on argv of `jq`.** Briefly visible in `ps`.
- **`password-generator.sh:34, 88, 99` uses `$RANDOM` for word/position/capitalization selection.** 15-bit LCG seeded from PID+time — NOT cryptographically secure. `RANDOM % 7776` introduces modulo bias (32768/7776=4.21; last 1664 values skew first 1664 words 5×). Real entropy ~37 bits vs advertised 38.9. Use `shuf -n1 -i 0-7775 --random-source=/dev/urandom` or `od -An -N2 -tu2 /dev/urandom`.
- **`password-generator.sh:91` `[[ ! " ${selected_indices[@]} " =~ " ${index} " ]]`** is substring regex, not exact match. Works due to spaces but fragile.
- **`password-generator.sh:34, 42-50`** — "guaranteed one substitution per word" — if guaranteed-position letter is not `e/o/i/l/a/s`, no chars touched. Possible zero-digit passwords.
- **`password-generator.sh:131-138`** fallback uses `@*+=` (4 symbols). `*` / `=` rejected by some validators (URL-embedded, YAML-unquoted).

### Parameterization
**Should be hardcoded:**
- `password-generator.sh:61, 127, 149-174` — `word_count`/`length` parameters only used as `services=3 words`, `admin=5 words`. Drop CLI flags.
- `semaphore-api.sh:716` — `max_wait` on `wait_for_task_completion` never passed differently.
- `:760` default 1200 never overridden.

**Should be configurable:**
- `semaphore-api.sh:596` — `max_attempts=30` × 10s = 5 min for API readiness. Slower hardware (N100/N150/N200, 8GB min) cold-start can exceed. Raise or env var.
- `:760` 20-minute orchestration timeout — top-level constant, not `${4:-1200}` buried.

**Correctly parameterized:**
- URLs pinned to `https://localhost:2443` — correct.
- `git_branch: "main"` hardcoded — correct.
- `ssh_key_id: 1` in `create_repository` — magic, see above.
- `STATIC_IP` fallback when `hostname -I` fails — correctly configurable.

### Library-specific concerns
**password-generator:**
- Weak entropy source (`$RANDOM` throughout phonetic path). ~37 bits with bias toward early-alphabet words. Fine for 5-word admin passphrase but should use `/dev/urandom`.
- Character set sound for fallback; phonetic output passes most validators.
- Wordlist size 7,776 matches EFF Large. Collision within single password prevented by index-dedup.

**semaphore-api:**
- 1306 lines. ~10 unique API calls. Rest is flow + duplicated status/body boilerplate. 30-40% reduction possible by having `make_api_request` return just body and set global status.
- **Cookie lifetime:** session obtained once at `:1113, :1250`, passed through entire ~20-minute orchestration. No TTL check, no refresh, no 401 retry. If Semaphore session timeout < 20 min, late steps silently fail.
- **Error surfacing:** several paths return 0 on degraded states (`:76-78, :410-413, :1162-1168`). `create_repository` returns 0 both on success and "already exists" without distinguishing.
- **Naming:** mostly consistent. `create_template_generator_task` vs `create_orchestrate_services_task` — Semaphore calls them templates; tasks are runs.
- **Shell-quoting in URLs/bodies:** URLs use `$project_id` / `$task_id` directly. Numeric in practice but no validation. Bodies safe via `jq -n --arg`.
- **Functions shared vs duplicated:** mostly shared. Exception: `cut -d'|' -f1/-f2-` dance duplicated at `:397-398` instead of using helpers.

### Top fix priorities
1. Remove `/tmp/proxmox-api-debug.log` writes (`:314-325, 381-385`) — leaks Proxmox API token.
2. Remove `log_info "Extracted API token: $token"` (`:107`) — leaks Semaphore API token.
3. Switch `password-generator.sh` phonetic path to `/dev/urandom` — eliminate `$RANDOM` modulo bias.
4. Add 401-aware retry / session refresh in `make_api_request` for 20-minute orchestrations (`:927`).
5. Replace `grep "already exists"` idempotency checks with HTTP status-code checks (`:79, 178, 255, 410, 482`).
6. Look up `repo_id`/`inv_id` by name instead of hardcoding `1` (`:519-521`).

---

## Cross-cutting themes

**Secret leakage** (most urgent class):
- World-readable `/tmp/privatebox-config.conf` (passwords + Proxmox API token)
- World-readable `/tmp/proxmox-api-debug.log` (Proxmox token in plaintext)
- `log_info "Extracted API token: $token"` in bootstrap log
- TLS private key `chmod 644`
- Admin password in `Environment=` line of world-readable Quadlet unit
- `OPNSENSE_DEFAULT_PASSWORD` in VM description + deployment info file
- OPNsense default password `opnsense` never rotated
- `/root/.credentials/` created without explicit `chmod 700`

**Determinism violations:**
- `:latest` container tags in 3 places + daily rebuild
- Debian `/latest/` cloud image URL rotates
- `apt-get upgrade -y` on every Phase 4 run
- No SHA512/GPG verification of base image
- No commit hash recorded in install log

**Silent failure / false-pass:**
- Marker polling can't distinguish "not done" from "unreachable"
- OPNsense deployment succeeds even with broken SSH / missing VLAN 20
- `create_default_projects` optional → Phase 4 success marker written with incomplete setup
- `$all_healthy` warned but exit 0 in verify
- Login cookie check via `grep 'semaphore'` matches error bodies
- `grep -v "already exists" | true` swallows all errors including real ones
- `qm set` failures ignored in quiet mode

**Storage pool coupling:**
- Hardcoded `local-lvm` breaks ZFS-root (`local-zfs`) and directory-storage (`local`) installs
- Snippet/image paths assume `/var/lib/vz/...` regardless of actual storage

**Idempotency holes on re-run:**
- authorized_keys accumulates duplicates
- `/etc/network/interfaces` accumulates duplicate stanzas
- Token secret rotates every Phase 1 run
- Marker file PROGRESS lines accumulate across runs
- CONFIG_FILE only wiped on success; stale passwords survive failure
- VM 9000 destroyed on every Phase 1 — wipes production management VM if re-run after Phase 4

**Duplicated code (estimated line savings):**
- deploy-opnsense.sh: ~60 lines from `run_logged()` helper + spinner extraction
- semaphore-api.sh: 30-40% reduction if `make_api_request` returns body + global status
- Orchestrators: color codes / `error_exit` / display helpers reimplemented instead of sourced from `lib/`

**Template approach contradiction (Phase 2):**
- OPNsense config.xml applied post-restore contradicts "template has final config" design
- Either bake VLANs into template and drop `apply_custom_config`, or document the two-stage rationale

**Weak entropy (password-generator):**
- `$RANDOM` throughout phonetic path → modulo bias → ~37 bits vs advertised 38.9
- Fix: `shuf --random-source=/dev/urandom` or `od /dev/urandom`
