#!/bin/bash
# PrivateBox Ansible Setup Script

set -e

echo "================================"
echo "PrivateBox Ansible Setup"
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script should not be run as root!${NC}"
   exit 1
fi

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check for required commands
check_requirements() {
    local requirements=("python3" "pip3" "git")
    
    for cmd in "${requirements[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    print_status "All requirements met"
}

# Install Ansible and required collections
install_ansible() {
    print_status "Installing Ansible..."
    pip3 install --user ansible ansible-lint
    
    print_status "Installing required Ansible collections..."
    ansible-galaxy collection install community.docker
    ansible-galaxy collection install community.general
    ansible-galaxy collection install community.mysql
    ansible-galaxy collection install community.postgresql
    ansible-galaxy collection install ansible.posix
}

# Setup vault file
setup_vault() {
    local vault_file="ansible/inventories/development/group_vars/all/vault.yml"
    
    if [[ ! -f "$vault_file" ]]; then
        print_status "Creating vault file from template..."
        cp "${vault_file}.example" "$vault_file"
        
        print_warning "Please edit $vault_file with your passwords"
        print_warning "Then encrypt it with: ansible-vault encrypt $vault_file"
    else
        print_status "Vault file already exists"
    fi
}

# Create SSH key for PrivateBox
setup_ssh_key() {
    local key_path="$HOME/.ssh/privatebox_development"
    
    if [[ ! -f "$key_path" ]]; then
        print_status "Generating SSH key for PrivateBox..."
        ssh-keygen -t ed25519 -f "$key_path" -C "privatebox@ansible" -N ""
        print_status "SSH key created at: $key_path"
        print_warning "Add the public key to your target hosts: $key_path.pub"
    else
        print_status "SSH key already exists"
    fi
}

# Create ansible.cfg
create_ansible_config() {
    if [[ ! -f "ansible.cfg" ]]; then
        print_status "Creating ansible.cfg..."
        cat > ansible.cfg << 'EOF'
[defaults]
host_key_checking = False
inventory = ansible/inventories/development/hosts.yml
roles_path = ansible/roles
collections_path = ~/.ansible/collections
remote_tmp = /tmp/.ansible-${USER}/tmp
local_tmp = /tmp/.ansible-${USER}/tmp
retry_files_enabled = False
stdout_callback = yaml
callback_whitelist = timer, profile_tasks
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible-facts
fact_caching_timeout = 86400

[inventory]
enable_plugins = yaml, ini, script

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = False

[ssh_connection]
ssh_args = -C -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
EOF
        print_status "ansible.cfg created"
    else
        print_status "ansible.cfg already exists"
    fi
}

# Update inventory with actual IPs
update_inventory() {
    print_warning "Please update ansible/inventories/development/hosts.yml with your actual host IPs"
    print_warning "Current inventory uses example IPs that need to be replaced"
}

# Main setup flow
main() {
    echo ""
    check_requirements
    echo ""
    
    install_ansible
    echo ""
    
    setup_vault
    echo ""
    
    setup_ssh_key
    echo ""
    
    create_ansible_config
    echo ""
    
    update_inventory
    echo ""
    
    print_status "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Update the inventory file with your actual host IPs"
    echo "2. Edit and encrypt the vault file"
    echo "3. Add your SSH public key to target hosts"
    echo "4. Run: ansible-playbook ansible/playbooks/site.yml --ask-vault-pass"
    echo ""
    echo "For a full deployment, run:"
    echo "   ansible-playbook ansible/playbooks/orchestration/full_deployment.yml --ask-vault-pass"
}

# Run main function
main "$@"