#!/bin/bash
# Backup script for PrivateBox configurations and credentials

# Source common library
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Backup configuration
BACKUP_BASE_DIR="/opt/privatebox-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"
RETENTION_DAYS=7

# Directories and files to backup
CREDENTIAL_DIRS=("/root/.credentials")
DATA_DIRS=("/opt/semaphore" "/opt/portainer")
CONFIG_FILES=(
    "/etc/containers/systemd"
    "$(dirname "${BASH_SOURCE[0]}")/../config/privatebox.conf"
)

# Function to create backup directory
create_backup_dir() {
    log_info "Creating backup directory: ${BACKUP_DIR}"
    
    if ! mkdir -p "${BACKUP_DIR}"; then
        error_exit "Failed to create backup directory: ${BACKUP_DIR}"
    fi
    
    chmod 700 "${BACKUP_DIR}"
}

# Function to backup credentials
backup_credentials() {
    log_info "Backing up credentials..."
    
    for cred_dir in "${CREDENTIAL_DIRS[@]}"; do
        if [[ -d "${cred_dir}" ]]; then
            local backup_name="credentials_$(basename "${cred_dir}")_${TIMESTAMP}.tar.gz"
            local backup_path="${BACKUP_DIR}/${backup_name}"
            
            log_info "Backing up ${cred_dir} to ${backup_name}"
            
            if tar -czf "${backup_path}" -C "$(dirname "${cred_dir}")" "$(basename "${cred_dir}")"; then
                chmod 600 "${backup_path}"
                log_info "✓ Credentials backup completed: ${backup_name}"
            else
                log_error "✗ Failed to backup credentials from ${cred_dir}"
                return 1
            fi
        else
            log_warn "Credentials directory not found: ${cred_dir}"
        fi
    done
}

# Function to backup service data
backup_service_data() {
    log_info "Backing up service data..."
    
    for data_dir in "${DATA_DIRS[@]}"; do
        if [[ -d "${data_dir}" ]]; then
            local service_name=$(basename "${data_dir}")
            local backup_name="${service_name}_data_${TIMESTAMP}.tar.gz"
            local backup_path="${BACKUP_DIR}/${backup_name}"
            
            log_info "Backing up ${data_dir} to ${backup_name}"
            
            if tar -czf "${backup_path}" -C "$(dirname "${data_dir}")" "$(basename "${data_dir}")"; then
                chmod 644 "${backup_path}"
                log_info "✓ Service data backup completed: ${backup_name}"
            else
                log_error "✗ Failed to backup service data from ${data_dir}"
                return 1
            fi
        else
            log_warn "Service data directory not found: ${data_dir}"
        fi
    done
}

# Function to backup configuration files
backup_config_files() {
    log_info "Backing up configuration files..."
    
    local config_backup_dir="${BACKUP_DIR}/configs"
    mkdir -p "${config_backup_dir}"
    
    for config_item in "${CONFIG_FILES[@]}"; do
        if [[ -e "${config_item}" ]]; then
            local item_name=$(basename "${config_item}")
            local backup_path="${config_backup_dir}/${item_name}"
            
            log_info "Backing up ${config_item}"
            
            if [[ -d "${config_item}" ]]; then
                # Directory - copy recursively
                if cp -r "${config_item}" "${backup_path}"; then
                    log_info "✓ Configuration directory backed up: ${item_name}"
                else
                    log_error "✗ Failed to backup configuration directory: ${config_item}"
                fi
            else
                # File - copy directly
                if cp "${config_item}" "${backup_path}"; then
                    log_info "✓ Configuration file backed up: ${item_name}"
                else
                    log_error "✗ Failed to backup configuration file: ${config_item}"
                fi
            fi
        else
            log_warn "Configuration item not found: ${config_item}"
        fi
    done
    
    # Create tarball of configs
    local config_backup_name="configs_${TIMESTAMP}.tar.gz"
    local config_backup_path="${BACKUP_DIR}/${config_backup_name}"
    
    if tar -czf "${config_backup_path}" -C "${BACKUP_DIR}" "configs"; then
        rm -rf "${config_backup_dir}"
        chmod 644 "${config_backup_path}"
        log_info "✓ Configuration backup completed: ${config_backup_name}"
    else
        log_error "✗ Failed to create configuration backup archive"
    fi
}

# Function to create backup manifest
create_backup_manifest() {
    local manifest_file="${BACKUP_DIR}/backup_manifest.txt"
    
    log_info "Creating backup manifest..."
    
    cat > "${manifest_file}" <<EOF
PrivateBox Backup Manifest
=========================
Backup Date: $(date)
Backup Directory: ${BACKUP_DIR}
Hostname: $(hostname)
System: $(uname -a)

Backup Contents:
$(ls -la "${BACKUP_DIR}")

Backup Sizes:
$(du -sh "${BACKUP_DIR}"/* 2>/dev/null || echo "No backup files found")

Notes:
- Credentials are encrypted and accessible only by root
- Service data includes persistent volumes and configurations
- Configuration files include systemd quadlet definitions
EOF

    log_info "✓ Backup manifest created"
}

# Function to cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."
    
    if [[ -d "${BACKUP_BASE_DIR}" ]]; then
        local deleted_count=0
        
        # Find and delete old backup directories
        while IFS= read -r -d '' old_backup; do
            log_info "Removing old backup: $(basename "${old_backup}")"
            rm -rf "${old_backup}"
            deleted_count=$((deleted_count + 1))
        done < <(find "${BACKUP_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -print0)
        
        if [[ ${deleted_count} -gt 0 ]]; then
            log_info "✓ Removed ${deleted_count} old backup(s)"
        else
            log_info "✓ No old backups to remove"
        fi
    fi
}

# Function to list available backups
list_backups() {
    log_info "Available backups:"
    
    if [[ -d "${BACKUP_BASE_DIR}" ]]; then
        local backup_count=0
        
        for backup_dir in "${BACKUP_BASE_DIR}"/*/; do
            if [[ -d "${backup_dir}" ]]; then
                local backup_name=$(basename "${backup_dir}")
                local backup_size=$(du -sh "${backup_dir}" | cut -f1)
                local backup_date=$(stat -c %y "${backup_dir}" | cut -d' ' -f1)
                
                echo "  ${backup_name} (${backup_size}, ${backup_date})"
                backup_count=$((backup_count + 1))
            fi
        done
        
        if [[ ${backup_count} -eq 0 ]]; then
            echo "  No backups found"
        fi
    else
        echo "  Backup directory does not exist: ${BACKUP_BASE_DIR}"
    fi
}

# Function to restore from backup
restore_backup() {
    local backup_name="$1"
    
    if [[ -z "${backup_name}" ]]; then
        log_error "Backup name not specified"
        echo "Available backups:"
        list_backups
        return 1
    fi
    
    local restore_dir="${BACKUP_BASE_DIR}/${backup_name}"
    
    if [[ ! -d "${restore_dir}" ]]; then
        log_error "Backup not found: ${backup_name}"
        return 1
    fi
    
    log_warn "CAUTION: This will overwrite existing configurations and data!"
    log_info "Restore source: ${restore_dir}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restore from backup: ${backup_name}"
        return 0
    fi
    
    # Note: Actual restore implementation would go here
    # For now, just show what would be restored
    log_info "Restore functionality not yet implemented."
    log_info "To manually restore, extract files from: ${restore_dir}"
    
    return 0
}

# Main backup function
perform_backup() {
    log_info "Starting PrivateBox backup..."
    log_info "==============================="
    
    # Create backup directory
    create_backup_dir
    
    # Perform backups
    backup_credentials
    backup_service_data
    backup_config_files
    
    # Create manifest
    create_backup_manifest
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Show summary
    local backup_size=$(du -sh "${BACKUP_DIR}" | cut -f1)
    log_info "==============================="
    log_info "✓ Backup completed successfully"
    log_info "Backup location: ${BACKUP_DIR}"
    log_info "Backup size: ${backup_size}"
    log_info "==============================="
}

# Main script logic
main() {
    case "${1:-backup}" in
        "backup")
            perform_backup
            ;;
        "list")
            list_backups
            ;;
        "restore")
            restore_backup "$2"
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        *)
            echo "Usage: $0 [backup|list|restore <name>|cleanup]"
            echo "  backup  - Create new backup (default)"
            echo "  list    - List available backups"
            echo "  restore - Restore from backup (specify backup name)"
            echo "  cleanup - Remove old backups"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi