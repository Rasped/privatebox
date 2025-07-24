#!/bin/bash

# Test script for PrivateBox Ansible playbooks
# This script performs syntax checks on all the new playbooks

echo "Testing PrivateBox Ansible Playbooks"
echo "===================================="

# Change to ansible directory
cd /opt/privatebox/ansible || cd /Users/rasped/privatebox/ansible

# Test install-requirements.yml (runs on localhost)
echo ""
echo "1. Testing install-requirements.yml..."
ansible-playbook --syntax-check playbooks/services/install-requirements.yml
if [ $? -eq 0 ]; then
    echo "✓ Syntax check passed"
else
    echo "✗ Syntax check failed"
fi

# Test discover-environment.yml
echo ""
echo "2. Testing discover-environment.yml..."
ansible-playbook --syntax-check -i inventories/development/hosts.yml playbooks/services/discover-environment.yml
if [ $? -eq 0 ]; then
    echo "✓ Syntax check passed"
else
    echo "✗ Syntax check failed"
fi

# Test discover-network.yml
echo ""
echo "3. Testing discover-network.yml..."
ansible-playbook --syntax-check -i inventories/development/hosts.yml playbooks/services/discover-network.yml
if [ $? -eq 0 ]; then
    echo "✓ Syntax check passed"
else
    echo "✗ Syntax check failed"
fi

# Test opnsense-deploy.yml
echo ""
echo "4. Testing opnsense-deploy.yml..."
ansible-playbook --syntax-check -i inventories/development/hosts.yml playbooks/services/opnsense-deploy.yml
if [ $? -eq 0 ]; then
    echo "✓ Syntax check passed"
else
    echo "✗ Syntax check failed"
fi

echo ""
echo "===================================="
echo "Syntax checks complete!"
echo ""
echo "To run these playbooks:"
echo ""
echo "1. Install requirements (run first on management VM):"
echo "   ansible-playbook playbooks/services/install-requirements.yml"
echo ""
echo "2. Discover Proxmox environment:"
echo "   ansible-playbook -i inventories/development/hosts.yml playbooks/services/discover-environment.yml --ask-pass"
echo ""
echo "3. Discover network configuration:"
echo "   ansible-playbook -i inventories/development/hosts.yml playbooks/services/discover-network.yml"
echo ""
echo "4. Deploy OPNsense VM (after running steps 1-3):"
echo "   ansible-playbook -i inventories/development/hosts.yml playbooks/services/opnsense-deploy.yml --ask-pass"
echo ""
echo "Note: Use --ask-pass if SSH keys are not configured for the Proxmox host"
echo "Note: You may need to add -e 'proxmox_api_password=YOUR_PASSWORD' for VM operations"