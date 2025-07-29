#!/bin/bash
# Quick OPNsense deployment script
# Usage: ./deploy-opnsense.sh [vm_id] [vm_name]

VM_ID=${1:-100}
VM_NAME=${2:-opnsense-prod}
TEMPLATE_URL=${OPNSENSE_TEMPLATE_URL:-http://192.168.1.17/templates/opnsense-template.qcow2}

echo "Deploying OPNsense VM..."
echo "  VM ID: $VM_ID"
echo "  VM Name: $VM_NAME"
echo "  Template URL: $TEMPLATE_URL"
echo ""

ansible-playbook \
  -i inventories/development/hosts.yml \
  playbooks/services/deploy-opnsense-from-template.yml \
  -e "vm_id=$VM_ID" \
  -e "vm_name=$VM_NAME" \
  -e "template_url=$TEMPLATE_URL" \
  -e "start_vm=true"