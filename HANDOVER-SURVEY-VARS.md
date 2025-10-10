# Handover: Survey Variables Support

## Task: Add survey_vars to generate-templates.py

Problem: Script only reads old vars_prompt format, ignores pre-formatted survey_vars in template_config.

## Context

Playbook ddns-1-setup-environment.yml converted to use Semaphore survey_vars (committed 6e6909d):
- Removed 58 lines of vars_prompt
- Added semaphore_survey_vars to template_config (lines 16-50)
- 5 variables: dns_provider (enum/dropdown), dns_api_token (secret), ddns_domain (text), letsencrypt_email (text), cloudflare_zone_id (text optional)
- Template regenerated but shows survey_vars: null

## Requirements

**File:** `tools/generate-templates.py`

### Change 1: parse_playbook() function (line 221+)

After line 237 (getting vars_section), add:
```python
# Check for pre-formatted survey vars in template_config
template_config = vars_section.get('template_config', {})
if 'semaphore_survey_vars' in template_config:
    survey_vars = template_config['semaphore_survey_vars']
    return {
        'name': play.get('name', 'Unnamed playbook'),
        'hosts': hosts,
        'survey_vars': survey_vars,
        'template_config': template_config
    }
```

Keep existing vars_prompt logic as fallback.

### Change 2: create_or_update_template() function (line 341+)

Replace line 349:
```python
# OLD
survey_vars = convert_to_survey_vars(playbook_info['vars'])

# NEW
survey_vars = playbook_info.get('survey_vars') or convert_to_survey_vars(playbook_info.get('vars', []))
```

## Testing

1. Commit + push changes
2. Regenerate templates via Semaphore
3. Check template 16:
   ```bash
   ssh root@192.168.1.10 "curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/1/templates/16 | jq '.survey_vars'"
   ```
4. Open Semaphore UI → run template 16 → verify dropdown appears

## Success Criteria

- Template API returns 5 survey_vars (not null)
- DNS Provider shows as dropdown with 4 options
- API Token shows as password field
- Required fields marked correctly

## Files

- `tools/generate-templates.py` (needs update)
- `ansible/playbooks/services/ddns-1-setup-environment.yml` (reference, already done)
- Cookie: `/tmp/sem.cookies` on Proxmox
- Semaphore: https://10.10.20.10:2443 (from Proxmox only)
- Template ID: 16

## Credentials

**Semaphore Access (from workstation):**
```bash
# SSH tunnel to Semaphore UI
ssh -L 2443:10.10.20.10:2443 root@192.168.1.10 -N

# Then browse to: https://localhost:2443
# Username: admin
# Password: handw0rK-cri3r-aRRiv4l
```

**Proxmox SSH:**
- Host: `root@192.168.1.10`
- SSH key authentication (no password needed)

**Test deSEC Credentials (for testing after implementation):**
- Provider: desec
- API Token: KpfDergffMuoLNRcNzHY3xXBvSfy
- Domain: subrosa.dedyn.io
- Email: rasped@gmail.com
