#!/usr/bin/env python3
"""
OPNsense API Examples
Demonstrates common API operations for OPNsense management
"""

import requests
import json
import sys
import os
from requests.auth import HTTPBasicAuth
from urllib3.exceptions import InsecureRequestWarning

# Disable SSL warnings for self-signed certificates
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)


class OPNsenseAPI:
    """OPNsense API client class"""
    
    def __init__(self, host, api_key, api_secret, verify_ssl=False):
        """Initialize API client"""
        self.host = host
        self.api_key = api_key
        self.api_secret = api_secret
        self.verify_ssl = verify_ssl
        self.base_url = f"https://{host}/api"
        self.auth = HTTPBasicAuth(api_key, api_secret)
        
    def _request(self, method, endpoint, data=None):
        """Make API request"""
        url = f"{self.base_url}/{endpoint}"
        
        try:
            response = requests.request(
                method=method,
                url=url,
                auth=self.auth,
                verify=self.verify_ssl,
                json=data,
                timeout=30
            )
            response.raise_for_status()
            
            # Return JSON if available
            if response.content:
                try:
                    return response.json()
                except json.JSONDecodeError:
                    return response.text
            return None
            
        except requests.exceptions.RequestException as e:
            print(f"API Error: {e}")
            return None
    
    def get(self, endpoint):
        """GET request"""
        return self._request("GET", endpoint)
    
    def post(self, endpoint, data=None):
        """POST request"""
        return self._request("POST", endpoint, data)
    
    # System Information
    def get_system_status(self):
        """Get system status"""
        return self.get("core/system/status")
    
    def get_system_info(self):
        """Get system information"""
        return self.get("core/firmware/info")
    
    # Interface Management
    def get_interfaces(self):
        """Get all interfaces"""
        return self.get("interfaces/overview/get")
    
    def get_interface_stats(self):
        """Get interface statistics"""
        return self.get("interfaces/overview/getInterfaceStatistics")
    
    # Firewall Management
    def get_firewall_rules(self):
        """Get firewall rules"""
        return self.get("firewall/filter/searchRule")
    
    def add_firewall_rule(self, rule_data):
        """Add a firewall rule"""
        return self.post("firewall/filter/addRule", rule_data)
    
    def apply_firewall_changes(self):
        """Apply firewall changes"""
        return self.post("firewall/filter/apply")
    
    # DHCP Management
    def get_dhcp_leases(self):
        """Get DHCP leases"""
        return self.get("dhcpv4/leases/searchLease")
    
    def get_dhcp_settings(self):
        """Get DHCP settings"""
        return self.get("dhcpv4/settings/get")
    
    # DNS Management
    def get_unbound_status(self):
        """Get Unbound DNS status"""
        return self.get("unbound/service/status")
    
    def get_dns_settings(self):
        """Get DNS settings"""
        return self.get("unbound/settings/get")
    
    # Service Management
    def restart_service(self, service_name):
        """Restart a service"""
        return self.post(f"{service_name}/service/restart")
    
    def get_service_status(self, service_name):
        """Get service status"""
        return self.get(f"{service_name}/service/status")


def load_credentials():
    """Load API credentials from files"""
    try:
        with open('/etc/privatebox-opnsense-api-key', 'r') as f:
            api_key = f.read().strip()
        with open('/etc/privatebox-opnsense-api-secret', 'r') as f:
            api_secret = f.read().strip()
        return api_key, api_secret
    except FileNotFoundError:
        print("Error: API credential files not found")
        print("Please run opnsense-enable-api.yml first")
        return None, None


def main():
    """Main example function"""
    # Check command line arguments
    if len(sys.argv) < 2:
        print("Usage: opnsense-api-examples.py <opnsense-host>")
        sys.exit(1)
    
    host = sys.argv[1]
    
    # Load credentials
    api_key, api_secret = load_credentials()
    if not api_key or not api_secret:
        # Try environment variables as fallback
        api_key = os.environ.get('OPNSENSE_API_KEY')
        api_secret = os.environ.get('OPNSENSE_API_SECRET')
        
        if not api_key or not api_secret:
            print("Error: No API credentials available")
            sys.exit(1)
    
    # Initialize API client
    api = OPNsenseAPI(host, api_key, api_secret)
    
    print(f"Connecting to OPNsense at {host}...")
    print("=" * 50)
    
    # Example 1: System Status
    print("\n1. System Status:")
    status = api.get_system_status()
    if status:
        print(f"   Version: {status.get('version_data', {}).get('product_version', 'Unknown')}")
        print(f"   Uptime: {status.get('uptime', 'Unknown')}")
        print(f"   CPU Usage: {status.get('cpu', {}).get('used', 'Unknown')}%")
        print(f"   Memory Usage: {status.get('memory', {}).get('used_pct', 'Unknown')}%")
    
    # Example 2: Interface Information
    print("\n2. Network Interfaces:")
    interfaces = api.get_interfaces()
    if interfaces:
        for iface_name, iface_data in interfaces.items():
            if iface_data.get('enabled'):
                print(f"   {iface_name}: {iface_data.get('descr', '')} - {iface_data.get('ipaddr', 'No IP')}")
    
    # Example 3: DHCP Leases
    print("\n3. Active DHCP Leases:")
    leases = api.get_dhcp_leases()
    if leases and 'rows' in leases:
        for lease in leases['rows'][:5]:  # Show first 5
            print(f"   {lease.get('mac', 'Unknown')} -> {lease.get('address', 'Unknown')} ({lease.get('hostname', 'No hostname')})")
        if leases['rowCount'] > 5:
            print(f"   ... and {leases['rowCount'] - 5} more")
    
    # Example 4: Firewall Rules Count
    print("\n4. Firewall Rules:")
    rules = api.get_firewall_rules()
    if rules:
        print(f"   Total rules: {rules.get('rowCount', 0)}")
        enabled_count = sum(1 for rule in rules.get('rows', []) if rule.get('enabled') == '1')
        print(f"   Enabled rules: {enabled_count}")
    
    # Example 5: DNS Status
    print("\n5. DNS Resolver Status:")
    dns_status = api.get_unbound_status()
    if dns_status:
        print(f"   Status: {'Running' if dns_status.get('status') == 'running' else 'Stopped'}")
    
    print("\n" + "=" * 50)
    print("Examples completed successfully!")
    
    # Additional example: Create a port forward rule
    print("\nExample: Creating a port forward rule (commented out):")
    print("""
    # Port forward rule for web server
    rule_data = {
        'rule': {
            'enabled': '1',
            'action': 'pass',
            'quick': '1',
            'interface': 'wan',
            'direction': 'in',
            'ipprotocol': 'inet',
            'protocol': 'tcp',
            'source': {'any': '1'},
            'destination': {
                'port': '80',
                'address': 'wan_address'
            },
            'redirect': {
                'target': '10.0.0.100',
                'port': '80'
            },
            'descr': 'Web Server Port Forward'
        }
    }
    
    # Add the rule
    result = api.add_firewall_rule(rule_data)
    
    # Apply changes
    api.apply_firewall_changes()
    """)


if __name__ == "__main__":
    main()