# Changelog

Completed work history. Updated via `/track` command.
Format: `- YYYY-MM-DD: [Category] Description`
Newest entries at top. Archive old entries annually.

---

## 2025

### August

- 2025-08-02: [Fix] Fixed config-generator subshell issue - passwords now save correctly to config
- 2025-08-02: [Fix] Renamed config-manager.sh to config-generator.sh to avoid confusion with config_manager.sh
- 2025-08-02: [Fix] Fixed unbound SEMAPHORE_ADMIN_PASSWORD variable in create-ubuntu-vm.sh
- 2025-08-02: [Task] Completed config-based installation integration - all passwords flow correctly
- 2025-08-02: [Config] Removed unused automation user code from Semaphore setup
- 2025-08-02: [Config] Centralized all password generation in config-generator.sh
- 2025-08-02: [Fix] Removed password generation from common.sh - all passwords from config
- 2025-08-02: [Config] Removed network-discovery.sh in favor of config-generator.sh
- 2025-08-02: [Feature] Enhanced config-manager with full network detection capabilities
- 2025-08-02: [Fix] Updated VM creation to use ADMIN_PASSWORD from config
- 2025-08-02: [Config] SERVICES_PASSWORD now used for Semaphore admin user
- 2025-08-02: [Config] Integrated network-discovery.sh with config-generator.sh for unified configuration
- 2025-08-02: [Fix] Fixed config-generator.sh argument consumption issue when sourced by other scripts
- 2025-08-02: [Fix] Added STORAGE variable to config-manager for legacy compatibility
- 2025-08-02: [Fix] Fixed VM_PASSWORD display error in bootstrap.sh completion message
- 2025-08-02: [Feature] Replaced custom wordlist with EFF large wordlist (7,776 words) for better security
- 2025-08-02: [Feature] Implemented phonetic password generator with 350 5-letter words
- 2025-08-02: [Feature] Created config-generator.sh for config-based installation
- 2025-08-02: [Docs] Redesigned password management as config-based installation
- 2025-08-02: [Docs] Documented current password management state and target behavior
- 2025-08-02: [Feature] Created /track slash command for work tracking
- 2025-08-02: [Docs] Updated DEPLOYMENT-STATUS.md with v1 release requirements  
- 2025-08-02: [Config] Cleaned up old archive files and scripts
- 2025-08-02: [Config] Restored handovers folder while removing other archives
- 2025-08-01: [Fix] Updated DNS configuration to use correct Alpine VM IP
- 2025-08-01: [Fix] Ensured Caddy log files have correct permissions
- 2025-08-01: [Fix] Used Alpine's built-in caddy service instead of custom scripts
- 2025-08-01: [Fix] Simplified Caddy startup for 100% hands-off deployment

### July

- 2025-07-31: [Feature] Achieved 100% hands-off deployment
- 2025-07-31: [Feature] Implemented Alpine VM deployment with integrated Caddy
- 2025-07-31: [Feature] Created automated AdGuard deployment with API configuration
- 2025-07-31: [Feature] Implemented Semaphore template synchronization
- 2025-07-21: [Fix] Resolved all critical bootstrap issues
- 2025-07-21: [Feature] Implemented cloud-init for unattended VM setup
- 2025-07-21: [Feature] Created one-line quickstart installer