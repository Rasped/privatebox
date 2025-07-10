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


def get_inventory_id(base_url, api_token, project_id, inventory_name="Default Inventory"):
    """Get inventory ID by name, with configurable default."""
    headers = {"Authorization": f"Bearer {api_token}"}
    
    try:
        response = requests.get(f"{base_url}/api/project/{project_id}/inventory", headers=headers, timeout=5)
        if response.status_code == 200:
            inventories = response.json()
            for inventory in inventories:
                if inventory.get('name') == inventory_name:
                    return inventory.get('id')
            
            # If not found, list available inventories
            print(f"\n⚠️  Inventory '{inventory_name}' not found. Available inventories:")
            for inv in inventories:
                print(f"    - {inv.get('name')} (ID: {inv.get('id')})")
            return None
        else:
            print(f"✗ Failed to list inventories: {response.status_code}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"✗ Failed to get inventories: {e}")
        return None


def get_repository_id(base_url, api_token, project_id, repository_name="PrivateBox"):
    """Get repository ID by name, with configurable default."""
    headers = {"Authorization": f"Bearer {api_token}"}
    
    try:
        response = requests.get(f"{base_url}/api/project/{project_id}/repositories", headers=headers, timeout=5)
        if response.status_code == 200:
            repositories = response.json()
            for repo in repositories:
                if repo.get('name') == repository_name:
                    return repo.get('id')
            
            # If not found, list available repositories
            print(f"\n⚠️  Repository '{repository_name}' not found. Available repositories:")
            for repo in repositories:
                print(f"    - {repo.get('name')} (ID: {repo.get('id')})")
            return None
        else:
            print(f"✗ Failed to list repositories: {response.status_code}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"✗ Failed to get repositories: {e}")
        return None


def get_environment_id(base_url, api_token, project_id, environment_name=None):
    """Get environment ID by name. If not specified, looks for 'Empty' environment."""
    if not environment_name:
        environment_name = "Empty"  # Default to "Empty" environment
    
    headers = {"Authorization": f"Bearer {api_token}"}
    
    try:
        response = requests.get(f"{base_url}/api/project/{project_id}/environment", headers=headers, timeout=5)
        if response.status_code == 200:
            environments = response.json()
            for env in environments:
                if env.get('name') == environment_name:
                    return env.get('id')
            
            # If not found, list available environments
            print(f"\n⚠️  Environment '{environment_name}' not found. Available environments:")
            for env in environments:
                print(f"    - {env.get('name')} (ID: {env.get('id')})")
            return None
        else:
            print(f"✗ Failed to list environments: {response.status_code}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"✗ Failed to get environments: {e}")
        return None


def get_view_id(base_url, api_token, project_id):
    """Get the first available view ID for the project."""
    headers = {"Authorization": f"Bearer {api_token}"}
    
    try:
        response = requests.get(f"{base_url}/api/project/{project_id}/views", headers=headers, timeout=5)
        if response.status_code == 200:
            views = response.json()
            if views:
                # Return the first view ID
                return views[0].get('id')
            else:
                print("✗ No views found in project")
                return None
        else:
            # Views might not be available in all versions, try to continue without it
            return None
    except requests.exceptions.RequestException as e:
        # Views might not be available, continue without it
        return None


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
        
        # Extract template configuration and variables
        template_config = {}
        semaphore_vars = []
        
        for var in vars_prompt:
            # Check for template configuration
            if var.get('name') == 'semaphore_template_config' or 'semaphore_template_config' in var:
                # Extract template-level configuration
                config = var.get('semaphore_template_config', {})
                template_config.update(config)
                continue
            
            # Check if this variable has any semaphore_* fields
            has_semaphore_metadata = any(key.startswith('semaphore_') for key in var.keys())
            if has_semaphore_metadata:
                semaphore_vars.append(var)
        
        if not semaphore_vars and not template_config:
            return None
        
        result = {
            'name': play.get('name', 'Unnamed playbook'),
            'vars': semaphore_vars,
            'template_config': template_config
        }
        
        # Allow template name override from config
        if 'semaphore_template_name' in template_config:
            result['template_name'] = template_config['semaphore_template_name']
        
        return result
    
    except Exception as e:
        print(f"✗ Error parsing {playbook_path}: {e}")
        return None


def convert_to_survey_vars(vars_list):
    """Convert playbook variables with semaphore metadata to survey_vars format."""
    survey_vars = []
    
    for var in vars_list:
        # Map our metadata types to Semaphore types
        var_type = var.get('semaphore_type', 'text')
        if var_type == 'boolean':
            survey_type = 'enum'  # Use enum for boolean with True/False options
        elif var_type == 'integer':
            survey_type = 'int'
        elif var_type == 'password' or var.get('private', False):
            survey_type = 'secret'
        else:
            survey_type = ''  # Default to text (empty string)
        
        # Build description, optionally adding default value
        description = var.get('semaphore_description', var.get('prompt', ''))
        if 'default' in var and description:
            description = f"{description} (default: {var['default']})"
        elif 'default' in var:
            description = f"Default: {var['default']}"
        
        survey_var = {
            'name': var.get('name'),
            'title': var.get('name', 'Unnamed variable'),
            'description': description,
            'type': survey_type,
            'required': var.get('semaphore_required', not var.get('private', True))
        }
        
        # Add enum values for boolean types
        if var_type == 'boolean':
            # Use the default from the playbook
            default_value = var.get('default', 'yes')
            # Add True/False options
            survey_var['values'] = [
                {'name': 'True', 'value': 'true'},
                {'name': 'False', 'value': 'false'}
            ]
        
        # Add integer constraints if present
        if var_type == 'integer':
            if 'semaphore_min' in var:
                survey_var['min'] = var['semaphore_min']
            if 'semaphore_max' in var:
                survey_var['max'] = var['semaphore_max']
        
        # Handle enum type if we have predefined values
        if 'semaphore_values' in var:
            survey_var['type'] = 'enum'
            survey_var['values'] = [
                {'name': str(v), 'value': str(v)} for v in var['semaphore_values']
            ]
        
        survey_vars.append(survey_var)
    
    return survey_vars


def create_or_update_template(base_url, api_token, project_id, playbook_path, playbook_info, resource_ids):
    """Create or update a template based on playbook information."""
    headers = {"Authorization": f"Bearer {api_token}"}
    
    # Determine template name
    template_name = playbook_info.get('template_name', f"Deploy: {playbook_path.stem}")
    
    # Convert variables to survey format
    survey_vars = convert_to_survey_vars(playbook_info['vars'])
    
    # Build template data
    template_data = {
        'name': template_name,
        'project_id': project_id,
        'inventory_id': resource_ids['inventory_id'],
        'repository_id': resource_ids['repository_id'],
        'environment_id': resource_ids.get('environment_id'),
        'playbook': f"ansible/playbooks/services/{playbook_path.name}",
        'arguments': '[]',
        'description': f"Generated from {playbook_path.name}",
        'allow_override_args_in_task': False,
        'survey_vars': survey_vars,
        'type': playbook_info.get('template_config', {}).get('semaphore_template_type', ''),  # Default to task type
        'app': 'ansible'  # Specify this is an Ansible template
    }
    
    # Add view_id if available
    if resource_ids.get('view_id'):
        template_data['view_id'] = resource_ids['view_id']
    
    try:
        # Check if template exists
        response = requests.get(f"{base_url}/api/project/{project_id}/templates", headers=headers, timeout=5)
        if response.status_code == 200:
            existing_templates = response.json()
            existing_template = next((t for t in existing_templates if t['name'] == template_name), None)
            
            if existing_template:
                # Update existing template
                template_id = existing_template['id']
                # Add the ID to the template data for update
                template_data['id'] = template_id
                response = requests.put(
                    f"{base_url}/api/project/{project_id}/templates/{template_id}",
                    json=template_data,
                    headers=headers,
                    timeout=10
                )
                if response.status_code in [200, 204]:
                    print(f"\n✓ Updated template: {template_name} (ID: {template_id})")
                    return True
                else:
                    print(f"\n✗ Failed to update template: {response.status_code}")
                    print(f"   Response: {response.text}")
                    return False
            else:
                # Create new template
                response = requests.post(
                    f"{base_url}/api/project/{project_id}/templates",
                    json=template_data,
                    headers=headers,
                    timeout=10
                )
                if response.status_code in [200, 201]:
                    new_template = response.json()
                    print(f"\n✓ Created template: {template_name} (ID: {new_template.get('id', 'unknown')})")
                    return True
                else:
                    print(f"\n✗ Failed to create template: {response.status_code}")
                    print(f"   Response: {response.text}")
                    return False
        else:
            print(f"\n✗ Failed to list templates: {response.status_code}")
            return False
    
    except requests.exceptions.RequestException as e:
        print(f"\n✗ Error creating/updating template: {e}")
        return False


def display_playbook_info(playbook_path, info):
    """Display parsed playbook information."""
    print(f"\n📄 {playbook_path.name}")
    print(f"   Name: {info['name']}")
    
    # Display template configuration if present
    if info.get('template_config'):
        print("   Template Configuration:")
        config = info['template_config']
        if 'semaphore_template_name' in config:
            print(f"     Custom name: {config['semaphore_template_name']}")
        if 'semaphore_inventory' in config:
            print(f"     Inventory: {config['semaphore_inventory']}")
        if 'semaphore_repository' in config:
            print(f"     Repository: {config['semaphore_repository']}")
        if 'semaphore_environment' in config:
            print(f"     Environment: {config['semaphore_environment']}")
    
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
    playbooks_with_metadata = []
    
    for playbook in playbooks:
        info = parse_playbook(playbook)
        if info:
            playbooks_with_metadata.append((playbook, info))
            display_playbook_info(playbook, info)
    
    if not playbooks_with_metadata:
        print("\n⚠️  No playbooks with semaphore_* metadata found.")
        print("To enable template generation, add semaphore_* fields to vars_prompt in your playbooks.")
        return
    
    print(f"\n✓ Found {len(playbooks_with_metadata)} playbook(s) with Semaphore metadata")
    
    # Phase 5: Create/Update templates
    print("\n=== Phase 5: Creating/Updating Templates ===")
    
    # Use project ID 1 (from our earlier check)
    project_id = 1
    
    # Get view ID (might not be available in all versions)
    view_id = get_view_id(semaphore_url, api_token, project_id)
    
    templates_processed = 0
    templates_created = 0
    templates_updated = 0
    templates_failed = 0
    
    for playbook_path, playbook_info in playbooks_with_metadata:
        print(f"\n🔄 Processing: {playbook_path.name}")
        
        # Get template configuration
        config = playbook_info.get('template_config', {})
        
        # Look up resource IDs based on configuration or defaults
        inventory_name = config.get('semaphore_inventory', 'Default Inventory')
        repository_name = config.get('semaphore_repository', 'PrivateBox')
        environment_name = config.get('semaphore_environment')
        
        print(f"   Looking up resources...")
        inventory_id = get_inventory_id(semaphore_url, api_token, project_id, inventory_name)
        if not inventory_id:
            print(f"   ✗ Skipping: Inventory '{inventory_name}' not found")
            templates_failed += 1
            continue
        
        repository_id = get_repository_id(semaphore_url, api_token, project_id, repository_name)
        if not repository_id:
            print(f"   ✗ Skipping: Repository '{repository_name}' not found")
            templates_failed += 1
            continue
        
        # Always try to get environment ID - defaults to "Empty" if not specified
        environment_id = get_environment_id(semaphore_url, api_token, project_id, environment_name)
        if environment_name and not environment_id:
            print(f"   ⚠️  Warning: Environment '{environment_name}' not found, continuing without it")
        elif not environment_name and not environment_id:
            print(f"   ⚠️  Warning: Default environment 'Empty' not found")
        
        # Prepare resource IDs
        resource_ids = {
            'inventory_id': inventory_id,
            'repository_id': repository_id,
            'environment_id': environment_id,
            'view_id': view_id
        }
        
        # Create or update the template
        if create_or_update_template(semaphore_url, api_token, project_id, playbook_path, playbook_info, resource_ids):
            templates_processed += 1
            # Note: The function prints whether it created or updated
        else:
            templates_failed += 1
    
    # Summary
    print("\n=== Summary ===")
    print(f"✓ Templates processed successfully: {templates_processed}")
    if templates_failed > 0:
        print(f"✗ Templates failed: {templates_failed}")
    
    print("\n✅ Template synchronization complete!")


if __name__ == "__main__":
    main()