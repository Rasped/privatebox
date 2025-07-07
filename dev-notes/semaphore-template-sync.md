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
└──────────┬──────────┘
           │ git clone/pull
           ▼
┌─────────────────────┐     ┌─────────────────────┐
│   PrivateBox VM     │     │  Semaphore Container│
│                     │     │                     │
│ /opt/privatebox/    │     │  - Web UI           │
│   repo/             │◄────┤  - API (port 3000)  │
│   - tools/          │     │  - Stored API token │
│     semaphore-      │     │    in environment   │
│     sync.py         │     │                     │
│                     │     │  "Sync Templates"   │
│ Python script runs  │     │  job triggers       │
│ locally, calls      │     │  script on VM       │
│ API via localhost   │     │                     │
└─────────────────────┘     └─────────────────────┘
           │
           │ API calls (localhost:3000)
           │ Creates templates
           ▼
┌─────────────────────┐
│ Created Templates   │
│ - Name from file    │
│ - Survey vars from  │
│   vars_prompt       │
│ - Correct types     │
└─────────────────────┘
```

## Design Decisions

### Why Python?
- **Chosen**: Python script running on VM
- **Alternatives considered**:
  - Go: Would require compilation step or installing Go toolchain in container
  - Pure Ansible: Limited YAML parsing capabilities, complex logic becomes painful
  - Shell script: Fragile YAML parsing, poor error handling
- **Rationale**: Python provides proper YAML parsing, good error handling, and is pre-installed on Ubuntu VMs

### Why Run on VM Instead of Container?
- **Chosen**: Script executes on PrivateBox VM
- **Alternatives considered**:
  - Running in Semaphore container: Would require installing Python/dependencies each run
  - Custom container: Maintenance burden, diverges from official image
- **Rationale**: 
  - VM has all dependencies (Python, Git)
  - Can access Semaphore API via localhost
  - Easier debugging via SSH
  - Follows pattern of VM being the management host

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

### Why Store Repository Locally?
- **Chosen**: Clone repository to `/opt/privatebox/repo` during bootstrap
- **Alternatives considered**:
  - GitHub API: Rate limits, needs auth, complex
  - Semaphore workspace: Would need full clone just for template sync
  - Read from Semaphore's clone: Can't access from VM
- **Rationale**: Simple, reliable, no external dependencies

## Implementation Details

### Phase 1: Bootstrap-Time Setup (One-Time)

During initial bootstrap, `semaphore-setup.sh` must:

1. **Clone Repository**
   ```bash
   git clone https://github.com/Rasped/privatebox.git /opt/privatebox/repo
   ```

2. **Create API Token**
   - After Semaphore is running, generate an API token
   - Store in `/root/.credentials/semaphore_api_token`

3. **Create Semaphore Environment**
   ```json
   {
     "name": "SemaphoreAPI",
     "project_id": 1,
     "password": null,
     "json": {
       "SEMAPHORE_URL": "http://localhost:3000",
       "SEMAPHORE_API_TOKEN": "<generated-token>",
       "REPO_PATH": "/opt/privatebox/repo"
     }
   }
   ```

4. **Create Repository**
   ```json
   {
     "name": "PrivateBox",
     "project_id": 1,
     "git_url": "https://github.com/Rasped/privatebox.git",
     "git_branch": "main",
     "ssh_key_id": null
   }
   ```

5. **Create Initial Sync Template**
   This is a one-time manual creation during bootstrap. The script will need to:
   - Look up the inventory ID for "Default Inventory"
   - Look up the repository ID for "PrivateBox"
   - Look up the environment ID for "SemaphoreAPI"
   - Create the template:
   ```json
   {
     "name": "Sync Templates",
     "project_id": 1,
     "inventory_id": <looked-up-id>,
     "repository_id": <looked-up-id>,
     "environment_id": <looked-up-id>,
     "playbook": "ansible/playbooks/maintenance/sync-templates.yml",
     "arguments": null,
     "override_args": false,
     "key_id": <id-for-vm-container-host-key>
   }
   ```

### Phase 2: Runtime Operation (Ongoing)

#### The Sync Playbook
`ansible/playbooks/maintenance/sync-templates.yml`:
```yaml
---
- name: Synchronize Semaphore Templates
  hosts: privatebox
  gather_facts: no
  
  tasks:
    - name: Update repository
      git:
        repo: https://github.com/Rasped/privatebox.git
        dest: "{{ lookup('env', 'REPO_PATH') | default('/opt/privatebox/repo') }}"
        version: main
      
    - name: Run template sync script
      command: >
        python3 {{ lookup('env', 'REPO_PATH') }}/tools/semaphore-sync.py
      environment:
        SEMAPHORE_URL: "{{ lookup('env', 'SEMAPHORE_URL') }}"
        SEMAPHORE_API_TOKEN: "{{ lookup('env', 'SEMAPHORE_API_TOKEN') }}"
      register: sync_result
      
    - name: Display sync results
      debug:
        var: sync_result.stdout_lines
```

#### The Python Script
`tools/semaphore-sync.py` will:

1. **Discover Playbooks**
   ```python
   playbook_dir = Path(os.environ['REPO_PATH']) / 'ansible' / 'playbooks' / 'services'
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
   
   # Get SSH key ID for "vm-container-host"
   keys = requests.get(f"{api_url}/project/1/keys",
                      cookies={'semaphore': token}).json()
   try:
       key_id = next(k['id'] for k in keys 
                    if k['name'] == 'vm-container-host')
   except StopIteration:
       print(f"ERROR: SSH key 'vm-container-host' not found")
       return
   ```

5. **Create Template**
   ```python
   template_data = {
       'name': f"Deploy: {playbook_name}",
       'project_id': 1,
       'inventory_id': inventory_id,
       'repository_id': repository_id,
       'environment_id': environment_id,
       'key_id': key_id,
       'playbook': f"ansible/playbooks/services/{playbook_file.name}",
       'survey_vars': survey_vars
   }
   
   response = requests.post(f"{api_url}/project/1/templates",
                          json=template_data,
                          cookies={'semaphore': token})
   ```

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
   - Click "Run" on "Sync Templates"
   - View output for results

2. **What Happens**:
   - Repository is updated via git pull
   - All service playbooks are scanned
   - New templates are created
   - Existing templates are skipped
   - Errors are reported but don't stop the process

## Limitations

1. **No Template Updates**: Only creates new templates, doesn't update existing ones
2. **Simple Types Only**: Only supports text, integer, boolean (no arrays/objects)
3. **No Jinja2 Evaluation**: Can't evaluate complex default values with Jinja2
4. **Basic Error Handling**: Skips problematic playbooks with warnings
5. **Fixed Conventions**: Assumes:
   - Inventory named "Default Inventory"
   - SSH key named "vm-container-host"
   - Repository named "PrivateBox"
   - Project ID is always 1

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
✓ Created template: Deploy: Pi-hole
! Skipped: wireguard.yml (Template already exists)

Summary: 2 created, 1 skipped, 1 error
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
1. Ensure `/opt/privatebox/repo` exists and is up-to-date
2. Check git credentials if using private repository
3. Verify network connectivity to GitHub

## Future Enhancements

1. **Update Existing Templates**: Detect changes and update templates
2. **Template Deletion**: Remove templates for deleted playbooks
3. **Complex Types**: Support for lists, dicts in survey variables
4. **Scheduled Sync**: Automatic daily/weekly synchronization
5. **Dry Run Mode**: Preview changes without creating templates
6. **Custom Field Mapping**: Configuration file for type mappings
7. **Validation**: Pre-flight checks for playbook compatibility

## Security Considerations

1. **API Token**: Stored encrypted in Semaphore environment
2. **Repository Access**: Uses HTTPS, no credentials stored
3. **Local Execution**: No external network calls except git pull
4. **Audit Trail**: All actions logged in Semaphore task output