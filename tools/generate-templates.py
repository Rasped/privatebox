#!/usr/bin/env python3
"""
Semaphore template generation script.
This will eventually parse Ansible playbooks and create Semaphore templates.
"""
import os
import sys
import json

# Auto-install requests if not available
try:
    import requests
except ImportError:
    import subprocess
    print("Installing requests package...")
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'requests'])
    import requests


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


def main():
    print("=== Semaphore Template Generator ===")
    print(f"Python version: {sys.version.split()[0]}")
    print(f"Current working directory: {os.getcwd()}")
    
    # Debug: Show command line arguments
    print(f"\n=== Command Line Arguments ===")
    print(f"  sys.argv: {sys.argv}")
    
    # Debug: Show all environment variables
    print("\n=== All Environment Variables ===")
    for key, value in sorted(os.environ.items()):
        # Hide sensitive values
        if 'TOKEN' in key or 'PASSWORD' in key:
            print(f"  {key}: {'*' * 10}")
        else:
            print(f"  {key}: {value}")
    
    # Debug: Check for JSON files in working directory
    print("\n=== Files in Current Directory ===")
    try:
        files = os.listdir('.')
        for f in sorted(files):
            print(f"  {f}")
    except Exception as e:
        print(f"  Error listing files: {e}")
    
    # Check for required environment variables
    semaphore_url = os.environ.get('SEMAPHORE_URL')
    api_token = os.environ.get('SEMAPHORE_API_TOKEN')
    
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
    print("\nNext steps (Phase 4+):")
    print("  - Parse Ansible playbooks with semaphore_* metadata")
    print("  - Create/update Semaphore templates via API")


if __name__ == "__main__":
    main()