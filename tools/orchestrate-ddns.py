#!/usr/bin/env python3
"""
Semaphore DynDNS orchestration script.
Runs DynDNS configuration templates in the correct sequence.

Prerequisites:
- DynDNS 1: Setup Environment must be run first (creates privatebox-env-dns)
- User must have filled in DNS provider, API token, domain, and email
"""
import os
import sys
import json
import time
from pathlib import Path

# Auto-install dependencies if not available
try:
    import requests
    import urllib3
except ImportError:
    import subprocess
    print("Installing requests package...")
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'requests'])
    import requests
    import urllib3

# Disable SSL warnings for self-signed certificates (internal Services VLAN only)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class DynDNSOrchestrator:
    """Orchestrates DynDNS configuration template execution."""

    def __init__(self):
        """Initialize the orchestrator."""
        # Parse command line arguments for Semaphore variables
        # Semaphore passes variables as KEY=VALUE arguments
        variables = {}
        for arg in sys.argv[1:]:
            if '=' in arg:
                key, value = arg.split('=', 1)
                variables[key] = value

        # Get API token from parsed arguments (how Semaphore provides it)
        self.api_token = variables.get('SEMAPHORE_API_TOKEN')

        # Fall back to environment variable if not in arguments
        if not self.api_token:
            self.api_token = os.environ.get("SEMAPHORE_API_TOKEN")

        # Get Semaphore URL from arguments or use default
        # When running inside Semaphore container, need to use host IP not localhost
        self.base_url = variables.get('SEMAPHORE_URL', 'https://10.10.20.10:2443')
        self.project_id = 1
        self.headers = {"Authorization": f"Bearer {self.api_token}"}

        # Define the template sequence
        # Note: "DynDNS 1: Setup Environment" is excluded - user must run that first
        self.template_sequence = [
            "Generate Templates",  # Regenerate templates with new DNS environment
            "DynDNS 2a: Prepare Configuration",
            "DynDNS 2b: Configure OPNsense",
            "DynDNS 3: Configure AdGuard",
            "DynDNS 4: Cleanup DNS Records",
            "DynDNS 5: Configure Caddy",
            "DynDNS 6: Verify Complete Setup"
        ]

        if not self.api_token:
            print("✗ SEMAPHORE_API_TOKEN not found in arguments or environment")
            print("  Debug: Command line arguments:", sys.argv)
            print("  Debug: Parsed variables:", variables)
            sys.exit(1)

    def test_connectivity(self):
        """Test connection to Semaphore API."""
        print("\n=== Testing Semaphore API Connection ===")
        try:
            response = requests.get(f"{self.base_url}/api/ping", timeout=5, verify=False)
            if response.status_code == 200:
                print(f"✓ Connected to Semaphore at {self.base_url}")
                return True
            else:
                print(f"✗ Unexpected response: {response.status_code}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"✗ Failed to connect: {e}")
            return False

    def test_authentication(self):
        """Test API authentication."""
        print("\n=== Testing Authentication ===")
        try:
            response = requests.get(
                f"{self.base_url}/api/user",
                headers=self.headers,
                timeout=5,
                verify=False
            )
            if response.status_code == 200:
                user_data = response.json()
                print(f"✓ Authenticated as: {user_data.get('username', 'unknown')}")
                print(f"  Admin: {user_data.get('admin', False)}")
                return True
            else:
                print(f"✗ Authentication failed: {response.status_code}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"✗ Authentication error: {e}")
            return False

    def check_prerequisites(self):
        """Check that privatebox-env-dns environment exists."""
        print("\n=== Checking Prerequisites ===")
        try:
            response = requests.get(
                f"{self.base_url}/api/project/{self.project_id}/environment",
                headers=self.headers,
                timeout=10,
                verify=False
            )
            if response.status_code == 200:
                environments = response.json()
                for env in environments:
                    if env.get('name') == 'privatebox-env-dns':
                        print("✓ Found privatebox-env-dns environment")
                        return True

                print("✗ privatebox-env-dns environment not found")
                print("  You must run 'DynDNS 1: Setup Environment' first")
                print("  This creates the DNS configuration environment")
                return False
            else:
                print(f"✗ Failed to get environments: {response.status_code}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"✗ Error checking environments: {e}")
            return False

    def get_templates(self):
        """Get all templates from Semaphore."""
        try:
            response = requests.get(
                f"{self.base_url}/api/project/{self.project_id}/templates",
                headers=self.headers,
                timeout=10,
                verify=False
            )
            if response.status_code == 200:
                return response.json()
            else:
                print(f"✗ Failed to get templates: {response.status_code}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"✗ Error getting templates: {e}")
            return None

    def find_template_by_name(self, name):
        """Find a template by its name with a fresh API call."""
        try:
            response = requests.get(
                f"{self.base_url}/api/project/{self.project_id}/templates",
                headers=self.headers,
                timeout=10,
                verify=False
            )
            if response.status_code == 200:
                templates = response.json()
                for template in templates:
                    if template.get('name') == name:
                        return template
                return None
            else:
                print(f"✗ Failed to get templates: {response.status_code}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"✗ Error getting templates: {e}")
            return None

    def execute_template(self, template_id, template_name):
        """Execute a template and return the task ID."""
        print(f"\n→ Executing: {template_name}")
        try:
            payload = {
                "template_id": template_id,
                "debug": False,
                "dry_run": False
            }
            response = requests.post(
                f"{self.base_url}/api/project/{self.project_id}/tasks",
                headers=self.headers,
                json=payload,
                timeout=10,
                verify=False
            )
            if response.status_code == 201:
                task_data = response.json()
                task_id = task_data.get('id')
                print(f"  Started task ID: {task_id}")
                return task_id
            else:
                print(f"  ✗ Failed to start template: {response.status_code}")
                if response.text:
                    print(f"    Error: {response.text}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"  ✗ Error executing template: {e}")
            return None

    def wait_for_task(self, task_id, template_name, timeout=600):
        """Wait for a task to complete."""
        print(f"  Waiting for completion", end="")
        start_time = time.time()
        last_status = None

        while time.time() - start_time < timeout:
            try:
                response = requests.get(
                    f"{self.base_url}/api/project/{self.project_id}/tasks/{task_id}",
                    headers=self.headers,
                    timeout=5,
                    verify=False
                )
                if response.status_code == 200:
                    task_data = response.json()
                    status = task_data.get('status', 'unknown')

                    if status != last_status:
                        if last_status is not None:
                            print()
                        print(f"  Status: {status}", end="")
                        last_status = status
                    else:
                        print(".", end="", flush=True)

                    if status in ['success', 'error', 'failed']:
                        print()
                        return status

                    time.sleep(5)
                else:
                    print(f"\n  ⚠ Error checking task status: {response.status_code}")
                    time.sleep(5)

            except requests.exceptions.RequestException as e:
                print(f"\n  ⚠ Error checking task: {e}")
                time.sleep(5)

        print(f"\n  ✗ Task timeout after {timeout} seconds")
        return 'timeout'

    def get_task_output(self, task_id):
        """Get the last lines of task output for error reporting."""
        try:
            response = requests.get(
                f"{self.base_url}/api/project/{self.project_id}/tasks/{task_id}/output",
                headers=self.headers,
                timeout=10,
                verify=False
            )
            if response.status_code == 200:
                output_lines = response.json()
                # Get last 10 lines of actual output
                if output_lines:
                    last_lines = output_lines[-10:]
                    error_output = []
                    for line in last_lines:
                        output = line.get('output', '')
                        if output and not output.startswith('Task '):
                            # Clean ANSI codes
                            import re
                            clean_output = re.sub(r'\x1b\[[0-9;]*m', '', output)
                            if clean_output.strip():
                                error_output.append(clean_output.strip())
                    return error_output[-5:] if error_output else []
            return []
        except:
            return []

    def run_orchestration(self):
        """Run the complete orchestration sequence."""
        print("\n" + "=" * 60)
        print(" PRIVATEBOX DYNDNS CONFIGURATION")
        print("=" * 60)

        # Test connectivity and auth
        if not self.test_connectivity():
            return False

        if not self.test_authentication():
            return False

        # Check prerequisites
        if not self.check_prerequisites():
            return False

        # Execute templates in sequence
        print(f"\n=== Executing Templates in Sequence ===")
        print(f"Sequence: {' → '.join(self.template_sequence)}")

        successful_templates = []
        failed_template = None

        for template_name in self.template_sequence:
            # Find template by name (fresh lookup each time)
            template = self.find_template_by_name(template_name)
            if not template:
                print(f"\n✗ Template not found: {template_name}")
                print("  Note: This lookup is done just-in-time")
                print("  If this template should exist, check Semaphore UI")
                failed_template = template_name
                break

            # Execute template
            template_id = template.get('id')
            task_id = self.execute_template(template_id, template_name)
            if not task_id:
                print(f"✗ Failed to execute: {template_name}")
                failed_template = template_name
                break

            # Wait for completion
            status = self.wait_for_task(task_id, template_name)

            if status == 'success':
                print(f"  ✓ {template_name} completed successfully")
                successful_templates.append(template_name)
            else:
                print(f"  ✗ {template_name} failed with status: {status}")

                # Try to get error details
                error_output = self.get_task_output(task_id)
                if error_output:
                    print("  Error details:")
                    for line in error_output:
                        print(f"    {line}")

                failed_template = template_name
                break

            # Short pause between templates
            if template_name != self.template_sequence[-1]:
                print("  Waiting 5 seconds before next template...")
                time.sleep(5)

        # Summary
        print("\n" + "=" * 60)
        print(" ORCHESTRATION SUMMARY")
        print("=" * 60)

        if successful_templates:
            print("\n✓ Successfully completed:")
            for name in successful_templates:
                print(f"  - {name}")

        if failed_template:
            print(f"\n✗ Failed at: {failed_template}")
            print(f"  Templates not run: {len(self.template_sequence) - len(successful_templates) - 1}")
            return False
        else:
            print("\n✅ All DynDNS configuration completed successfully!")
            print("\nDynamic DNS is now configured:")
            print("  - OPNsense updates your public IP automatically")
            print("  - AdGuard DNS rewrites configured for internal access")
            print("  - Caddy automatically renews Let's Encrypt certificates")
            print("  - All services accessible via your external domain")
            print("\nAccess your services:")
            print("  - https://portainer.yourdomain.com")
            print("  - https://semaphore.yourdomain.com")
            print("  - https://adguard.yourdomain.com")
            return True


def main():
    """Main entry point."""
    orchestrator = DynDNSOrchestrator()

    try:
        success = orchestrator.run_orchestration()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⚠ Orchestration interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
