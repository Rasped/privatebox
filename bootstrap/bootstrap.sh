#!/bin/bash
#
# PrivateBox Bootstrap - Main Orchestrator
# Simple, robust, phased installation process
#

set -euo pipefail

# Fix locale warnings from Perl (qm, pvesm commands)
export LC_ALL=C

# Set fallback TERM for tput commands when running via pipe (e.g., curl | bash)
export TERM="${TERM:-dumb}"

# Detect if stdout is a real terminal (spinners produce garbage over SSH pipes)
IS_TTY=false
[[ -t 1 ]] && IS_TTY=true
export IS_TTY
DOTS_PRINTED=false

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LOG_FILE="/tmp/privatebox-bootstrap.log"
CONFIG_FILE="/tmp/privatebox-config.conf"

# Default values
DRY_RUN=false
VERBOSE=false
QUIET_MODE=false
VMID=9000

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --setup-proxmox-api)
            # Run Proxmox API setup
            if [[ ! -f "${SCRIPT_DIR}/scripts/setup-proxmox-api-token.sh" ]]; then
                echo "ERROR: Proxmox API setup script not found"
                exit 1
            fi
            exec "${SCRIPT_DIR}/scripts/setup-proxmox-api-token.sh"
            ;;
        --help|-h)
            cat <<EOF
PrivateBox Bootstrap

Usage: $0 [OPTIONS]

Options:
    --dry-run       Run pre-flight checks and generate config only (no VM creation)
    --verbose, -v   Show detailed output
    --quiet         Show minimal output with in-place spinner (default for quickstart.sh)
    --help, -h      Show this help message
    --setup-proxmox-api  Setup Proxmox API token (run on Proxmox host)

The bootstrap process has 4 phases:
1. Host preparation - Pre-flight checks and config generation
2. OPNsense deployment - Deploy and configure firewall VM
3. VM provisioning - Create management VM with cloud-init
4. Service configuration - Install services and verify

Optional: Setup Proxmox API token for automation (use --setup-proxmox-api)

Logs are written to: $LOG_FILE
Configuration saved to: $CONFIG_FILE
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Initialize logging
init_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PrivateBox Bootstrap starting" > "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Arguments: dry-run=$DRY_RUN, verbose=$VERBOSE, quiet=$QUIET_MODE" >> "$LOG_FILE"
}

# Log function
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    if [[ "$VERBOSE" == true ]]; then
        echo "$message"
    fi
}

# Display important messages (always shown)
display() {
    local message="$1"
    if [[ "${DOTS_PRINTED:-false}" == true ]]; then
        echo ""
        DOTS_PRINTED=false
    fi
    echo "$message"
    log "$message"
}

# Update status line at bottom of terminal
# Usage: update_status_line "spinner_char"
update_status_line() {
    if [[ "$QUIET_MODE" == true ]] && [[ "$IS_TTY" == true ]]; then
        local spinner_char="$1"
        tput sc 2>/dev/null || true                    # Save cursor position
        tput cup $(tput lines) 0 2>/dev/null || true   # Move to last line
        tput sgr0 2>/dev/null || true                  # Reset colors/attributes
        tput el 2>/dev/null || true                    # Clear line
        printf "%s Configuring PrivateBox..." "$spinner_char"
        tput rc 2>/dev/null || true                    # Restore cursor
    elif [[ "$QUIET_MODE" == true ]]; then
        # Non-TTY (SSH pipe): print dot every ~30s to keep pipe buffer flushing
        SPINNER_COUNT=$((${SPINNER_COUNT:-0} + 1))
        if [[ $((SPINNER_COUNT % 30)) -eq 0 ]]; then
            printf "."
            DOTS_PRINTED=true
        fi
    fi
}

# Clear status line at bottom of terminal
cleanup_status_line() {
    if [[ "$QUIET_MODE" == true ]] && [[ "$IS_TTY" == true ]]; then
        tput sc 2>/dev/null || true
        tput cup $(tput lines) 0 2>/dev/null || true
        tput sgr0 2>/dev/null || true                  # Reset colors/attributes
        tput el 2>/dev/null || true
        tput rc 2>/dev/null || true
    elif [[ "${DOTS_PRINTED:-false}" == true ]]; then
        echo ""
        DOTS_PRINTED=false
    fi
}

# Error handler
error_exit() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >> "$LOG_FILE"
    echo "ERROR: $message" >&2
    echo "Check log file for details: $LOG_FILE"
    exit 1
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "Bootstrap failed with exit code: $exit_code"
        display "❌ Bootstrap failed. Check $LOG_FILE for details"
    fi
}

trap cleanup EXIT

# Main execution
main() {
    init_log
    
    display "======================================"
    display "   PrivateBox Bootstrap"
    display "======================================"
    display ""
    
    # Phase 1: Host Preparation
    display "Phase 1: Host Preparation"
    display "-------------------------"
    log "Starting Phase 1: Host preparation"
    
    if [[ ! -f "${SCRIPT_DIR}/prepare-host.sh" ]]; then
        error_exit "prepare-host.sh not found"
    fi
    
    if ! bash "${SCRIPT_DIR}/prepare-host.sh"; then
        error_exit "Host preparation failed"
    fi
    
    # Load generated config
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not generated: $CONFIG_FILE"
    fi
    
    source "$CONFIG_FILE"
    log "Configuration loaded successfully"

    cleanup_status_line
    display ""

    # Check for dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        display "======================================"
        display "   Dry-run Complete"
        display "======================================"
        display ""
        display "Configuration generated at: $CONFIG_FILE"
        display "Network settings:"
        display "  Gateway: ${GATEWAY:-not set}"
        display "  Bridge: ${VM_NET_BRIDGE:-not set}"
        display "  VM IP: ${STATIC_IP:-not set}"
        display ""
        display "Credentials generated:"
        display "  Admin password: ${ADMIN_PASSWORD:-not set}"
        display "  Services password: ${SERVICES_PASSWORD:-not set}"
        display ""
        display "Run without --dry-run to create VM"
        log "Dry-run completed successfully"
        exit 0
    fi
    
    # Phase 2: OPNsense Deployment
    display "Phase 2: OPNsense Deployment"
    display "-----------------------------"
    log "Starting Phase 2: OPNsense deployment"
    
    if [[ ! -f "${SCRIPT_DIR}/deploy-opnsense.sh" ]]; then
        display "⚠️  OPNsense deployment script not found"
        display "   Skipping firewall deployment"
        display "   Note: Management VM will need a gateway configured"
        log "WARNING: deploy-opnsense.sh not found, skipping"
    else
        local opnsense_args=""
        if [[ "$QUIET_MODE" == true ]]; then
            opnsense_args="--quiet"
        fi
        if ! bash "${SCRIPT_DIR}/deploy-opnsense.sh" $opnsense_args; then
            error_exit "OPNsense deployment failed - cannot continue without firewall"
        else
            cleanup_status_line
        fi
    fi
    display ""
    
    # Phase 3: Management VM Provisioning
    display "Phase 3: Management VM Provisioning"
    display "------------------------------------"
    log "Starting Phase 3: Management VM provisioning"
    
    if [[ ! -f "${SCRIPT_DIR}/create-vm.sh" ]]; then
        error_exit "create-vm.sh not found"
    fi

    local createvm_args=""
    if [[ "$QUIET_MODE" == true ]]; then
        createvm_args="--quiet"
    fi
    if ! bash "${SCRIPT_DIR}/create-vm.sh" $createvm_args; then
        error_exit "VM creation failed"
    fi

    cleanup_status_line
    display ""

    # Phase 4: Service Configuration (runs inside VM via cloud-init)
    display "Phase 4: Service Configuration"
    display "-------------------------------"
    log "Phase 4: Service configuration started via cloud-init"

    # Monitor Phase 4 progress by checking the VM's marker file
    display "⏳ Waiting for guest setup to complete..."
    display "   This may take 15-20 minutes for full service deployment"

    # Define SSH key path (same as verify-install.sh uses)
    local ssh_key_path="${SSH_KEY_PATH:-/root/.ssh/id_ed25519}"
    local ssh_opts="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    if [[ -f "$ssh_key_path" ]]; then
        ssh_opts="$ssh_opts -i $ssh_key_path"
    fi

    # Wait for VM to be accessible first
    local elapsed=0
    local vm_accessible=false
    local phase4_progress_shown=false
    while [[ $elapsed -lt 120 ]]; do
        if ssh $ssh_opts "${VM_USERNAME}@${STATIC_IP}" "echo 'SSH ready'" &>/dev/null; then
            vm_accessible=true
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ "$vm_accessible" == true ]]; then
        # Poll for Phase 4 progress messages
        local last_line_count=0
        local phase4_timeout=1500  # 25 minutes (allows for 20min orchestration + buffer)
        elapsed=0
        local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        local spinner_index=0
        local check_interval=10  # Check for progress every 10 seconds
        local seconds_since_check=0

        while [[ $elapsed -lt $phase4_timeout ]]; do
            # Check for progress every 10 seconds
            if [[ $seconds_since_check -ge $check_interval ]]; then
                # Get the marker file content
                local file_content=$(ssh $ssh_opts \
                              "${VM_USERNAME}@${STATIC_IP}" "cat /etc/privatebox-install-complete 2>/dev/null" || echo "PENDING")

                # Get the last line for status check
                local status=$(echo "$file_content" | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                # Process any new progress messages
                if [[ -n "$file_content" ]] && [[ "$file_content" != "PENDING" ]]; then
                    local current_line_count=$(echo "$file_content" | wc -l)

                    # Display new progress messages since last check
                    if [[ $current_line_count -gt $last_line_count ]]; then
                        local new_lines=$(echo "$file_content" | tail -n $((current_line_count - last_line_count)))
                        while IFS= read -r line; do
                            if [[ "$line" == PROGRESS:* ]]; then
                                local progress_msg="${line#PROGRESS:}"
                                display "   ✓ ${progress_msg}"
                                log "Phase 4 progress: $progress_msg"
                                phase4_progress_shown=true
                            fi
                        done <<< "$new_lines"
                        last_line_count=$current_line_count
                    fi
                fi

                # Check if Phase 4 is complete
                case "$status" in
                    SUCCESS)
                        cleanup_status_line
                        log "Phase 4 completed successfully"
                        phase4_progress_shown=true
                        break
                        ;;
                    ERROR)
                        cleanup_status_line
                        error_exit "Service configuration failed"
                        ;;
                esac

                seconds_since_check=0
            fi

            # Update spinner every second (only in quiet mode)
            if [[ "$QUIET_MODE" == true ]]; then
                local spinner_char="${spinner_chars[$spinner_index]}"
                update_status_line "$spinner_char"
                spinner_index=$(( (spinner_index + 1) % ${#spinner_chars[@]} ))
            fi

            # Sleep and increment counters
            sleep 1
            elapsed=$((elapsed + 1))
            seconds_since_check=$((seconds_since_check + 1))

            # Log progress periodically
            if [[ $((elapsed % 30)) -eq 0 ]]; then
                log "Still waiting for progress (${elapsed}s elapsed)"
            fi
        done

        # Clear status line if we exited the loop
        cleanup_status_line

        if [[ $elapsed -ge $phase4_timeout ]]; then
            error_exit "Service configuration timeout after ${phase4_timeout} seconds"
        fi
    else
        display "⚠️  Cannot monitor progress - VM not accessible yet"
        display "   Proceeding to verification phase..."
    fi

    display ""

    # Verify installation
    export PHASE4_PROGRESS_SHOWN="$phase4_progress_shown"
    log "Starting installation verification"

    if [[ ! -f "${SCRIPT_DIR}/verify-install.sh" ]]; then
        error_exit "verify-install.sh not found"
    fi

    if ! bash "${SCRIPT_DIR}/verify-install.sh" 2>>"$LOG_FILE"; then
        error_exit "Installation verification failed"
    fi

    cleanup_status_line
    display ""

    # Final summary
    display "======================================"
    display "   Installation Complete!"
    display "======================================"
    display ""
    display "VM Details:"
    display "  VM ID: $VMID"
    display "  IP Address: $STATIC_IP"
    display "  Username: ${VM_USERNAME:-debian}"
    display ""
    display "Access Credentials:"
    display "  SSH: ssh ${VM_USERNAME:-debian}@$STATIC_IP"
    display "  Password: $ADMIN_PASSWORD"
    display ""
    display "Service Access:"
    display "  Dashboard:   https://privatebox.lan"
    display "  AdGuard:     https://adguard.lan"
    display "  OPNsense:    https://opnsense.lan  (root / opnsense)"
    display "  Portainer:   https://portainer.lan  (admin / $SERVICES_PASSWORD)"
    display "  Semaphore:   https://semaphore.lan  (admin / $SERVICES_PASSWORD)"
    display "  Proxmox:     https://proxmox.lan"
    display ""
    display "Note: Services use .lan domains with self-signed certificates"
    display "      Accept security warnings on first visit"
    display "      Configure your DNS to point to AdGuard at $STATIC_IP"
    display ""
    display "Logs saved to: $LOG_FILE"

    log "Bootstrap completed successfully"

    # Clean up config file (contains passwords)
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Removing temporary config file"
        rm -f "$CONFIG_FILE"
    fi
}

# Run main function
main "$@"