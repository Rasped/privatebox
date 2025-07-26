#!/usr/bin/env python3
"""
OPNsense Console Configuration Script
Configures OPNsense via Proxmox console using qm sendkey commands
"""

import sys
import time
import subprocess
import argparse
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def send_key(vm_id, key):
    """Send a key to the VM console"""
    cmd = ['qm', 'sendkey', str(vm_id), key]
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        time.sleep(0.1)  # Small delay between keys
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to send key {key}: {e}")
        raise

def send_string(vm_id, text):
    """Send a string character by character"""
    for char in text:
        if char == '.':
            send_key(vm_id, 'dot')
        elif char == ' ':
            send_key(vm_id, 'spc')
        elif char == '-':
            send_key(vm_id, 'minus')
        elif char == '_':
            send_key(vm_id, 'shift-minus')
        elif char == '!':
            send_key(vm_id, 'shift-1')
        elif char == '@':
            send_key(vm_id, 'shift-2')
        elif char == '#':
            send_key(vm_id, 'shift-3')
        elif char == '$':
            send_key(vm_id, 'shift-4')
        elif char.isdigit():
            send_key(vm_id, char)
        elif char.isalpha():
            if char.isupper():
                send_key(vm_id, f'shift-{char.lower()}')
            else:
                send_key(vm_id, char)
        else:
            logger.warning(f"Skipping unsupported character: {char}")

def wait_with_message(seconds, message):
    """Wait with progress message"""
    logger.info(f"{message} (waiting {seconds} seconds)")
    time.sleep(seconds)

def configure_opnsense(vm_id, lan_ip, netmask, gateway, root_password=None):
    """Configure OPNsense via console"""
    
    logger.info(f"Starting OPNsense configuration for VM {vm_id}")
    logger.info(f"Target configuration: IP={lan_ip}/{netmask}, Gateway={gateway}")
    
    # Wait for boot
    wait_with_message(60, "Waiting for OPNsense to boot")
    
    # Send Enter to get login prompt
    logger.info("Getting login prompt...")
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Login as root
    logger.info("Logging in as root...")
    send_string(vm_id, 'root')
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Send default password
    logger.info("Entering default password...")
    send_string(vm_id, 'opnsense')
    send_key(vm_id, 'ret')
    wait_with_message(5, "Waiting for console menu")
    
    # Select option 2 (Set interface IP)
    logger.info("Selecting interface configuration...")
    send_key(vm_id, '2')
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Select interface 1 (LAN)
    logger.info("Selecting LAN interface...")
    send_key(vm_id, '1')
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # No DHCP
    logger.info("Disabling DHCP client...")
    send_key(vm_id, 'n')
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Enter IP address
    logger.info(f"Setting IP address to {lan_ip}...")
    send_string(vm_id, lan_ip)
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Enter subnet mask
    logger.info(f"Setting subnet mask to {netmask}...")
    send_string(vm_id, str(netmask))
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Enter gateway
    logger.info(f"Setting gateway to {gateway}...")
    send_string(vm_id, gateway)
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Skip IPv6
    logger.info("Skipping IPv6 configuration...")
    send_key(vm_id, 'n')
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # No DHCP server
    logger.info("Disabling DHCP server...")
    send_key(vm_id, 'n')
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Keep HTTPS
    logger.info("Keeping HTTPS for web interface...")
    send_key(vm_id, 'n')
    send_key(vm_id, 'ret')
    time.sleep(2)
    
    # Press enter to continue
    logger.info("Applying configuration...")
    send_key(vm_id, 'ret')
    wait_with_message(10, "Waiting for configuration to apply")
    
    # If root password provided, change it
    if root_password:
        logger.info("Changing root password...")
        # Select option 3 (Reset root password)
        send_key(vm_id, '3')
        send_key(vm_id, 'ret')
        time.sleep(2)
        
        # Enter new password twice
        send_string(vm_id, root_password)
        send_key(vm_id, 'ret')
        time.sleep(1)
        send_string(vm_id, root_password)
        send_key(vm_id, 'ret')
        wait_with_message(3, "Password change completed")
    
    logger.info("="*50)
    logger.info("OPNsense configuration completed!")
    logger.info(f"IP Address: {lan_ip}/{netmask}")
    logger.info(f"Gateway: {gateway}")
    logger.info(f"Web UI: https://{lan_ip}")
    logger.info("Default credentials: root / opnsense (unless changed)")
    logger.info("="*50)

def main():
    parser = argparse.ArgumentParser(description='Configure OPNsense via console')
    parser.add_argument('vm_id', type=int, help='Proxmox VM ID')
    parser.add_argument('lan_ip', help='LAN IP address')
    parser.add_argument('netmask', type=int, help='Subnet mask (e.g., 24)')
    parser.add_argument('gateway', help='Gateway IP address')
    parser.add_argument('--root-password', help='New root password (optional)')
    
    args = parser.parse_args()
    
    try:
        configure_opnsense(
            args.vm_id,
            args.lan_ip,
            args.netmask,
            args.gateway,
            args.root_password
        )
        return 0
    except Exception as e:
        logger.error(f"Configuration failed: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())