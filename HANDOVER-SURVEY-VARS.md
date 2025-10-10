# Survey Variables Support - COMPLETED ✅

## Status: Implementation Complete and Verified

**Completed:** 2025-10-10
**Commits:** df5771e, 717c0c4, 823df90

Survey variables feature is fully implemented and working. Template 16 (DynDNS 1: Setup Environment) successfully tested with dropdown selector and all form controls.

## Problem Solved

Script only read old vars_prompt format, ignoring pre-formatted survey_vars in template_config. Now supports both formats with proper priority.

## Implementation Summary

**File:** `tools/generate-templates.py`

### Change 1: parse_playbook() - Early Return for Pre-formatted Survey Vars (df5771e)

Added check after line 239 to detect and use pre-formatted `semaphore_survey_vars`:
```python
# Check for pre-formatted survey vars in template_config
template_config = vars_section.get('template_config', {})
if 'semaphore_survey_vars' in template_config:
    survey_vars = template_config['semaphore_survey_vars']
    hosts = play.get('hosts', 'all')
    return {
        'name': play.get('name', 'Unnamed playbook'),
        'hosts': hosts,
        'survey_vars': survey_vars,
        'template_config': template_config
    }
```

Existing vars_prompt logic remains as fallback for 15 legacy playbooks.

### Change 2: create_or_update_template() - Fallback Chain (df5771e)

Updated line 362 to handle both formats:
```python
# Use pre-formatted survey_vars if present, otherwise convert vars_prompt
survey_vars = playbook_info.get('survey_vars') or convert_to_survey_vars(playbook_info.get('vars', []))
```

### Change 3: display_playbook_info() - Handle Both Formats (717c0c4)

Fixed KeyError when displaying playbooks with new format:
```python
# Handle pre-formatted survey_vars (new format)
if 'survey_vars' in info and info['survey_vars']:
    print(f"   Survey variables (pre-formatted): {len(info['survey_vars'])} variable(s)")
# Handle legacy vars_prompt conversion (old format)
elif 'vars' in info and info['vars']:
    # ... existing detailed display ...
```

## Additional Fix: deSEC API Endpoint (823df90)

**File:** `ansible/playbooks/services/ddns-1-setup-environment.yml`

Fixed API connectivity test that was failing with 405 Method Not Allowed:
```yaml
# OLD (line 154)
url: "https://desec.io/api/v1/auth/"

# NEW
url: "https://desec.io/api/v1/domains/"
```

The `/auth/` endpoint only accepts POST (for login). The `/domains/` endpoint properly tests token validity by listing domains.

## Verification Results ✅

**Template API Check:**
```bash
curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/1/templates/16 | jq '.survey_vars'
```
Returns 5 properly formatted survey variables:
- ✅ dns_provider: enum type with 4 dropdown options
- ✅ dns_api_token: secret type (password field)
- ✅ ddns_domain: text type, required
- ✅ letsencrypt_email: text type, required
- ✅ cloudflare_zone_id: text type, optional

**End-to-End Test (Task 2147483623):**
- ✅ Dropdown displayed correctly in Semaphore UI
- ✅ Selected "deSEC" provider from enum dropdown
- ✅ All form controls rendered properly (password field, text fields)
- ✅ deSEC API authentication successful (1 domain found)
- ✅ DynamicDNS environment created (ID: 8)
- ✅ Credentials stored securely
- ✅ Task completed successfully

**Backwards Compatibility:**
- ✅ All 15 existing playbooks with vars_prompt continue working
- ✅ Template generation successful for all playbooks
- ✅ No breaking changes

## Modified Files

- ✅ `tools/generate-templates.py` - Survey vars support (3 functions modified)
- ✅ `ansible/playbooks/services/ddns-1-setup-environment.yml` - deSEC API endpoint fix

## Architecture Notes

**Two-Path System:**
1. **New format:** Playbooks with `semaphore_survey_vars` in `template_config` → used directly
2. **Legacy format:** Playbooks with `vars_prompt` → converted via `convert_to_survey_vars()`

**Priority:** Pre-formatted survey_vars checked first, then falls back to vars_prompt conversion.

**Migration:** Playbooks can be migrated to new format when enum/dropdown controls are needed. Simple playbooks can stay with vars_prompt indefinitely.

## For Future Reference

### Access Information

**Semaphore Web UI (from workstation):**
```bash
# SSH tunnel to access Semaphore UI
ssh -L 2443:10.10.20.10:2443 root@192.168.1.10 -N

# Browse to: https://localhost:2443
# Username: admin
# Password: handw0rK-cri3r-aRRiv4l
```

**Semaphore API (from Proxmox):**
```bash
# Cookie stored at: /tmp/sem.cookies
# Check if valid:
curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/user | grep -q '"admin":true' && echo VALID

# Check template 16 survey_vars:
curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/1/templates/16 | jq '.survey_vars'
```

**Proxmox SSH:**
- Host: `root@192.168.1.10`
- SSH key authentication (no password needed)

### How to Create Playbooks with Survey Variables

**Example structure in playbook YAML:**
```yaml
vars:
  template_config:
    semaphore_environment: "SemaphoreAPI"
    semaphore_inventory: "localhost"
    semaphore_survey_vars:
      - name: "variable_name"
        title: "Human Readable Title"
        description: "Help text for user"
        type: "enum"              # Types: "", "enum", "secret", "int"
        required: true
        values:                   # Only for enum type
          - name: "Display Text"
            value: "actual_value"
      - name: "another_var"
        title: "Password Field"
        type: "secret"            # Renders as password field
        required: true

  # Load variables from environment
  variable_name: "{{ lookup('env', 'variable_name') }}"
  another_var: "{{ lookup('env', 'another_var') }}"
```

**Available types:**
- `""` (empty string) - Text input
- `"enum"` - Dropdown selector (requires `values` list)
- `"secret"` - Password field (masked input)
- `"int"` - Integer input with optional min/max

### Test Credentials (DynamicDNS environment created)

**Provider:** deSEC
**API Token:** KpfDergffMuoLNRcNzHY3xXBvSfy
**Domain:** subrosa.dedyn.io
**Email:** rasped@gmail.com
**Environment ID:** 8 (in Semaphore)
