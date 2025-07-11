# Semaphore Template Synchronization Design

## Overview

This document describes the design and implementation plan for automatically creating Semaphore job templates from Ansible playbooks. This feature eliminates manual template creation by parsing playbooks and creating corresponding Semaphore templates via API.

## Problem Statement

Currently, each Ansible playbook requires manual creation of a Semaphore job template through the web UI. This involves:
- Navigating to Task Templates
- Clicking "New Template"
- Entering template name and description
- Selecting playbook, inventory, repository, environment, and SSH key
- Manually defining survey variables with correct types
- Saving the template

This process is:
- Time-consuming and repetitive
- Error-prone (typos, wrong types, missed variables)
- A barrier to adding new services
- Difficult to keep synchronized

## Solution Architecture

```
┌─────────────────────┐
│   GitHub Repo       │
│  - Playbooks with   │
│    semaphore_*      │
│    annotations      │
│  - tools/           │
│    generate-        │
│    templates.py     │
└──────────┬──────────┘
           │ Semaphore clones repo
           ▼
┌─────────────────────┐
│ Semaphore Container │
│                     │
│ - Web UI            │
│ - API (port 3000)   │
│ - Python 3          │
│ - Cloned repo       │
│                     │
│ Task Execution:     │
│ 1. Run playbook     │
│ 2. Execute generate-│
│    templates.py     │
│ 3. API localhost    │
└─────────────────────┘
           │
           │ Creates/Updates templates
           ▼
┌─────────────────────┐
│ Semaphore Templates │
│ - Name from file    │
│ - Survey vars from  │
│   vars_prompt       │
│ - Correct types     │
└─────────────────────┘
```

## Implementation Plan

This plan ensures a 100% hands-off solution where bootstrap automatically creates and configures everything needed for template synchronization.

### Phase 1: Basic Infrastructure ✅ COMPLETE (2025-07-10)
- ✅ Create minimal Python script (`tools/generate-templates.py`) that prints "Hello from template generator"
- ✅ **[AUTOMATED]** Enable Python application in Semaphore UI via SEMAPHORE_APPS environment variable
- ✅ **[MANUAL]** Create Python task template to test the script
- ✅ **[MANUAL]** Run the job to verify execution works
- ✅ **[CHECK]** Verify working directory when script runs - `/tmp/semaphore/project_1/repository_1_template_1`
- ✅ **[CHECK]** Confirm environment variables are passed through - Only PATH and PWD, no SEMAPHORE_* vars

### Phase 2: API Setup ✅ COMPLETE (2025-07-10)
- ✅ **[MANUAL]** Generate API token in Semaphore UI
- ✅ **[MANUAL]** Create SemaphoreAPI environment with token - Created as Variable and Secret
- ✅ Update Python script to test API connection (just ping)
- ✅ **[MANUAL]** Run job to verify API access works
- ✅ **[CHECK]** Test if API token works directly or needs session cookie - Bearer token works directly
- ✅ **[DISCOVERED]** Semaphore passes variables as command line arguments, not environment variables

### Phase 3: Repository Setup ✅ COMPLETE (2025-07-10)
- ✅ **[MANUAL]** Add PrivateBox repository to Semaphore
- ✅ **[MANUAL]** Update Semaphore job to use the repository
- ✅ **[MANUAL]** Test that script can read files from repo - Repository root check: True

### Phase 4: Basic Sync Logic ✅ COMPLETE (2025-07-10)
- ✅ Update Python script to list playbook files
- ✅ Add parsing logic to read vars_prompt
- ✅ Add one test playbook with semaphore_* metadata - test-semaphore-sync.yml
- ✅ **[MANUAL]** Test parsing works correctly - Successfully parsed 3 variables

### Phase 5: Template Creation ✅ COMPLETE (2025-07-10)
- ✅ Add template creation logic to Python script
- ✅ **[MANUAL]** Test creating one template - Successfully created/updated
- ✅ Add update logic - Handles both create and update cases
- ✅ **[MANUAL]** Test updating works - Updated template ID 2 with survey vars
- ✅ **[BONUS]** Added flexible resource lookups for inventory/repo/environment
- ✅ **[DISCOVERED]** Must include template ID in body for updates
- ✅ **[DISCOVERED]** Use task type ("") instead of deploy to avoid build template requirement
- ✅ **[DISCOVERED]** Default to "Empty" environment/variable group
- ✅ **[DISCOVERED]** Survey vars don't support default values - show in description instead
- ✅ **[DISCOVERED]** Boolean type best handled as enum with True/False options

### Phase 6: Bootstrap Automation ✅ COMPLETE (2025-07-10)
The bootstrap process now fully automates template synchronization setup:

**What Bootstrap Now Does:**
- ✅ **[AUTOMATED]** Uses admin username/password authentication during bootstrap to generate API token
- ✅ **[AUTOMATED]** Creates SemaphoreAPI environment with the generated token
- ✅ **[AUTOMATED]** Creates PrivateBox repository pointing to GitHub
- ✅ **[AUTOMATED]** Python application enabled via `SEMAPHORE_APPS` environment variable in Quadlet file
- ✅ **[AUTOMATED]** Creates "Generate Templates" Python task template
- ✅ **[AUTOMATED]** Runs initial template synchronization automatically

**Key Discoveries During Implementation:**
1. **Authentication Flow** - Bootstrap must use username/password to create the initial API token, which is then used for all subsequent operations
2. **Variable Passing** - Semaphore passes environment variables as command-line arguments (KEY=VALUE format), not as actual environment variables
3. **Environment Format** - The `json` field in environments must be a JSON string containing the variables
4. **Repository Requirements** - Repository creation requires a valid ssh_key_id (even for public repos)
5. **Template Arguments** - The arguments field must contain valid JSON, use "{}" for empty arguments

**Result:** Fresh bootstrap automatically creates all infrastructure and synchronizes templates on first run.

### Phase 7: Full Implementation ✅ COMPLETE
The Python script (`tools/generate-templates.py`) is now fully functional with:

**Implemented Features:**
- ✅ Automatic dependency installation (requests and PyYAML)
- ✅ Comprehensive error handling and informative logging
- ✅ Support for all documented metadata fields
- ✅ Flexible resource lookups by name (inventory, repository, environment)
- ✅ Both create and update operations for templates
- ✅ Detailed progress reporting during synchronization

**Production Ready:** The test playbook (`test-semaphore-sync.yml`) demonstrates the working implementation, and the system is ready for adding metadata to service playbooks.

### Final State
- **Fresh install**: 100% automated - bootstrap enables Python, creates infrastructure and runs initial template generation
- **Existing install**: One manual run of updated bootstrap script (or manually enable Python in UI)
- **Ongoing use**: Click "Generate Templates" in UI or schedule it

## Design Decisions

### Why Python?
- **Chosen**: Python script running in Semaphore container
- **Alternatives considered**:
  - Go: Would require compilation step and binary deployment
  - Pure Ansible: Limited YAML parsing capabilities, complex logic becomes painful
  - Shell script: Fragile YAML parsing, poor error handling
- **Rationale**: 
  - Python 3 is pre-installed in Semaphore container
  - Provides proper YAML parsing with PyYAML
  - Good error handling and debugging capabilities
  - No compilation or deployment of binaries needed

### Why Python Tasks Instead of Ansible Wrapper?
- **Chosen**: Use native Python task type in Semaphore
- **Alternatives considered**:
  - Ansible playbook wrapper: Extra layer of complexity, indirect execution
  - Shell/Bash task: Would work but less semantic clarity
  - Custom integration: Overkill for this use case
- **Rationale**: 
  - Direct execution of Python scripts
  - No intermediate wrapper needed
  - Clear intent - Python scripts run as Python tasks
  - Semaphore supports Python as a first-class application type
  - Simpler debugging and output handling

### Why Run in Container Instead of VM?
- **Chosen**: Script executes directly in Semaphore container
- **Alternatives considered**:
  - Running on VM: Would require SSH from container to VM, then API calls back to container
  - Custom container: Maintenance burden, diverges from official image
- **Rationale**: 
  - Semaphore tasks naturally execute in the container
  - Direct access to API via localhost:3000 (no network hops)
  - Repository automatically cloned by Semaphore
  - Simpler execution flow - no SSH required
  - Python and all dependencies already available

### Why Inline Metadata?
- **Chosen**: Add `semaphore_*` fields directly to vars_prompt
- **Alternatives considered**:
  - Separate YAML config files: Duplication, synchronization issues
  - Comments with metadata: Fragile parsing, feels hacky
  - Parse without metadata: Can't determine correct types
- **Rationale**: 
  - Ansible ignores unknown fields in vars_prompt
  - Keeps metadata with the code
  - Version controlled together
  - Clear and explicit


## Implementation Details

### Phase 1: Bootstrap-Time Setup (One-Time)

During initial bootstrap, `semaphore-setup.sh` performs the following:

1. **Authenticate with Admin Credentials**
   - Uses the admin username and password to authenticate
   - Obtains a session cookie for API operations
   - This is the only time username/password authentication is used

2. **Create API Token**
   - Makes authenticated request to `/api/user/tokens` to generate a permanent API token
   - Stores token in `/root/.credentials/semaphore_credentials.txt`
   - This token is used for all future template synchronization

3. **Create Semaphore Environment**
   ```json
   {
     "name": "SemaphoreAPI",
     "project_id": 1,
     "password": null,
     "json": "{\"SEMAPHORE_URL\":\"http://localhost:3000\",\"SEMAPHORE_API_TOKEN\":\"<generated-token>\"}"
   }
   ```
   Note: The `json` field must be a string containing JSON, not a JSON object

4. **Create Repository**
   ```json
   {
     "name": "PrivateBox",
     "project_id": 1,
     "git_url": "https://github.com/Rasped/privatebox.git",
     "git_branch": "main",
     "ssh_key_id": 1
   }
   ```
   Note: ssh_key_id must be a valid ID, even for public repositories

5. **Enable Python Application**
   - Python is automatically enabled via the `SEMAPHORE_APPS` environment variable in the Quadlet container configuration
   - No manual API calls needed

6. **Create Initial Template Generation Task**
   Bootstrap automatically:
   - Looks up the inventory ID for "Default Inventory"
   - Looks up the repository ID for "PrivateBox"
   - Looks up the environment ID for "SemaphoreAPI"
   - Creates the Python task template:
   ```json
   {
     "name": "Generate Templates",
     "project_id": 1,
     "inventory_id": <looked-up-id>,
     "repository_id": <looked-up-id>,
     "environment_id": <looked-up-id>,
     "app": "python",
     "playbook": "tools/generate-templates.py",
     "arguments": "{}",
     "allow_override_args_in_task": false,
     "type": ""
   }
   ```

7. **Run Initial Synchronization**
   - Bootstrap automatically triggers the first template generation run
   - This creates templates for any playbooks with semaphore metadata

### Phase 2: Runtime Operation (Ongoing)

#### Direct Python Script Execution
With Python enabled as an application in Semaphore, the Python script runs directly without needing an Ansible wrapper. 

**Important Discovery:** Semaphore passes environment variables as command-line arguments in KEY=VALUE format, not as actual environment variables. The Python script parses sys.argv to extract these values.

#### Python Dependencies
The script requires:
- `PyYAML` - Likely already available (required by Ansible/Semaphore)
- `requests` - Installed at runtime if needed

**Chosen approach: Runtime installation**

The script will handle missing dependencies automatically:
```python
# At the top of generate-templates.py
try:
    import requests
except ImportError:
    import subprocess
    print("Installing requests package...")
    subprocess.check_call(['pip', 'install', 'requests'])
    import requests
```

This approach was chosen because:
- No custom Docker image needed (uses official Semaphore image)
- No maintenance overhead when Semaphore updates
- pip won't reinstall if package already exists
- Clean and self-contained solution for a single dependency
- Transparent - dependency management is visible in the code

#### The Python Script
`tools/generate-templates.py` performs the following:

1. **Discover Playbooks**
   ```python
   # Script runs from repository root
   playbook_dir = Path('ansible/playbooks/services')
   playbooks = playbook_dir.glob('*.yml')
   ```

2. **Parse Each Playbook**
   ```python
   with open(playbook_file) as f:
       data = yaml.safe_load(f)
   
   # Extract vars_prompt if present
   vars_prompt = data[0].get('vars_prompt', []) if data else []
   ```

3. **Convert to Survey Variables**
   Key type mappings discovered:
   - `boolean` → `enum` type with True/False options
   - `integer` → `int` type
   - `text` → empty string (default)
   - `password` or `private: yes` → `secret` type
   
   Default values are shown in the description field since survey variables don't support actual defaults:
   ```python
   # Build description with recommended value
   description = var.get('semaphore_description', var.get('prompt', ''))
   if 'default' in var and description:
       description = f"{description} (recommended: {var['default']})"
   ```

4. **Look Up Required IDs**
   The script flexibly looks up resources by name:
   ```python
   # Using Bearer token authentication
   headers = {"Authorization": f"Bearer {api_token}"}
   
   # Get inventory ID by name
   inventories = requests.get(f"{api_url}/project/1/inventory", 
                            headers=headers).json()
   
   # Find by name with fallback handling
   inventory_id = next((i['id'] for i in inventories 
                       if i['name'] == inventory_name), None)
   
   # Similar lookups for repository and environment
   # Environment defaults to "Empty" if not specified
   ```

5. **Create or Update Template**
   Key discoveries for template creation:
   - Template type should be empty string ("") for standard tasks
   - Must specify `app: "ansible"` for Ansible templates
   - Update operations require the template ID in the request body
   
   ```python
   template_data = {
       'name': template_name,
       'project_id': 1,
       'inventory_id': inventory_id,
       'repository_id': repository_id,
       'environment_id': environment_id,
       'playbook': f"ansible/playbooks/services/{playbook_file.name}",
       'arguments': '[]',
       'description': f"Generated from {playbook_path.name}",
       'allow_override_args_in_task': False,
       'survey_vars': survey_vars,
       'type': '',  # Empty string for task type
       'app': 'ansible'
   }
   
   # For updates, must include the ID in the body
   if existing_template:
       template_data['id'] = existing_template['id']
   ```

## API Reference

### Authentication

Semaphore supports two authentication methods:

#### 1. Bootstrap Authentication (Username/Password → Session Cookie)
Used only during initial setup to create the API token:

```python
# Login with admin credentials to get session cookie
login_data = {
    "auth": "admin",
    "password": "your-admin-password"
}
response = requests.post(
    "http://localhost:3000/api/auth/login",
    json=login_data
)
# Extract session cookie for subsequent requests
session_cookie = f"semaphore={response.cookies.get('semaphore')}"

# Use session to create API token
headers = {"Cookie": session_cookie}
token_response = requests.post(
    "http://localhost:3000/api/user/tokens",
    json={"name": "template-generator"},
    headers=headers
)
api_token = token_response.json()['id']
```

#### 2. Runtime Authentication (Bearer Token)
Used by the Python script for all template operations:

```python
# Use Bearer token for all API calls
headers = {"Authorization": f"Bearer {api_token}"}
response = requests.get(
    "http://localhost:3000/api/projects",
    headers=headers
)
```

### Running Jobs Programmatically
To trigger a job run:

```python
# Start a task using the template
headers = {"Authorization": f"Bearer {api_token}"}
task_payload = {"template_id": template_id}

response = requests.post(
    f"http://localhost:3000/api/project/1/tasks",
    json=task_payload,
    headers=headers
)
task_id = response.json()['id']

# Check task status
status_response = requests.get(
    f"http://localhost:3000/api/project/1/tasks/{task_id}",
    headers=headers
)
task_status = status_response.json()['status']  # 'success', 'error', 'running', etc.
```

### Key API Endpoints

**Authentication:**
- `POST /api/auth/login` - Login with username/password (bootstrap only)
- `POST /api/user/tokens` - Create API token
- `GET /api/user` - Verify authentication

**Resources:**
- `GET /api/project/{id}/inventory` - List inventories
- `GET /api/project/{id}/repositories` - List repositories  
- `GET /api/project/{id}/environment` - List environments
- `POST /api/project/{id}/environment` - Create environment

**Templates:**
- `GET /api/project/{id}/templates` - List templates
- `POST /api/project/{id}/templates` - Create template
- `PUT /api/project/{id}/templates/{template_id}` - Update template (ID required in body)

**Tasks:**
- `POST /api/project/{id}/tasks` - Run a task
- `GET /api/project/{id}/tasks/{task_id}` - Check task status

## Usage Guide

### Annotating Playbooks

Add `semaphore_*` fields to vars_prompt in your playbook:

```yaml
---
- name: Deploy AdGuard Home DNS Filter
  hosts: privatebox
  
  vars_prompt:
    - name: confirm_deploy
      prompt: "Deploy AdGuard Home? (yes/no)"
      default: "yes"
      private: no
      # Semaphore template metadata
      semaphore_type: boolean
      semaphore_description: "Confirm deployment of AdGuard Home"
      
    - name: custom_web_port
      prompt: "Web UI port (default: 8080)"
      default: "8080"
      private: no
      semaphore_type: integer
      semaphore_description: "Port for AdGuard web interface"
      semaphore_min: 1024
      semaphore_max: 65535
      semaphore_required: false
      
    - name: dns_upstream
      prompt: "Upstream DNS server"
      default: "9.9.9.9"
      private: no
      semaphore_type: text
      semaphore_description: "Upstream DNS server for AdGuard"
```

### Supported Field Types

| Field | Description | Example |
|-------|-------------|---------|
| `semaphore_type` | Variable type: text, integer, boolean | `integer` |
| `semaphore_description` | Help text shown in UI | `"Port number"` |
| `semaphore_required` | Is field required? | `false` |
| `semaphore_min` | Minimum value (integer only) | `1024` |
| `semaphore_max` | Maximum value (integer only) | `65535` |

### Additional Template Configuration

You can customize template properties by adding a special configuration variable:

```yaml
vars_prompt:
  - name: semaphore_template_config
    semaphore_template_config:
      semaphore_template_name: "Custom Template Name"
      semaphore_inventory: "Production Inventory"
      semaphore_repository: "PrivateBox"
      semaphore_environment: "Production"
```

This allows overriding default template settings without affecting the playbook's execution.

### Running Template Sync

1. **Automatic Initial Sync**:
   - Bootstrap automatically runs the first synchronization
   - Creates templates for any playbooks with semaphore metadata
   - No manual intervention required for fresh installs

2. **Manual Sync from Semaphore UI**:
   - Navigate to Task Templates
   - Click "Run" on "Generate Templates"
   - View output for results

3. **What Happens During Sync**:
   - Semaphore automatically clones/updates the repository
   - All service playbooks are scanned for semaphore_* metadata
   - New templates are created with proper survey variables
   - Existing templates are updated with latest configuration
   - Default values are shown in description fields
   - Errors are reported but don't stop the process

## Limitations

1. **Simple Types Only**: Only supports text, integer, boolean (no arrays/objects)
2. **No Jinja2 Evaluation**: Can't evaluate complex default values with Jinja2
3. **Basic Error Handling**: Skips problematic playbooks with warnings
4. **Fixed Conventions**: Assumes:
   - Inventory named "Default Inventory"
   - Repository named "PrivateBox"
   - Project ID is always 1

## Important Considerations

### vars_prompt Extra Fields

The use of `semaphore_*` fields in `vars_prompt` is **experimental**:

1. **Not Officially Documented**: Ansible documentation doesn't explicitly state whether extra fields in vars_prompt are supported
2. **Version Compatibility**: Future Ansible versions might validate vars_prompt more strictly
3. **Testing Recommended**: 
   - Test playbooks with ansible-lint before deploying
   - Verify playbooks still work with your Ansible version
   - Consider this a "use at your own risk" feature

### Template Updates

1. **Overwrites Manual Changes**: Updates will overwrite any manual customizations made to templates in Semaphore UI
2. **No Rollback**: There's no built-in way to restore previous template configurations
3. **Consider Version Control**: Keep important template configurations in a separate file if manual customization is needed

## Error Handling

The script will:
- **Skip and warn** about playbooks it can't parse
- **Continue processing** other playbooks after errors
- **Report summary** of created/skipped templates
- **Log details** for debugging

Example output:
```
Syncing Semaphore templates...
✓ Created template: Deploy: AdGuard Home
✗ Skipped: complex-service.yml (Error: Unable to parse vars_prompt)
✓ Updated template: Deploy: Pi-hole
✓ Created template: Deploy: WireGuard

Summary: 2 created, 1 updated, 1 error
```

## Troubleshooting

### Template Not Created
1. Check playbook has `vars_prompt` section
2. Verify YAML syntax is valid
3. Check script output for specific errors
4. Ensure all semaphore_* fields have correct types

### API Errors
1. Verify Semaphore is running: `systemctl status semaphore-ui`
2. Check API token is valid (Bearer token format)
3. Ensure required resources exist:
   - "Default Inventory" must exist
   - "PrivateBox" repository must be created
   - "Empty" environment should exist (or specify custom)
4. Check Semaphore logs: `podman logs semaphore-ui`
5. Verify variables are being passed correctly (check task output)

### Repository Issues
1. Ensure Semaphore can access the Git repository
2. Check SSH keys or credentials in Key Store if using private repository
3. Verify network connectivity to GitHub

## Future Enhancements

1. **Template Deletion**: Remove templates for deleted playbooks
2. **Complex Types**: Support for lists, dicts in survey variables
3. **Scheduled Sync**: Automatic daily/weekly synchronization
4. **Dry Run Mode**: Preview changes without creating templates
5. **Custom Field Mapping**: Configuration file for type mappings
6. **Validation**: Pre-flight checks for playbook compatibility
7. **Change Detection**: Only update templates when playbook actually changes

## Security Considerations

1. **API Token**: Stored encrypted in Semaphore environment
2. **Repository Access**: Uses HTTPS, no credentials stored
3. **Container Execution**: Runs in isolated Semaphore container environment
4. **Audit Trail**: All actions logged in Semaphore task output