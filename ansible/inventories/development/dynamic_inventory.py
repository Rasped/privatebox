#!/usr/bin/env python3
"""
Dynamic inventory script for Proxmox VE
Discovers VMs and containers from Proxmox API and groups them appropriately
"""

import json
import os
import sys
import urllib3
from proxmoxer import ProxmoxAPI
from collections import defaultdict

# Disable SSL warnings if needed
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class ProxmoxInventory:
    def __init__(self):
        """Initialize the inventory with Proxmox connection details"""
        # Get configuration from environment variables
        self.proxmox_host = os.environ.get('PROXMOX_API_HOST', '10.0.0.10')
        self.proxmox_user = os.environ.get('PROXMOX_API_USER', 'ansible@pam')
        self.proxmox_password = os.environ.get('PROXMOX_API_PASSWORD', '')
        self.proxmox_token_name = os.environ.get('PROXMOX_TOKEN_NAME', '')
        self.proxmox_token_value = os.environ.get('PROXMOX_TOKEN_VALUE', '')
        self.verify_ssl = os.environ.get('PROXMOX_VERIFY_SSL', 'false').lower() == 'true'
        
        # Initialize inventory structure
        self.inventory = {
            '_meta': {
                'hostvars': {}
            },
            'all': {
                'children': ['proxmox_hosts', 'vms', 'containers']
            },
            'proxmox_hosts': {
                'hosts': []
            },
            'vms': {
                'hosts': [],
                'children': ['opnsense_vms', 'ubuntu_vms']
            },
            'containers': {
                'hosts': [],
                'children': ['ubuntu_containers', 'service_containers']
            },
            'opnsense_vms': {
                'hosts': []
            },
            'ubuntu_vms': {
                'hosts': []
            },
            'ubuntu_containers': {
                'hosts': []
            },
            'service_containers': {
                'hosts': []
            },
            'ubuntu_servers': {
                'hosts': [],
                'children': ['ubuntu_vms', 'ubuntu_containers']
            }
        }
        
        # Service-specific groups
        self.service_groups = {
            'adguard_servers': [],
            'unbound_servers': [],
            'portainer_servers': [],
            'semaphore_servers': [],
            'monitoring_servers': []
        }

    def connect_proxmox(self):
        """Connect to Proxmox API"""
        try:
            if self.proxmox_token_name and self.proxmox_token_value:
                # Use API token authentication
                proxmox = ProxmoxAPI(
                    self.proxmox_host,
                    user=self.proxmox_user,
                    token_name=self.proxmox_token_name,
                    token_value=self.proxmox_token_value,
                    verify_ssl=self.verify_ssl
                )
            else:
                # Use password authentication
                proxmox = ProxmoxAPI(
                    self.proxmox_host,
                    user=self.proxmox_user,
                    password=self.proxmox_password,
                    verify_ssl=self.verify_ssl
                )
            return proxmox
        except Exception as e:
            print(f"Error connecting to Proxmox: {e}", file=sys.stderr)
            return None

    def get_vm_network_info(self, node, vmid, vm_type='qemu'):
        """Get network information for a VM or container"""
        try:
            if vm_type == 'qemu':
                config = self.proxmox.nodes(node).qemu(vmid).config.get()
            else:
                config = self.proxmox.nodes(node).lxc(vmid).config.get()
            
            # Extract network interfaces
            networks = {}
            for key, value in config.items():
                if key.startswith('net'):
                    networks[key] = value
            
            return networks
        except:
            return {}

    def get_vm_ip_address(self, node, vmid, vm_type='qemu'):
        """Try to get the IP address of a VM or container"""
        try:
            if vm_type == 'qemu':
                # For VMs, try to get agent info
                try:
                    agent_info = self.proxmox.nodes(node).qemu(vmid).agent('network-get-interfaces').get()
                    for iface in agent_info.get('result', []):
                        if iface.get('name') != 'lo':
                            for addr in iface.get('ip-addresses', []):
                                if addr.get('ip-address-type') == 'ipv4':
                                    return addr.get('ip-address')
                except:
                    pass
            else:
                # For containers, check the config
                config = self.proxmox.nodes(node).lxc(vmid).config.get()
                for key, value in config.items():
                    if key.startswith('net') and 'ip=' in value:
                        # Extract IP from format: ip=10.0.20.101/24
                        ip_part = [p for p in value.split(',') if p.strip().startswith('ip=')]
                        if ip_part:
                            ip = ip_part[0].split('=')[1].split('/')[0]
                            return ip
        except:
            pass
        return None

    def categorize_host(self, hostname, description, tags):
        """Categorize a host based on its name, description, and tags"""
        hostname_lower = hostname.lower()
        description_lower = description.lower() if description else ''
        tags_lower = [tag.lower() for tag in tags] if tags else []
        
        # Check for OPNSense
        if 'opnsense' in hostname_lower or 'opnsense' in description_lower or 'firewall' in tags_lower:
            return 'opnsense_vms'
        
        # Check for specific services
        if 'adguard' in hostname_lower or 'adguard' in tags_lower:
            self.service_groups['adguard_servers'].append(hostname)
        elif 'unbound' in hostname_lower or 'unbound' in tags_lower:
            self.service_groups['unbound_servers'].append(hostname)
        elif 'portainer' in hostname_lower or 'portainer' in tags_lower:
            self.service_groups['portainer_servers'].append(hostname)
        elif 'semaphore' in hostname_lower or 'semaphore' in tags_lower:
            self.service_groups['semaphore_servers'].append(hostname)
        elif 'prometheus' in hostname_lower or 'grafana' in hostname_lower or 'monitoring' in tags_lower:
            self.service_groups['monitoring_servers'].append(hostname)
        
        # Default to ubuntu for other systems
        return None

    def discover_inventory(self):
        """Discover all VMs and containers from Proxmox"""
        self.proxmox = self.connect_proxmox()
        if not self.proxmox:
            return
        
        try:
            # Get all nodes
            nodes = self.proxmox.nodes.get()
            
            for node in nodes:
                node_name = node['node']
                
                # Add Proxmox host itself
                self.inventory['proxmox_hosts']['hosts'].append(node_name)
                self.inventory['_meta']['hostvars'][node_name] = {
                    'ansible_host': node.get('ip', self.proxmox_host),
                    'node_type': 'proxmox',
                    'proxmox_node': node_name
                }
                
                # Get all VMs
                vms = self.proxmox.nodes(node_name).qemu.get()
                for vm in vms:
                    if vm.get('template', 0) == 1:
                        continue  # Skip templates
                    
                    vmid = vm['vmid']
                    name = vm.get('name', f'vm-{vmid}')
                    status = vm.get('status', 'unknown')
                    description = vm.get('description', '')
                    tags = vm.get('tags', '').split(',') if vm.get('tags') else []
                    
                    # Get IP address
                    ip_address = self.get_vm_ip_address(node_name, vmid, 'qemu')
                    
                    # Add to VMs group
                    self.inventory['vms']['hosts'].append(name)
                    
                    # Categorize the VM
                    category = self.categorize_host(name, description, tags)
                    if category:
                        self.inventory[category]['hosts'].append(name)
                    else:
                        self.inventory['ubuntu_vms']['hosts'].append(name)
                    
                    # Add host variables
                    self.inventory['_meta']['hostvars'][name] = {
                        'ansible_host': ip_address or name,
                        'proxmox_vmid': vmid,
                        'proxmox_node': node_name,
                        'proxmox_type': 'qemu',
                        'proxmox_status': status,
                        'proxmox_description': description,
                        'proxmox_tags': tags
                    }
                
                # Get all containers
                containers = self.proxmox.nodes(node_name).lxc.get()
                for ct in containers:
                    if ct.get('template', 0) == 1:
                        continue  # Skip templates
                    
                    vmid = ct['vmid']
                    name = ct.get('name', f'ct-{vmid}')
                    status = ct.get('status', 'unknown')
                    description = ct.get('description', '')
                    tags = ct.get('tags', '').split(',') if ct.get('tags') else []
                    
                    # Get IP address
                    ip_address = self.get_vm_ip_address(node_name, vmid, 'lxc')
                    
                    # Add to containers group
                    self.inventory['containers']['hosts'].append(name)
                    
                    # Categorize the container
                    category = self.categorize_host(name, description, tags)
                    if category and category != 'opnsense_vms':  # OPNSense shouldn't be in a container
                        self.inventory['service_containers']['hosts'].append(name)
                    else:
                        self.inventory['ubuntu_containers']['hosts'].append(name)
                    
                    # Add host variables
                    self.inventory['_meta']['hostvars'][name] = {
                        'ansible_host': ip_address or name,
                        'proxmox_vmid': vmid,
                        'proxmox_node': node_name,
                        'proxmox_type': 'lxc',
                        'proxmox_status': status,
                        'proxmox_description': description,
                        'proxmox_tags': tags
                    }
            
            # Add service groups to inventory
            for group_name, hosts in self.service_groups.items():
                if hosts:
                    self.inventory[group_name] = {'hosts': hosts}
            
        except Exception as e:
            print(f"Error discovering inventory: {e}", file=sys.stderr)

    def get_inventory(self):
        """Return the inventory in JSON format"""
        self.discover_inventory()
        return json.dumps(self.inventory, indent=2)


def main():
    """Main function"""
    # Check for arguments
    if len(sys.argv) > 1:
        if sys.argv[1] == '--list':
            inventory = ProxmoxInventory()
            print(inventory.get_inventory())
        elif sys.argv[1] == '--host':
            # Return empty host vars (already included in _meta)
            print(json.dumps({}))
        else:
            print("Usage: {} --list or {} --host <hostname>".format(sys.argv[0], sys.argv[0]))
            sys.exit(1)
    else:
        print("Usage: {} --list or {} --host <hostname>".format(sys.argv[0], sys.argv[0]))
        sys.exit(1)


if __name__ == '__main__':
    main()