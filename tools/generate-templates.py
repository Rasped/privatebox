#!/usr/bin/env python3
"""
Semaphore template generation script.
This will eventually parse Ansible playbooks and create Semaphore templates.
"""
import os
import sys
import json
from pathlib import Path

# Auto-install dependencies if not available
try:
    import requests
except ImportError:
    import subprocess
    print("Installing requests package...")
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'requests'])
    import requests

try:
    import yaml
except ImportError:
    import subprocess
    print("Installing PyYAML package...")
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'PyYAML'])
    import yaml


def test_connectivity(base_url):
    """Test basic connectivity to Semaphore API."""
    print("\n=== Stage 1: Testing Basic Connectivity ===")
    try:
        response = requests.get(f"{base_url}/api/ping", timeout=5)
        if response.status_code == 200:
            print(f"✓ Successfully connected to Semaphore at {base_url}")
            print(f"  Response: {response.text.strip()}")
            return True
        else:
            print(f"✗ Unexpected response from /api/ping: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"✗ Failed to connect to {base_url}")
        print(f"  Error: {e}")
        return False


def test_authentication(base_url, api_token):
    """Test API authentication using Bearer token."""
    print("\n=== Stage 2: Testing Authentication ===")
    headers = {"Authorization": f"Bearer {api_token}"}
    
    try:
        response = requests.get(f"{base_url}/api/user", headers=headers, timeout=5)
        if response.status_code == 200:
            user_data = response.json()
            print("✓ Authentication successful!")
            print(f"  Logged in as: {user_data.get('username', 'Unknown')}")
            print(f"  User ID: {user_data.get('id', 'Unknown')}")
            print(f"  Admin: {user_data.get('admin', False)}")
            return True
        elif response.status_code == 401:
            print("✗ Authentication failed: Invalid API token")
            return False
        else:
            print(f"✗ Unexpected response: {response.status_code}")
            print(f"  Response: {response.text}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"✗ Failed to make authenticated request")
        print(f"  Error: {e}")
        return False


def list_projects(base_url, api_token):
    """List available projects to verify API access."""
    print("\n=== Stage 3: Listing Projects ===")
    headers = {"Authorization": f"Bearer {api_token}"}
    
    try:
        response = requests.get(f"{base_url}/api/projects", headers=headers, timeout=5)
        if response.status_code == 200:
            projects = response.json()
            print(f"✓ Found {len(projects)} project(s):")
            for project in projects:
                print(f"  - Project ID {project.get('id')}: {project.get('name', 'Unnamed')}")
            return True
        else:
            print(f"✗ Failed to list projects: {response.status_code}")
            print(f"  Response: {response.text}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"✗ Failed to list projects")
        print(f"  Error: {e}")
        return False


def discover_playbooks(base_dir):
    """Discover all playbook files in the services directory."""
    playbook_dir = Path(base_dir) / 'ansible' / 'playbooks' / 'services'
    if not playbook_dir.exists():
        print(f"✗ Playbook directory not found: {playbook_dir}")
        return []
    
    playbooks = list(playbook_dir.glob('*.yml'))
    # Exclude template files
    playbooks = [p for p in playbooks if not p.name.startswith('_')]
    return sorted(playbooks)


def parse_playbook(playbook_path):
    """Parse a playbook and extract vars_prompt with semaphore metadata."""
    try:
        with open(playbook_path, 'r') as f:
            data = yaml.safe_load(f)
        
        if not data or not isinstance(data, list):
            return None
        
        # Get the first play
        play = data[0]
        if not isinstance(play, dict):
            return None
        
        vars_prompt = play.get('vars_prompt', [])
        if not vars_prompt:
            return None
        
        # Extract variables with semaphore metadata
        semaphore_vars = []
        for var in vars_prompt:
            # Check if this variable has any semaphore_* fields
            has_semaphore_metadata = any(key.startswith('semaphore_') for key in var.keys())
            if has_semaphore_metadata:
                semaphore_vars.append(var)
        
        if not semaphore_vars:
            return None
        
        return {
            'name': play.get('name', 'Unnamed playbook'),
            'vars': semaphore_vars
        }
    
    except Exception as e:
        print(f"✗ Error parsing {playbook_path}: {e}")
        return None


def display_playbook_info(playbook_path, info):
    """Display parsed playbook information."""
    print(f"\n📄 {playbook_path.name}")
    print(f"   Name: {info['name']}")
    print(f"   Variables with Semaphore metadata:")
    
    for var in info['vars']:
        var_name = var.get('name', 'unnamed')
        var_type = var.get('semaphore_type', 'text')
        description = var.get('semaphore_description', var.get('prompt', ''))
        required = var.get('semaphore_required', not var.get('private', True))
        
        print(f"\n   - Variable: {var_name}")
        print(f"     Type: {var_type}")
        print(f"     Description: {description}")
        print(f"     Required: {required}")
        
        # Show additional fields for specific types
        if var_type == 'integer':
            if 'semaphore_min' in var:
                print(f"     Min: {var['semaphore_min']}")
            if 'semaphore_max' in var:
                print(f"     Max: {var['semaphore_max']}")


def main():
    print("=== Semaphore Template Generator ===")
    print(f"Python version: {sys.version.split()[0]}")
    print(f"Current working directory: {os.getcwd()}")
    
    # Parse command line arguments for Semaphore variables
    # Semaphore passes variables as KEY=VALUE arguments
    variables = {}
    for arg in sys.argv[1:]:
        if '=' in arg:
            key, value = arg.split('=', 1)
            variables[key] = value
    
    # Get required variables from parsed arguments
    semaphore_url = variables.get('SEMAPHORE_URL')
    api_token = variables.get('SEMAPHORE_API_TOKEN')
    
    print("\n=== Environment Check ===")
    if not semaphore_url:
        print("✗ Missing SEMAPHORE_URL environment variable")
        print("  This should be set in the Variable attached to this task")
        sys.exit(1)
    else:
        print(f"✓ SEMAPHORE_URL: {semaphore_url}")
    
    if not api_token:
        print("✗ Missing SEMAPHORE_API_TOKEN environment variable")
        print("  This should be set in the Secret attached to this task")
        sys.exit(1)
    else:
        print(f"✓ SEMAPHORE_API_TOKEN: {'*' * 10}... (hidden)")
    
    # Run connectivity tests
    if not test_connectivity(semaphore_url):
        print("\n❌ Connectivity test failed. Exiting.")
        sys.exit(1)
    
    if not test_authentication(semaphore_url, api_token):
        print("\n❌ Authentication test failed. Exiting.")
        sys.exit(1)
    
    if not list_projects(semaphore_url, api_token):
        print("\n❌ Project listing failed. Exiting.")
        sys.exit(1)
    
    print("\n✅ All API tests passed! Ready for template synchronization.")
    
    # Phase 4: Discover and parse playbooks
    print("\n=== Phase 4: Discovering Playbooks ===")
    playbooks = discover_playbooks(os.getcwd())
    
    if not playbooks:
        print("✗ No playbooks found in ansible/playbooks/services/")
        return
    
    print(f"✓ Found {len(playbooks)} playbook(s)")
    
    # Parse each playbook
    print("\n=== Parsing Playbooks for Semaphore Metadata ===")
    templates_found = 0
    
    for playbook in playbooks:
        info = parse_playbook(playbook)
        if info:
            templates_found += 1
            display_playbook_info(playbook, info)
    
    if templates_found == 0:
        print("\n⚠️  No playbooks with semaphore_* metadata found.")
        print("To enable template generation, add semaphore_* fields to vars_prompt in your playbooks.")
    else:
        print(f"\n✓ Found {templates_found} playbook(s) with Semaphore metadata")
        print("\nNext steps (Phase 5):")
        print("  - Create Semaphore templates via API")
        print("  - Update existing templates if they already exist")


if __name__ == "__main__":
    main()