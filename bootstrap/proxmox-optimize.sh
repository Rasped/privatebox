#!/usr/bin/env bash
#
# PrivateBox - Proxmox Post-Install Optimizations
#
# ================================================================================
# ORIGINAL WORK:
# Copyright (c) 2021-2025 tteck | community-scripts ORG
# Source: https://github.com/community-scripts/ProxmoxVE
# Original file: tools/pve/post-pve-install.sh
# Author: tteckster | MickLesk (CanbiZ)
#
# Licensed under the MIT License:
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Full MIT License: See licenses/community-scripts-MIT-LICENSE
# ================================================================================
#
# MODIFICATIONS:
# Copyright (c) 2025 SubRosa ApS (PrivateBox)
# Licensed under EUPL v1.2
#
# This file is a modified version of the original community-scripts work.
# Modifications include:
# - Removed all interactive prompts (whiptail dialogs)
# - Auto-configured for single-node deployment
# - Skipped apt dist-upgrade to avoid reboot requirement during bootstrap
# - Integrated with PrivateBox logging system
# - Adapted for commercial appliance deployment workflow
#

set -euo pipefail

# Logging functions (PrivateBox style)
LOG_FILE="/tmp/privatebox-bootstrap.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

display() {
    echo "$1"
    log "$1"
}

error_exit() {
    echo "ERROR: $1" >&2
    log "ERROR: $1"
    exit 1
}

get_pve_version() {
    local pve_ver
    pve_ver="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
    echo "$pve_ver"
}

get_pve_major_minor() {
    local ver="$1"
    local major minor
    IFS='.' read -r major minor _ <<<"$ver"
    echo "$major $minor"
}

component_exists_in_sources() {
    local component="$1"
    grep -h -E "^[^#]*Components:[^#]*\b${component}\b" /etc/apt/sources.list.d/*.sources 2>/dev/null | grep -q .
}

optimize_proxmox_8() {
    display "  Optimizing Proxmox VE 8.x (Bookworm)..."

    # Correct Debian sources
    log "Setting up Debian Bookworm sources"
    cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
EOF

    # Suppress firmware warnings
    echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' >/etc/apt/apt.conf.d/no-bookworm-firmware.conf
    log "Configured Debian sources and suppressed firmware warnings"

    # Disable enterprise repository
    log "Disabling pve-enterprise repository"
    cat <<EOF >/etc/apt/sources.list.d/pve-enterprise.list
# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise
EOF

    # Enable no-subscription repository
    log "Enabling pve-no-subscription repository"
    cat <<EOF >/etc/apt/sources.list.d/pve-install-repo.list
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF

    # Configure Ceph repositories (disabled by default)
    log "Configuring Ceph repositories (disabled)"
    cat <<EOF >/etc/apt/sources.list.d/ceph.list
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
# deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
# deb https://enterprise.proxmox.com/debian/ceph-reef bookworm enterprise
# deb http://download.proxmox.com/debian/ceph-reef bookworm no-subscription
EOF

    # Add pvetest repository (disabled)
    log "Adding pvetest repository (disabled)"
    cat <<EOF >/etc/apt/sources.list.d/pvetest-for-beta.list
# deb http://download.proxmox.com/debian/pve bookworm pvetest
EOF

    display "  ✓ Proxmox 8.x repositories configured"
}

optimize_proxmox_9() {
    display "  Optimizing Proxmox VE 9.x (Trixie)..."

    # Disable legacy .list files if they exist
    if find /etc/apt/sources.list.d/ -maxdepth 1 -name '*.list' 2>/dev/null | grep -q .; then
        log "Renaming legacy .list files to .list.bak"
        find /etc/apt/sources.list.d/ -maxdepth 1 -name '*.list' -exec mv {} {}.bak \; 2>/dev/null || true
    fi

    # Clean up sources.list from Bookworm/Proxmox entries
    if [[ -f /etc/apt/sources.list ]]; then
        log "Cleaning sources.list from old entries"
        sed -i '/proxmox/d;/bookworm/d' /etc/apt/sources.list 2>/dev/null || true
    fi

    # Create Debian Trixie sources (deb822 format)
    log "Creating Debian Trixie sources (deb822)"
    cat >/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-updates
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    # Disable pve-enterprise if it exists, otherwise skip
    if component_exists_in_sources "pve-enterprise"; then
        log "Disabling pve-enterprise repository"
        for file in /etc/apt/sources.list.d/*.sources; do
            if grep -q "Components:.*pve-enterprise" "$file" 2>/dev/null; then
                if grep -q "^Enabled:" "$file"; then
                    sed -i 's/^Enabled:.*/Enabled: false/' "$file"
                else
                    echo "Enabled: false" >>"$file"
                fi
            fi
        done
    fi

    # Enable pve-no-subscription repository
    log "Enabling pve-no-subscription repository"
    cat >/etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

    # Add Ceph repository
    if ! component_exists_in_sources "no-subscription"; then
        log "Adding Ceph no-subscription repository"
        cat >/etc/apt/sources.list.d/ceph.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    fi

    # Add pve-test repository (disabled)
    if ! component_exists_in_sources "pve-test"; then
        log "Adding pve-test repository (disabled)"
        cat >/etc/apt/sources.list.d/pve-test.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-test
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
Enabled: false
EOF
    fi

    display "  ✓ Proxmox 9.x repositories configured"
}

remove_subscription_nag() {
    display "  Removing subscription nag..."

    # Create nag removal script
    mkdir -p /usr/local/bin
    cat >/usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    echo "Patching Web UI nag..."
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi

MOBILE_TPL=/usr/share/pve-yew-mobile-gui/index.html.tpl
MARKER="<!-- MANAGED BLOCK FOR MOBILE NAG -->"
if [ -f "$MOBILE_TPL" ] && ! grep -q "$MARKER" "$MOBILE_TPL"; then
    echo "Patching Mobile UI nag..."
    printf "%s\n" \
      "$MARKER" \
      "<script>" \
      "  function removeSubscriptionElements() {" \
      "    // --- Remove subscription dialogs ---" \
      "    const dialogs = document.querySelectorAll('dialog.pwt-outer-dialog');" \
      "    dialogs.forEach(dialog => {" \
      "      const text = (dialog.textContent || '').toLowerCase();" \
      "      if (text.includes('subscription')) {" \
      "        dialog.remove();" \
      "        console.log('Removed subscription dialog');" \
      "      }" \
      "    });" \
      "" \
      "    // --- Remove subscription cards, but keep Reboot/Shutdown/Console ---" \
      "    const cards = document.querySelectorAll('.pwt-card.pwt-p-2.pwt-d-flex.pwt-interactive.pwt-justify-content-center');" \
      "    cards.forEach(card => {" \
      "      const text = (card.textContent || '').toLowerCase();" \
      "      const hasButton = card.querySelector('button');" \
      "      if (!hasButton && text.includes('subscription')) {" \
      "        card.remove();" \
      "        console.log('Removed subscription card');" \
      "      }" \
      "    });" \
      "  }" \
      "" \
      "  const observer = new MutationObserver(removeSubscriptionElements);" \
      "  observer.observe(document.body, { childList: true, subtree: true });" \
      "  removeSubscriptionElements();" \
      "  setInterval(removeSubscriptionElements, 300);" \
      "  setTimeout(() => {observer.disconnect();}, 10000);" \
      "</script>" \
      "" >> "$MOBILE_TPL"
fi
EOF
    chmod 755 /usr/local/bin/pve-remove-nag.sh

    # Create APT hook to run after package updates
    cat >/etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
EOF
    chmod 644 /etc/apt/apt.conf.d/no-nag-script

    # Run the script now
    log "Running nag removal script"
    /usr/local/bin/pve-remove-nag.sh >/dev/null 2>&1 || true

    # Reinstall widget toolkit to apply patches
    log "Reinstalling proxmox-widget-toolkit"
    apt --reinstall install proxmox-widget-toolkit -y >/dev/null 2>&1 || log "WARNING: Widget toolkit reinstall failed"

    display "  ✓ Subscription nag removed (clear browser cache)"
}

disable_ha_services() {
    display "  Configuring HA services for single-node..."

    # PrivateBox is always single-node, disable HA services
    if systemctl is-active --quiet pve-ha-lrm 2>/dev/null; then
        log "Disabling pve-ha-lrm service"
        systemctl disable --now pve-ha-lrm >/dev/null 2>&1 || true
    fi

    if systemctl is-active --quiet pve-ha-crm 2>/dev/null; then
        log "Disabling pve-ha-crm service"
        systemctl disable --now pve-ha-crm >/dev/null 2>&1 || true
    fi

    if systemctl is-active --quiet corosync 2>/dev/null; then
        log "Disabling corosync service"
        systemctl disable --now corosync >/dev/null 2>&1 || true
    fi

    display "  ✓ HA services disabled (single-node optimization)"
}

update_package_lists() {
    display "  Updating package lists..."
    log "Running apt update"

    if apt update >/dev/null 2>&1; then
        display "  ✓ Package lists updated"
    else
        log "WARNING: apt update failed, but continuing"
        display "  ⚠ Package list update failed (non-critical)"
    fi
}

main() {
    display "Optimizing Proxmox VE..."

    # Check we're running as root
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi

    # Detect Proxmox version
    local PVE_VERSION PVE_MAJOR PVE_MINOR
    PVE_VERSION="$(get_pve_version)"
    read -r PVE_MAJOR PVE_MINOR <<<"$(get_pve_major_minor "$PVE_VERSION")"

    log "Detected Proxmox VE version: $PVE_VERSION (major: $PVE_MAJOR, minor: $PVE_MINOR)"
    display "  Proxmox VE $PVE_VERSION detected"

    # Run version-specific optimizations
    if [[ "$PVE_MAJOR" == "8" ]]; then
        if ((PVE_MINOR < 0 || PVE_MINOR > 9)); then
            error_exit "Unsupported Proxmox 8 version: $PVE_VERSION"
        fi
        optimize_proxmox_8
    elif [[ "$PVE_MAJOR" == "9" ]]; then
        if ((PVE_MINOR != 0)); then
            error_exit "Only Proxmox 9.0 is currently supported (found: $PVE_VERSION)"
        fi
        optimize_proxmox_9
    else
        error_exit "Unsupported Proxmox VE major version: $PVE_MAJOR (supported: 8.0-8.9.x and 9.0)"
    fi

    # Common optimizations for all versions
    remove_subscription_nag
    disable_ha_services
    update_package_lists

    display "  ✓ Proxmox VE optimizations complete"
    log "Proxmox optimizations completed successfully"

    display ""
    display "  NOTE: Clear your browser cache (Ctrl+Shift+R) before accessing Proxmox Web UI"
}

# Run main
main "$@"
