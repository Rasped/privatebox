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

### Phase 6: Bootstrap Automation
Update `semaphore-setup.sh` to:
- **[AUTOMATES]** Generate API token programmatically
- **[AUTOMATES]** Create SemaphoreAPI environment
- **[AUTOMATES]** Create PrivateBox repository
- **[AUTOMATES]** Enable Python application in Semaphore
- **[AUTOMATES]** Create "Generate Templates" Python task template
- **[AUTOMATES]** Run the template generation job automatically

Test fresh bootstrap creates everything AND syncs templates.

### Phase 7: Full Implementation
- Add error handling and logging to Python script
- Add metadata to all service playbooks
- Test complete bootstrap on fresh system
- Verify all templates are created automatically

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

During initial bootstrap, `semaphore-setup.sh` must:

1. **Create API Token**
   - After Semaphore is running, generate an API token
   - Store in `/root/.credentials/semaphore_api_token`

2. **Create Semaphore Environment**
   ```json
   {
     "name": "SemaphoreAPI",
     "project_id": 1,
     "password": null,
     "json": {
       "SEMAPHORE_URL": "http://localhost:3000",
       "SEMAPHORE_API_TOKEN": "<generated-token>"
     }
   }
   ```

3. **Create Repository**
   ```json
   {
     "name": "PrivateBox",
     "project_id": 1,
     "git_url": "https://github.com/Rasped/privatebox.git",
     "git_branch": "main",
     "ssh_key_id": null
   }
   ```

4. **Enable Python Application**
   - Check if Python is already enabled via API
   - If not, enable Python app (method TBD based on API investigation)

5. **Create Initial Template Generation Task**
   This is a one-time creation during bootstrap. The script will need to:
   - Look up the inventory ID for "Default Inventory"
   - Look up the repository ID for "PrivateBox"
   - Look up the environment ID for "SemaphoreAPI"
   - Create the Python task template:
   ```json
   {
     "name": "Generate Templates",
     "project_id": 1,
     "inventory_id": <looked-up-id>,
     "repository_id": <looked-up-id>,
     "environment_id": <looked-up-id>,
     "app": "python",
     "playbook": "tools/generate-templates.py",
     "arguments": null,
     "override_args": false
   }
   ```

### Phase 2: Runtime Operation (Ongoing)

#### Direct Python Script Execution
With Python enabled as an application in Semaphore, the Python script runs directly without needing an Ansible wrapper. The environment variables (SEMAPHORE_URL and SEMAPHORE_API_TOKEN) are automatically passed from the Semaphore environment configuration.

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
`tools/generate-templates.py` will:

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
   ```python
   survey_vars = []
   for var in vars_prompt:
       survey_var = {
           'name': var['name'],
           'type': var.get('semaphore_type', 'text'),
           'required': var.get('semaphore_required', not var.get('private', True)),
           'description': var.get('semaphore_description', var.get('prompt', ''))
       }
       
       # Add constraints for integers
       if survey_var['type'] == 'integer':
           if 'semaphore_min' in var:
               survey_var['min'] = var['semaphore_min']
           if 'semaphore_max' in var:
               survey_var['max'] = var['semaphore_max']
               
       survey_vars.append(survey_var)
   ```

4. **Look Up Required IDs**
   ```python
   # Get inventory ID by name
   inventories = requests.get(f"{api_url}/project/1/inventory", 
                            cookies={'semaphore': token}).json()
   try:
       inventory_id = next(i['id'] for i in inventories 
                          if i['name'] == 'Default Inventory')
   except StopIteration:
       print(f"ERROR: Inventory 'Default Inventory' not found")
       return
   
   # Similar for repository_id, environment_id
   ```

5. **Create or Update Template**
   ```python
   template_name = f"Deploy: {playbook_name}"
   template_data = {
       'name': template_name,
       'project_id': 1,
       'inventory_id': inventory_id,
       'repository_id': repository_id,
       'environment_id': environment_id,
       'playbook': f"ansible/playbooks/services/{playbook_file.name}",
       'survey_vars': survey_vars
   }
   
   # Check if template already exists
   existing_templates = requests.get(f"{api_url}/project/1/templates",
                                   cookies={'semaphore': token}).json()
   existing_template = next((t for t in existing_templates 
                           if t['name'] == template_name), None)
   
   if existing_template:
       # Update existing template
       response = requests.put(f"{api_url}/project/1/templates/{existing_template['id']}",
                             json=template_data,
                             cookies={'semaphore': token})
       print(f"✓ Updated template: {template_name}")
   else:
       # Create new template
       response = requests.post(f"{api_url}/project/1/templates",
                              json=template_data,
                              cookies={'semaphore': token})
       print(f"✓ Created template: {template_name}")
   ```

## API Reference

### Authentication
Semaphore uses cookie-based sessions. To authenticate:

```python
# Login and get session cookie
login_data = {
    "auth": "admin",
    "password": "your-admin-password"
}
response = requests.post(
    "http://localhost:3000/api/auth/login",
    json=login_data
)
# Extract cookie from response headers
cookie = response.cookies.get('semaphore')
```

### Running Jobs Programmatically
To trigger a job run after creating templates:

```python
# Get template ID (from creation response or by querying)
template_id = 123  # The sync template ID

# Start a job
job_data = {}  # Empty for jobs without variables
response = requests.post(
    f"http://localhost:3000/api/project/1/tasks",
    json={
        "template_id": template_id,
        "debug": False,
        "diff": False,
        "playbook": "",
        "environment": "",
        "limit": ""
    },
    cookies={'semaphore': cookie}
)
job_id = response.json()['id']
```

### Key API Endpoints
- `POST /api/auth/login` - Authenticate and get session
- `GET /api/project/{id}/templates` - List templates
- `POST /api/project/{id}/templates` - Create template
- `PUT /api/project/{id}/templates/{template_id}` - Update template
- `POST /api/project/{id}/tasks` - Run a job
- `GET /api/project/{id}/tasks/{task_id}` - Check job status

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

### Running Template Sync

1. **From Semaphore UI**:
   - Navigate to Task Templates
   - Click "Run" on "Generate Templates"
   - View output for results

2. **What Happens**:
   - Semaphore automatically clones/updates the repository
   - All service playbooks are scanned
   - New templates are created
   - Existing templates are updated with latest configuration
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
2. Check API token is valid
3. Ensure required objects exist (inventory, keys, etc.)
4. Check Semaphore logs: `podman logs semaphore-ui`

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