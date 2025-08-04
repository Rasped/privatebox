#!/bin/bash
# PrivateBox Quick Start Script
# 
# This script provides a simple installation method for PrivateBox
# 
# Recommended usage (safer):
#   curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh
#   sudo bash quickstart.sh [options]
#
# One-line usage (less secure):
#   curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
#
# Available options:
#   --ip <IP>           Set static IP for the VM
#   --gateway <IP>      Set gateway IP
#   --no-auto          Skip network auto-discovery
#   --cleanup          Remove downloaded files after installation
#   --branch <branch>  Use specific git branch (default: main)
#   --distro <distro>  Choose VM distro: debian or ubuntu (default: debian)
#   --yes, -y          Skip confirmation prompt
#   --help             Show this help message

set -euo pipefail

# Configuration
REPO_URL="https://github.com/Rasped/privatebox"
REPO_BRANCH="main"
TEMP_DIR="/tmp/privatebox-quickstart"
CLEANUP_AFTER=true  # Default to cleaning up
SKIP_CONFIRMATION=false

# Color codes for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    # No colors for non-terminal output
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

print_banner() {
    echo "==========================================="
    echo "     PrivateBox Quick Start Installer"
    echo "==========================================="
    echo ""
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

show_usage() {
    cat << EOF
PrivateBox Quick Start Script

Usage: 
    sudo bash quickstart.sh [options]

Options:
    --ip <IP>           Set static IP for the VM
    --gateway <IP>      Set gateway IP  
    --no-auto          Skip network auto-discovery
    --no-cleanup       Keep downloaded files after installation
    --branch <branch>  Use specific git branch (default: main)
    --distro <distro>  Choose VM distro: debian or ubuntu (default: debian)
    --yes, -y          Skip confirmation prompt
    --help             Show this help message

Examples:
    # Download and run (recommended)
    curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh
    sudo bash quickstart.sh

    # Basic installation with auto-discovery
    sudo bash quickstart.sh

    # Set custom IP address
    sudo bash quickstart.sh --ip 192.168.1.50

    # Use specific gateway
    sudo bash quickstart.sh --ip 192.168.1.50 --gateway 192.168.1.1

    # Use development branch
    sudo bash quickstart.sh --branch develop

    # Skip confirmation prompt
    sudo bash quickstart.sh --yes

EOF
}

check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi

    if ! command -v qm &> /dev/null; then
        print_error "This script must be run on a Proxmox VE host"
        print_error "The 'qm' command was not found"
        exit 1
    fi

    if command -v pveversion &> /dev/null; then
        print_info "Detected Proxmox VE: $(pveversion | cut -d'/' -f2)"
    fi

    local missing_tools=()
    
    for tool in curl tar jq; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_warn "Missing tools: ${missing_tools[*]}"
        print_info "Installing missing tools..."
        if ! apt-get update >/dev/null 2>&1; then
            print_error "Failed to update package lists"
            exit 1
        fi
        if ! apt-get install -y "${missing_tools[@]}" >/dev/null 2>&1; then
            print_error "Failed to install required tools: ${missing_tools[*]}"
            exit 1
        fi
    fi
}

download_repository() {
    print_info "Downloading PrivateBox bootstrap files..."
    
    if [[ -d "$TEMP_DIR" ]]; then
        print_info "Removing existing installation directory..."
        rm -rf "$TEMP_DIR"
    fi
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    print_info "Downloading from ${REPO_URL}/archive/${REPO_BRANCH}.tar.gz"
    
    local temp_tar="/tmp/privatebox-$$.tar.gz"
    
    if ! curl -fsSL "${REPO_URL}/archive/${REPO_BRANCH}.tar.gz" -o "$temp_tar"; then
        print_error "Failed to download from GitHub"
        print_error "Check your internet connection and try again"
        exit 1
    fi
    
    if ! tar -xzf "$temp_tar" --strip-components=1 "privatebox-${REPO_BRANCH}/bootstrap"; then
        print_error "Failed to extract bootstrap files"
        print_error "This might be a temporary issue. Please try again."
        rm -f "$temp_tar"
        exit 1
    fi
    
    rm -f "$temp_tar"

    print_info "Bootstrap files downloaded to $TEMP_DIR"
}

prepare_bootstrap() {
    print_info "Preparing bootstrap environment..."
    
    find "$TEMP_DIR/bootstrap" -name "*.sh" -type f -exec chmod +x {} \;
    
    if [[ ! -f "$TEMP_DIR/bootstrap/bootstrap.sh" ]]; then
        print_error "bootstrap.sh not found in downloaded repository"
        exit 1
    fi
}

run_bootstrap() {
    local bootstrap_args=()
    
    if [[ "${USE_AUTO_DISCOVERY:-true}" == "false" ]]; then
        bootstrap_args+=("--no-auto")
    fi
    
    if [[ -n "${STATIC_IP:-}" ]]; then
        bootstrap_args+=("--ip" "$STATIC_IP")
    fi
    
    if [[ -n "${GATEWAY_IP:-}" ]]; then
        bootstrap_args+=("--gateway" "$GATEWAY_IP")
    fi
    
    if [[ -n "${VM_DISTRO:-}" ]]; then
        bootstrap_args+=("--distro" "$VM_DISTRO")
    fi
    
    print_info "Starting PrivateBox installation..."
    print_info "This process will:"
    print_info "  1. Detect network configuration"
    print_info "  2. Create ${VM_DISTRO:-Debian} VM"
    print_info "  3. Install and configure services"
    print_info "  4. Wait for complete installation (5-10 minutes)"
    echo ""
    
    cd "$TEMP_DIR/bootstrap"
    
    if [[ ${#bootstrap_args[@]} -gt 0 ]]; then
        print_info "Running: ./bootstrap.sh ${bootstrap_args[*]}"
        ./bootstrap.sh "${bootstrap_args[@]}"
    else
        ./bootstrap.sh
    fi
}

cleanup() {
    if [[ "$CLEANUP_AFTER" == "true" ]]; then
        if [[ -d "$TEMP_DIR" ]]; then
            print_info "Cleaning up temporary files..."
            rm -rf "$TEMP_DIR"
        fi
    else
        print_info "Installation files retained at: $TEMP_DIR"
        print_info "To remove manually: rm -rf $TEMP_DIR"
    fi
}

main() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ip)
                STATIC_IP="$2"
                shift 2
                ;;
            --gateway)
                GATEWAY_IP="$2"
                shift 2
                ;;
            --no-auto)
                USE_AUTO_DISCOVERY=false
                shift
                ;;
            --no-cleanup)
                CLEANUP_AFTER=false
                shift
                ;;
            --branch)
                REPO_BRANCH="$2"
                shift 2
                ;;
            --distro)
                VM_DISTRO="$2"
                if [[ "$VM_DISTRO" != "debian" && "$VM_DISTRO" != "ubuntu" ]]; then
                    print_error "Invalid distro: $VM_DISTRO. Must be 'debian' or 'ubuntu'"
                    exit 1
                fi
                shift 2
                ;;
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    print_banner
    
    echo "Welcome to PrivateBox!"
    echo ""
    echo "This installer will set up a privacy-focused router system on your Proxmox server."
    echo ""
    echo "What will happen:"
    echo "  ✓ Create a ${VM_DISTRO:-Debian} virtual machine"
    echo "  ✓ Install Portainer for container management"  
    echo "  ✓ Install Semaphore for Ansible automation"
    echo "  ✓ Configure networking and security settings"
    echo "  ✓ Auto-detect network and assign IP address"
    echo ""
    echo "Requirements:"
    echo "  • Proxmox VE 7.0 or higher"
    echo "  • At least 4GB free RAM"
    echo "  • At least 10GB free storage"
    echo "  • Internet connection"
    echo ""
    echo "The installation will take approximately 5-10 minutes."
    echo ""
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        if [[ -t 0 ]]; then
            # Interactive mode - ask for confirmation
            read -p "Do you want to continue? (yes/no) " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Installation cancelled."
                exit 0
            fi
        else
            # Non-interactive mode - proceed with notice
            print_info "Running in non-interactive mode. Proceeding with installation..."
            print_info "To cancel, press Ctrl+C within the next 3 seconds..."
            sleep 3
        fi
        echo ""
    else
        print_info "Skipping confirmation (--yes flag provided)"
        echo ""
    fi
    
    check_prerequisites
    download_repository
    prepare_bootstrap
    run_bootstrap
    
    cleanup
    
    print_info ""
    print_info "PrivateBox installation completed!"
    print_info "Check the output above for connection details."
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Installation failed with exit code: $exit_code"
    fi
    # Always clean up unless --cleanup=false was explicitly set
    if [[ "$CLEANUP_AFTER" != "false" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup_on_exit EXIT

main "$@"