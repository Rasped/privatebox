#!/bin/bash
#
# PrivateBox Asset Download Script
# Downloads all assets required for offline recovery and factory provisioning
#
# This script downloads:
# - Container images (saved as .tar files)
# - VM images (Debian cloud image, OPNsense template)
# - Source code (PrivateBox repository)
# - Proxmox VE packages (for Debian → Proxmox conversion)
#
# Usage: ./download-assets.sh [--assets-dir /path/to/assets]
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="${ASSETS_DIR:-/var/privatebox/assets}"
MANIFEST_FILE="${SCRIPT_DIR}/assets-manifest.json"
LOG_FILE="/tmp/privatebox-asset-download.log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --assets-dir)
            ASSETS_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--assets-dir /path/to/assets]"
            echo ""
            echo "Downloads all PrivateBox assets to local directory for offline use."
            echo ""
            echo "Options:"
            echo "  --assets-dir PATH    Directory to store assets (default: /var/privatebox/assets)"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}→${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

error_exit() {
    error "$1"
    exit 1
}

# Pre-flight checks
preflight_checks() {
    log "Running pre-flight checks..."

    # Check root
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (required for apt operations)"
    fi
    success "Running as root"

    # Check required commands
    local required_commands=("wget" "podman" "jq" "md5sum")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error_exit "Required command not found: $cmd"
        fi
    done
    success "All required commands available"

    # Check manifest exists
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        error_exit "Manifest file not found: $MANIFEST_FILE"
    fi
    success "Manifest file found"

    # Check internet connectivity
    if ! wget -q --spider --timeout=5 http://download.proxmox.com 2>/dev/null; then
        error_exit "No internet connectivity (cannot reach download.proxmox.com)"
    fi
    success "Internet connectivity verified"

    # Estimate disk space needed
    local space_needed=$((6 * 1024 * 1024)) # 6GB in KB
    local space_available=$(df -k "$ASSETS_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || df -k / | awk 'NR==2 {print $4}')

    if [[ $space_available -lt $space_needed ]]; then
        error_exit "Insufficient disk space. Need ~6GB, have $(( space_available / 1024 / 1024 ))GB"
    fi
    success "Sufficient disk space available"
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."

    mkdir -p "$ASSETS_DIR"/{containers,images,templates,source,proxmox/packages,installer,recovery}

    success "Directory structure created at $ASSETS_DIR"
}

# Download container images
download_container_images() {
    log "Downloading container images..."

    local containers_dir="$ASSETS_DIR/containers"

    # Array of container images (registry/image:tag|filename)
    local images=(
        "docker.io/portainer/portainer-ce:latest|portainer-ce-latest.tar"
        "docker.io/adguard/adguardhome:latest|adguard-home-latest.tar"
        "docker.io/b4bz/homer:latest|homer-latest.tar"
        "docker.io/headscale/headscale:latest|headscale-latest.tar"
        "ghcr.io/tale/headplane:latest|headplane-latest.tar"
        "docker.io/semaphoreui/semaphore:latest|semaphore-base-latest.tar"
        "docker.io/caddy:2-alpine|caddy-base-2-alpine.tar"
    )

    for image_spec in "${images[@]}"; do
        local image="${image_spec%|*}"
        local filename="${image_spec#*|}"
        local filepath="$containers_dir/$filename"

        if [[ -f "$filepath" ]]; then
            info "Container image already exists: $filename"
            continue
        fi

        info "Pulling container image: $image"
        if podman pull "$image" 2>&1 | tee -a "$LOG_FILE"; then
            info "Saving container image to: $filename"
            if podman save -o "$filepath" "$image" 2>&1 | tee -a "$LOG_FILE"; then
                success "Saved: $filename ($(du -h "$filepath" | cut -f1))"
            else
                error "Failed to save: $filename"
            fi
        else
            error "Failed to pull: $image"
        fi
    done

    success "Container images download complete"
}

# Download VM images
download_vm_images() {
    log "Downloading VM images..."

    # Debian cloud image
    local debian_url="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    local debian_file="$ASSETS_DIR/images/debian-13-genericcloud-amd64.qcow2"

    if [[ -f "$debian_file" ]]; then
        info "Debian cloud image already exists"
    else
        info "Downloading Debian 13 cloud image (~400MB)..."
        if wget --progress=bar:force -O "$debian_file" "$debian_url" 2>&1 | tee -a "$LOG_FILE"; then
            success "Downloaded: debian-13-genericcloud-amd64.qcow2 ($(du -h "$debian_file" | cut -f1))"
        else
            error "Failed to download Debian cloud image"
            rm -f "$debian_file"
        fi
    fi

    # OPNsense template
    local opnsense_url="https://github.com/Rasped/privatebox/releases/download/v1.0.2-opnsense/vzdump-qemu-105-opnsense.vma.zst"
    local opnsense_file="$ASSETS_DIR/templates/vzdump-qemu-105-opnsense.vma.zst"
    local opnsense_md5="c6d251e1c62f065fd28d720572f8f943"

    if [[ -f "$opnsense_file" ]]; then
        info "OPNsense template already exists, verifying checksum..."
        local existing_md5=$(md5sum "$opnsense_file" | awk '{print $1}')
        if [[ "$existing_md5" == "$opnsense_md5" ]]; then
            success "OPNsense template verified (MD5 match)"
        else
            warning "OPNsense template MD5 mismatch, re-downloading..."
            rm -f "$opnsense_file"
        fi
    fi

    if [[ ! -f "$opnsense_file" ]]; then
        info "Downloading OPNsense template (~767MB, this may take several minutes)..."
        if wget --progress=bar:force -O "$opnsense_file" "$opnsense_url" 2>&1 | tee -a "$LOG_FILE"; then
            # Verify MD5
            local downloaded_md5=$(md5sum "$opnsense_file" | awk '{print $1}')
            if [[ "$downloaded_md5" == "$opnsense_md5" ]]; then
                success "Downloaded and verified: vzdump-qemu-105-opnsense.vma.zst ($(du -h "$opnsense_file" | cut -f1))"
            else
                error "OPNsense template MD5 verification failed"
                error "Expected: $opnsense_md5, Got: $downloaded_md5"
                rm -f "$opnsense_file"
            fi
        else
            error "Failed to download OPNsense template"
            rm -f "$opnsense_file"
        fi
    fi

    success "VM images download complete"
}

# Download source code
download_source_code() {
    log "Downloading PrivateBox source code..."

    local repo_url="https://github.com/Rasped/privatebox/archive/refs/heads/main.tar.gz"
    local repo_file="$ASSETS_DIR/source/privatebox-main.tar.gz"

    if [[ -f "$repo_file" ]]; then
        info "PrivateBox source already exists"
    else
        info "Downloading PrivateBox repository..."
        if wget --progress=bar:force -O "$repo_file" "$repo_url" 2>&1 | tee -a "$LOG_FILE"; then
            success "Downloaded: privatebox-main.tar.gz ($(du -h "$repo_file" | cut -f1))"
        else
            error "Failed to download PrivateBox source"
            rm -f "$repo_file"
        fi
    fi

    success "Source code download complete"
}

# Download Proxmox packages
download_proxmox_packages() {
    log "Downloading Proxmox VE packages..."

    local proxmox_dir="$ASSETS_DIR/proxmox"
    local packages_dir="$proxmox_dir/packages"

    # Download GPG key
    local gpg_url="https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg"
    local gpg_file="$proxmox_dir/proxmox-archive-keyring-trixie.gpg"
    local gpg_sha256="136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45"

    if [[ -f "$gpg_file" ]]; then
        info "Proxmox GPG key already exists, verifying..."
        local existing_sha256=$(sha256sum "$gpg_file" | awk '{print $1}')
        if [[ "$existing_sha256" == "$gpg_sha256" ]]; then
            success "Proxmox GPG key verified (SHA256 match)"
        else
            warning "Proxmox GPG key SHA256 mismatch, re-downloading..."
            rm -f "$gpg_file"
        fi
    fi

    if [[ ! -f "$gpg_file" ]]; then
        info "Downloading Proxmox GPG key..."
        if wget -q -O "$gpg_file" "$gpg_url"; then
            local downloaded_sha256=$(sha256sum "$gpg_file" | awk '{print $1}')
            if [[ "$downloaded_sha256" == "$gpg_sha256" ]]; then
                success "Downloaded and verified: proxmox-archive-keyring-trixie.gpg"
            else
                error "Proxmox GPG key SHA256 verification failed"
                rm -f "$gpg_file"
                return 1
            fi
        else
            error "Failed to download Proxmox GPG key"
            return 1
        fi
    fi

    # Save repository configuration
    local repo_config_file="$proxmox_dir/pve-install-repo.sources"
    cat > "$repo_config_file" <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    success "Created repository configuration file"

    # Add Proxmox repository temporarily (if not already added)
    local temp_repo_added=false
    if [[ ! -f /etc/apt/sources.list.d/pve-install-repo.sources ]]; then
        info "Adding Proxmox repository temporarily..."
        cp "$gpg_file" /usr/share/keyrings/proxmox-archive-keyring.gpg
        cp "$repo_config_file" /etc/apt/sources.list.d/pve-install-repo.sources
        temp_repo_added=true

        info "Updating package lists..."
        apt-get update 2>&1 | tee -a "$LOG_FILE"
    fi

    # Download Proxmox packages (without installing)
    info "Downloading Proxmox VE packages and dependencies (~2GB)..."
    info "This may take 10-20 minutes depending on your connection..."

    # Clear apt cache first to get fresh downloads
    apt-get clean

    # Download packages
    if apt-get install -y --download-only \
        proxmox-default-kernel \
        proxmox-ve \
        postfix \
        open-iscsi \
        chrony 2>&1 | tee -a "$LOG_FILE"; then

        # Copy downloaded packages to assets directory
        info "Copying packages to assets directory..."
        cp -v /var/cache/apt/archives/*.deb "$packages_dir/" 2>&1 | tee -a "$LOG_FILE"

        local package_count=$(ls -1 "$packages_dir"/*.deb 2>/dev/null | wc -l)
        local packages_size=$(du -sh "$packages_dir" | cut -f1)

        success "Downloaded $package_count Proxmox packages ($packages_size)"
    else
        error "Failed to download Proxmox packages"
    fi

    # Clean up temporary repository configuration
    if [[ "$temp_repo_added" == "true" ]]; then
        info "Removing temporary Proxmox repository..."
        rm -f /etc/apt/sources.list.d/pve-install-repo.sources
        apt-get update 2>&1 | tee -a "$LOG_FILE"
    fi

    success "Proxmox packages download complete"
}

# Display summary
display_summary() {
    log ""
    log "=========================================="
    log "Asset Download Summary"
    log "=========================================="
    log ""
    log "Assets downloaded to: $ASSETS_DIR"
    log ""

    # Count files in each directory
    local containers_count=$(ls -1 "$ASSETS_DIR/containers"/*.tar 2>/dev/null | wc -l)
    local images_count=$(ls -1 "$ASSETS_DIR/images"/*.qcow2 2>/dev/null | wc -l)
    local templates_count=$(ls -1 "$ASSETS_DIR/templates"/*.vma.zst 2>/dev/null | wc -l)
    local source_count=$(ls -1 "$ASSETS_DIR/source"/*.tar.gz 2>/dev/null | wc -l)
    local proxmox_packages=$(ls -1 "$ASSETS_DIR/proxmox/packages"/*.deb 2>/dev/null | wc -l)

    log "Container images: $containers_count files ($(du -sh "$ASSETS_DIR/containers" 2>/dev/null | cut -f1 || echo "0"))"
    log "VM images: $images_count files ($(du -sh "$ASSETS_DIR/images" 2>/dev/null | cut -f1 || echo "0"))"
    log "VM templates: $templates_count files ($(du -sh "$ASSETS_DIR/templates" 2>/dev/null | cut -f1 || echo "0"))"
    log "Source code: $source_count files ($(du -sh "$ASSETS_DIR/source" 2>/dev/null | cut -f1 || echo "0"))"
    log "Proxmox packages: $proxmox_packages files ($(du -sh "$ASSETS_DIR/proxmox/packages" 2>/dev/null | cut -f1 || echo "0"))"
    log ""
    log "Total size: $(du -sh "$ASSETS_DIR" | cut -f1)"
    log ""
    log "=========================================="
    log ""
    success "All assets downloaded successfully!"
    log ""
    log "Next steps:"
    log "  1. Verify all assets are present and checksums match"
    log "  2. Copy assets to recovery partition (future implementation)"
    log "  3. Test offline installation using these assets"
    log ""
    log "Log file: $LOG_FILE"
}

# Main execution
main() {
    log "PrivateBox Asset Download Script"
    log "Assets will be downloaded to: $ASSETS_DIR"
    log ""

    preflight_checks
    create_directories
    download_container_images
    download_vm_images
    download_source_code
    download_proxmox_packages
    display_summary
}

# Run main
main "$@"
