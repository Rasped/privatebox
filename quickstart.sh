#!/bin/bash
# PrivateBox Quick Start Script
# 
# Simple installation method for PrivateBox
# 
# Recommended usage (safer):
#   curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh
#   sudo bash quickstart.sh [options]
#
# One-line usage:
#   curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
#
# Available options:
#   --dry-run          Run pre-flight checks and generate config only (no VM)
#   --no-cleanup       Keep downloaded files after installation
#   --branch <branch>  Use specific git branch (default: main)
#   --verbose, -v      Show detailed output
#   --help             Show this help message

set -euo pipefail

# Configuration
REPO_URL="https://github.com/Rasped/privatebox"
REPO_BRANCH="main"
TEMP_DIR="/tmp/privatebox-quickstart"
CLEANUP_AFTER=true
DRY_RUN=false
VERBOSE=false

# Detect if running via pipe (non-interactive)
if [ ! -t 0 ]; then
    PIPED_INPUT=true
else
    PIPED_INPUT=false
fi

# Color codes for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    # No colors for non-terminal output
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

print_banner() {
    echo -e "${BLUE}==========================================="
    echo "     PrivateBox Quick Start"
    echo "==========================================="
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run          Run pre-flight checks and generate config only"
    echo "  --no-cleanup       Keep downloaded files after installation"
    echo "  --branch <branch>  Use specific git branch (default: main)"
    echo "  --verbose, -v      Show detailed output"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive installation"
    echo "  $0 --dry-run          # Test without creating VM"
    echo "  $0 --no-cleanup       # Keep downloaded files"
    echo "  $0 --branch develop   # Use develop branch"
}

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

success_msg() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning_msg() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

info_msg() {
    echo -e "$1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-cleanup)
            CLEANUP_AFTER=false
            shift
            ;;
        --branch)
            if [[ -z "${2:-}" ]]; then
                error_exit "Branch name required for --branch option"
            fi
            REPO_BRANCH="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help)
            print_banner
            print_usage
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1\nUse --help for usage information"
            ;;
    esac
done

# Pre-flight checks
run_preflight_checks() {
    info_msg "Running pre-flight checks..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
    
    # Check if running on Proxmox
    if [[ ! -d /etc/pve ]]; then
        error_exit "This script must be run on a Proxmox VE host"
    fi
    
    # Fix Proxmox repository configuration first
    # This prevents enterprise repository warnings/errors
    info_msg "Configuring Proxmox repositories..."
    
    # Disable enterprise repositories
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list
        [[ "$VERBOSE" == true ]] && info_msg "  Disabled enterprise repository"
    fi
    
    if [[ -f /etc/apt/sources.list.d/ceph.list ]]; then
        sed -i 's/^/#/' /etc/apt/sources.list.d/ceph.list
        [[ "$VERBOSE" == true ]] && info_msg "  Disabled Ceph enterprise repository"
    fi
    
    # Enable no-subscription repository if not already present
    if ! grep -q "^deb.*pve-no-subscription" /etc/apt/sources.list.d/*.list 2>/dev/null; then
        echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
        [[ "$VERBOSE" == true ]] && info_msg "  Enabled no-subscription repository"
    fi
    
    success_msg "Repository configuration fixed"
    
    # Check and install git if needed (Proxmox may not have it by default)
    if ! command -v git &> /dev/null; then
        warning_msg "Git not found on this system. Installing git..."
        info_msg "Running: apt-get update"
        if ! apt-get update; then
            error_exit "Failed to update package list. Please install git manually: apt-get install git"
        fi
        info_msg "Running: apt-get install -y git"
        if ! apt-get install -y git; then
            error_exit "Failed to install git. Please install manually: apt-get install git"
        fi
        # Verify git is now available
        if command -v git &> /dev/null; then
            success_msg "Git installed successfully"
        else
            error_exit "Git installation completed but git command still not found. Please check your system."
        fi
    else
        success_msg "Git is already installed"
    fi
    
    # Check for other required commands
    for cmd in curl wget qm; do
        if ! command -v $cmd &> /dev/null; then
            error_exit "Required command '$cmd' not found"
        fi
    done
    
    # Check internet connectivity
    if ! curl -s --head --connect-timeout 5 https://github.com > /dev/null; then
        error_exit "Cannot reach GitHub. Check internet connection"
    fi
    
    success_msg "Pre-flight checks passed"
}

# Download repository
download_repository() {
    info_msg "Downloading PrivateBox repository..."
    
    # Clean up any existing directory
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Clone repository
    if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TEMP_DIR" &>/dev/null; then
        error_exit "Failed to download repository from branch '$REPO_BRANCH'"
    fi
    
    success_msg "Repository downloaded (branch: $REPO_BRANCH)"
}

# Show confirmation prompt
confirm_installation() {
    if [[ "$PIPED_INPUT" == true ]]; then
        info_msg "Running in non-interactive mode (piped input detected)"
        return 0
    fi
    
    echo ""
    info_msg "Installation Summary:"
    info_msg "  • Repository branch: $REPO_BRANCH"
    info_msg "  • Installation path: $TEMP_DIR"
    info_msg "  • Dry-run mode: $DRY_RUN"
    info_msg "  • Verbose output: $VERBOSE"
    info_msg "  • Cleanup after: $CLEANUP_AFTER"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        info_msg "This will run pre-flight checks and generate configuration only."
        info_msg "No VM will be created."
    else
        warning_msg "This will create a new VM with ID 9000."
        warning_msg "Any existing VM with ID 9000 will be destroyed!"
    fi
    
    echo ""
    read -p "Do you want to continue? (yes/no) " -r REPLY
    
    # Accept various forms of "yes"
    if [[ "$REPLY" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info_msg "Starting installation..."
    else
        info_msg "Installation cancelled"
        exit 0
    fi
}

# Run bootstrap
run_bootstrap() {
    info_msg "Starting PrivateBox bootstrap..."
    
    cd "$TEMP_DIR"
    
    # Use the bootstrap script
    local bootstrap_script="./bootstrap/bootstrap.sh"
    if [[ ! -f "$bootstrap_script" ]]; then
        error_exit "Bootstrap script not found at $bootstrap_script"
    fi
    
    # Build bootstrap command with arguments
    local bootstrap_cmd="$bootstrap_script"
    
    if [[ "$DRY_RUN" == true ]]; then
        bootstrap_cmd="$bootstrap_cmd --dry-run"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        bootstrap_cmd="$bootstrap_cmd --verbose"
    fi
    
    # Run bootstrap
    if [[ "$VERBOSE" == true ]]; then
        if ! bash $bootstrap_cmd; then
            error_exit "Bootstrap failed. Check /tmp/privatebox-bootstrap.log for details"
        fi
    else
        if ! bash $bootstrap_cmd 2>&1 | while IFS= read -r line; do
            # Filter output for non-verbose mode
            if [[ "$line" =~ ^Phase ]] || [[ "$line" =~ ^✓ ]] || [[ "$line" =~ ^✅ ]] || \
               [[ "$line" =~ ERROR ]] || [[ "$line" =~ "Installation Complete" ]] || \
               [[ "$line" =~ "VM Details:" ]] || [[ "$line" =~ "Access Credentials:" ]] || \
               [[ "$line" =~ "Service Access:" ]] || [[ "$line" =~ "IP Address:" ]] || \
               [[ "$line" =~ "Password:" ]] || [[ "$line" =~ "http://" ]]; then
                echo "$line"
            fi
        done; then
            error_exit "Bootstrap failed. Check /tmp/privatebox-bootstrap.log for details"
        fi
    fi
}

# Cleanup function
cleanup() {
    if [[ "$CLEANUP_AFTER" == true ]] && [[ -d "$TEMP_DIR" ]]; then
        info_msg "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
        success_msg "Cleanup complete"
    fi
}

# Main execution
main() {
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Print banner
    print_banner
    
    # Run pre-flight checks
    run_preflight_checks
    
    # Show confirmation
    confirm_installation
    
    # Download repository
    download_repository
    
    # Run bootstrap
    run_bootstrap
    
    # Success message
    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        success_msg "Dry-run completed successfully!"
        info_msg "Run without --dry-run to create the VM"
    else
        success_msg "PrivateBox installation completed successfully!"
        info_msg "Check /tmp/privatebox-bootstrap.log for detailed logs"
    fi
}

# Run main function
main "$@"