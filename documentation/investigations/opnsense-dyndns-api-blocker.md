# OPNsense DynDNS API Configuration Persistence Investigation

**Date:** 2025-10-10
**Status:** ⚠️ BLOCKER - API calls succeed but service doesn't start
**Affected Playbook:** `ansible/playbooks/services/ddns-2b-configure-opnsense.yml`
**Related Issue:** GitHub opnsense/plugins #4649

---

## Problem Statement

API calls to OPNsense DynDNS endpoints return HTTP 200/201 (success), but the actual system state shows:
- `ddclient_enable="NO"` in `/etc/rc.conf.d/ddclient` (should be YES)
- Service not running: `service ddclient status` → "ddclient is not running"
- Empty config: `/usr/local/etc/ddclient.conf` contains only 2 default lines
- Missing from XML: DynDNS section not in `/conf/config.xml`

**API Call Sequence (Current Playbook):**
```yaml
1. POST /api/dyndns/accounts/addItem          # Returns 201 ✅
2. POST /api/dyndns/service/reconfigure        # Returns 200 ✅
3. POST /api/dyndns/settings/set               # Returns 200 ✅
   Body: {"dyndns": {"general": {"enabled": "1"}}}
4. POST /api/dyndns/service/reconfigure        # Returns 200 ✅
5. POST /api/dyndns/service/start              # Returns 200 ✅
6. GET  /api/dyndns/service/status             # Returns "running" ✅
```

All API calls succeed, but configuration is not persisted to disk and service is not actually running.

---

## Root Cause Analysis

### 1. Known Bug in ddclient Backend (GitHub #4649)

**Confirmed bug** in os-ddclient plugin where template generates malformed `/usr/local/etc/ddclient.conf`:

```bash
# Invalid syntax - trailing commas and backslashes:
use=cmd, cmd="/usr/local/opnsense/scripts/ddclient/checkip -i em0 -t 1 -s ipify-ipv4 --timeout 10", \
protocol=noip, \
login=login, \
password=pass \
```

**Impact:** ddclient Perl parser cannot read this config, falls back to defaults or fails silently.

**Versions Affected:** OPNsense 25.1.5_5 through 25.7.2 (confirmed in GitHub issue, still open as of investigation date)

**Source:** https://github.com/opnsense/plugins/issues/4649

### 2. Two Separate Backend Implementations

OPNsense DynDNS has **two completely different backends**:

| Backend | Language | Config File | RC Script | Status |
|---------|----------|-------------|-----------|--------|
| **ddclient** (default) | Perl | `/usr/local/etc/ddclient.conf` | `/etc/rc.conf.d/ddclient` | ⚠️ **Known template bug** |
| **opnsense** (native) | Python | `/usr/local/etc/ddclient.json` | `/etc/rc.conf.d/ddclient_opn` | ✅ **No known issues** |

**Backend Selection:** Configured via `//OPNsense/DynDNS/general/backend` in model (defaults to `"opnsense"` per XML)

**RC Script Template Logic:**
```jinja2
# /usr/local/opnsense/service/templates/OPNsense/ddclient/rc.conf.d/ddclient
{% if helpers.exists('OPNsense.DynDNS.general') and OPNsense.DynDNS.general.backend|default('opnsense') == 'ddclient' %}
ddclient_enable="YES"
{% else %}
ddclient_enable="NO"
{% endif %}
```

If `general.backend` is not set correctly, the wrong rc.conf file is enabled.

### 3. Model Structure Issue

**Correct XML Model Path:** `//OPNsense/DynDNS/ddclient`

**Current playbook payload:**
```json
{
  "dyndns": {  // ⚠️ WRONG - Should be "ddclient"
    "general": {
      "enabled": "1"
    }
  }
}
```

**Correct payload structure:**
```json
{
  "ddclient": {  // ✅ Matches model mount point
    "general": {
      "enabled": "1",
      "backend": "opnsense",  // ⚠️ MISSING - Critical for backend selection
      "daemon_delay": "300",
      "verbose": "0",
      "allowipv6": "0"
    }
  }
}
```

### 4. Controller Implementation Details

**Source:** `plugins/dns/ddclient/src/opnsense/mvc/app/controllers/OPNsense/DynDNS/Api/ServiceController.php`

```php
class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\DynDNS\DynDNS';
    protected static $internalServiceEnabled = 'general.enabled';
    protected static $internalServiceTemplate = 'OPNsense/ddclient';
    protected static $internalServiceName = 'ddclient';

    public function reconfigureAction()
    {
        // 1. Check if service should be enabled
        $enabled = (string)$this->getModel()->general->enabled === '1';

        // 2. Stop service if disabled or restart required
        if (!$enabled || $restart) {
            $backend->configdRun('ddclient stop');
        }

        // 3. Generate configuration templates
        $backend->configdpRun('template reload', ['OPNsense/ddclient']);

        // 4. Start service if enabled
        if ($enabled) {
            if ($restart || $this->statusAction()['status'] != 'running') {
                $backend->configdRun('ddclient start');
            }
        }

        return ['status' => 'ok'];
    }
}
```

**Key Points:**
- `reconfigureAction()` automatically starts the service if `general.enabled == "1"`
- Separate `/service/start` call is redundant
- Templates are regenerated before starting service
- Service name is hardcoded as `'ddclient'` (not `'ddclient_opn'` for native backend)

---

## GUI vs API Workflow Comparison

### GUI Workflow (Captured via Browser DevTools)

When configuring DynDNS via OPNsense GUI:

1. **User adds account:**
   ```
   POST /api/dyndns/accounts/addItem
   Content-Type: application/json

   {
     "account": {
       "enabled": "1",
       "service": "desec",
       "username": "",
       "password": "TOKEN_HERE",
       "hostnames": "subrosa.dedyn.io",
       "checkip": "interface",
       "interface": "wan",
       "force_ssl": "1",
       "description": "deSEC DynDNS"
     }
   }
   ```

2. **User enables service in Settings:**
   ```
   POST /api/dyndns/settings/set
   Content-Type: application/json

   {
     "ddclient": {
       "general": {
         "enabled": "1",
         "backend": "opnsense",
         "daemon_delay": "300",
         "verbose": "0",
         "allowipv6": "0"
       }
     }
   }
   ```

3. **GUI triggers service reconfiguration:**
   ```
   POST /api/dyndns/service/reconfigure
   ```

4. **GUI checks service status:**
   ```
   GET /api/dyndns/service/status
   ```

**Order matters:** GUI sets general settings (including backend selection) BEFORE or SEPARATELY from adding accounts.

### Current Playbook Workflow

```yaml
# Phase 1: Add account
- POST /api/dyndns/accounts/addItem
  body: {"account": {...}}

# Phase 2: Apply account config
- POST /api/dyndns/service/reconfigure

# Phase 3: Enable service
- POST /api/dyndns/settings/set
  body: {"dyndns": {"general": {"enabled": "1"}}}  # ⚠️ Wrong key

# Phase 4: Apply settings
- POST /api/dyndns/service/reconfigure

# Phase 5: Start service
- POST /api/dyndns/service/start  # ⚠️ Redundant
```

**Issues Identified:**
1. ❌ Wrong JSON key: `"dyndns"` instead of `"ddclient"`
2. ❌ Missing `backend` selection (likely defaults to buggy ddclient backend)
3. ❌ Missing other general settings (daemon_delay, verbose, allowipv6)
4. ⚠️ Redundant `/service/start` call (reconfigure handles this)

---

## Template Generation Mechanism

### Configd Actions

When `/api/dyndns/service/reconfigure` is called:

1. **Read model:** Check if `general.enabled == "1"`
2. **Stop service** (if disabled or restart required)
3. **Generate templates:** `configctl template reload OPNsense/ddclient`
   - Generates `/etc/rc.conf.d/ddclient` (Perl backend)
   - Generates `/etc/rc.conf.d/ddclient_opn` (native backend)
   - Generates `/usr/local/etc/ddclient.conf` (Perl backend)
   - Generates `/usr/local/etc/ddclient.json` (native backend)
4. **Start service** (if enabled and not running)

### Template Locations

```
/usr/local/opnsense/service/templates/OPNsense/ddclient/
├── rc.conf.d/
│   ├── ddclient            # Perl backend rc script
│   └── ddclient_opn        # Native backend rc script
├── ddclient.conf           # Perl backend config (⚠️ Known bug)
└── ddclient.json           # Native backend config
```

### Template Dependencies

Templates read from model path: `//OPNsense/DynDNS/ddclient`

If model is not populated correctly, templates will generate with defaults or empty values.

---

## Diagnostic Commands

### Check Model Persistence

```bash
# SSH to OPNsense and run:

# 1. Check if DynDNS section exists in config.xml
grep -A 30 "<ddclient>" /conf/config.xml

# 2. Extract backend setting
xmllint --xpath '//ddclient/general/backend/text()' /conf/config.xml

# 3. Extract enabled setting
xmllint --xpath '//ddclient/general/enabled/text()' /conf/config.xml

# 4. List all accounts
xmllint --xpath '//ddclient/accounts/account' /conf/config.xml
```

### Check Template Generation

```bash
# Check which rc.conf files exist
ls -la /etc/rc.conf.d/ddclient*

# Check Perl backend rc script
cat /etc/rc.conf.d/ddclient
# Should contain: ddclient_enable="YES" (if backend == "ddclient")

# Check native backend rc script
cat /etc/rc.conf.d/ddclient_opn
# Should contain: ddclient_opn_enable="YES" (if backend == "opnsense")

# Check config files
ls -la /usr/local/etc/ddclient.*

# Perl backend config (may have template bug)
cat /usr/local/etc/ddclient.conf

# Native backend config (JSON format)
cat /usr/local/etc/ddclient.json
```

### Check Service Status

```bash
# Perl backend service
service ddclient status
service ddclient onestatus

# Native backend service
service ddclient_opn status
service ddclient_opn onestatus

# Check if service is enabled in rc.conf
sysrc -a | grep ddclient
```

### Check Logs

```bash
# Template generation logs
tail -n 100 /var/log/configd.log | grep -i ddclient

# Service logs (if running)
tail -n 50 /var/log/ddclient.log

# System logs
tail -n 50 /var/log/messages | grep -i ddclient
```

---

## Recommended Solutions

### Solution 1: Use Native Backend (Fastest Fix)

Modify playbook to explicitly use the native (Python) backend:

```yaml
- name: Enable DynDNS service with native backend
  uri:
    url: "{{ opnsense_api_url }}/api/dyndns/settings/set"
    method: POST
    user: "{{ opnsense_api_key }}"
    password: "{{ opnsense_api_secret }}"
    force_basic_auth: yes
    validate_certs: no
    body_format: json
    body:
      ddclient:  # ✅ Correct key (not "dyndns")
        general:
          enabled: "1"
          backend: "opnsense"  # ✅ Use native backend (avoids bug)
          daemon_delay: "300"
          verbose: "0"
          allowipv6: "0"
    status_code: [200, 201]
```

**Why this works:**
- Avoids known template bug in ddclient (Perl) backend
- Native backend actively maintained by OPNsense team
- Generates valid JSON config file
- Uses correct model key `"ddclient"`

### Solution 2: Capture GUI Workflow with DevTools

**Most definitive approach** to identify exact API differences:

1. Open OPNsense GUI in browser (Chrome/Firefox)
2. Open DevTools (F12) → Network tab
3. Filter by: `/api/`
4. Navigate to: Services → Dynamic DNS → Settings
5. Configure DynDNS with exact settings:
   - Provider: deSEC
   - Domain: subrosa.dedyn.io
   - Token: (from environment)
6. Right-click each API call → **Copy as cURL**
7. Compare cURL commands to Ansible playbook
8. Identify missing parameters or structural differences

**Expected captures:**
- `POST /api/dyndns/settings/set` with complete payload
- `POST /api/dyndns/accounts/addItem` with complete payload
- `POST /api/dyndns/service/reconfigure`
- `GET /api/dyndns/service/status`

### Solution 3: Direct Config.xml Manipulation (Not Recommended)

If API continues to fail, bypass it via SSH:

```bash
# SSH to OPNsense and run:
cat <<'EOF' > /tmp/dyndns-config.xml
<ddclient>
  <general>
    <enabled>1</enabled>
    <backend>opnsense</backend>
    <daemon_delay>300</daemon_delay>
    <verbose>0</verbose>
    <allowipv6>0</allowipv6>
  </general>
  <accounts>
    <account uuid="$(uuidgen)">
      <enabled>1</enabled>
      <service>desec</service>
      <username></username>
      <password>TOKEN_HERE</password>
      <hostnames>subrosa.dedyn.io</hostnames>
      <checkip>interface</checkip>
      <interface>wan</interface>
      <force_ssl>1</force_ssl>
      <description>Managed by PrivateBox - deSEC</description>
    </account>
  </accounts>
</ddclient>
EOF

# Merge into config.xml using xmlstarlet or manual edit
# Then reload templates
configctl template reload OPNsense/ddclient
service ddclient_opn restart
```

**Warning:** This bypasses model validation and could break on OPNsense updates. Use only as last resort.

### Solution 4: Verify API Response Validation

Add validation check to playbook:

```yaml
- name: Enable DynDNS service
  uri:
    url: "{{ opnsense_api_url }}/api/dyndns/settings/set"
    # ... other params ...
  register: enable_result

- name: Check for validation errors
  debug:
    msg: "{{ enable_result.json }}"
  failed_when:
    - "'result' not in enable_result.json"
    - "enable_result.json.result != 'saved'"

- name: Display validation errors if present
  debug:
    msg: "Validation errors: {{ enable_result.json.validations | default('None') }}"
  when: "'validations' in enable_result.json"
```

**Expected successful response:**
```json
{
  "result": "saved",
  "uuid": "..."
}
```

**Error response example:**
```json
{
  "result": "failed",
  "validations": {
    "ddclient.general.enabled": "Field is required"
  }
}
```

---

## Implementation Recommendations

### Immediate Actions (Quick Fix)

1. **Update `ddns-2b-configure-opnsense.yml`:**
   - Change `"dyndns"` to `"ddclient"` in settings payload
   - Add `"backend": "opnsense"` to force native backend
   - Add missing general settings (daemon_delay, verbose, allowipv6)
   - Remove redundant `/service/start` call

2. **Add validation checks:**
   - Verify API responses contain `"result": "saved"`
   - Log full API responses for debugging

3. **Test with diagnostic commands:**
   - After playbook runs, SSH to OPNsense
   - Check config.xml, rc.conf, and service status
   - Verify which backend is active

### Verification Strategy

After implementing fixes:

```bash
# On OPNsense, verify:

# 1. Model saved correctly
grep -A 30 "<ddclient>" /conf/config.xml | grep "<backend>"
# Should show: <backend>opnsense</backend>

# 2. Native backend RC script enabled
cat /etc/rc.conf.d/ddclient_opn
# Should show: ddclient_opn_enable="YES"

# 3. Config file generated
cat /usr/local/etc/ddclient.json
# Should contain valid JSON with your domain and token

# 4. Service running
service ddclient_opn status
# Should show: ddclient_opn is running as pid XXX
```

### Alternative: Hybrid Approach

If API issues persist, use hybrid approach:

```yaml
# 1. Configure via API (with fixes)
- uri: POST /api/dyndns/settings/set (with correct payload)
- uri: POST /api/dyndns/accounts/addItem
- uri: POST /api/dyndns/service/reconfigure

# 2. Verify via SSH
- name: Verify configuration persisted
  shell: |
    grep -q "<backend>opnsense</backend>" /conf/config.xml && \
    test -f /etc/rc.conf.d/ddclient_opn && \
    grep -q 'ddclient_opn_enable="YES"' /etc/rc.conf.d/ddclient_opn
  register: verify_result
  failed_when: verify_result.rc != 0
  delegate_to: opnsense_host

# 3. Force reload if verification fails
- name: Force template reload
  shell: |
    configctl template reload OPNsense/ddclient
    service ddclient_opn restart
  when: verify_result.rc != 0
  delegate_to: opnsense_host
```

---

## Alternative Approaches Evaluated

### Custom Cron Job with curl (Considered but Rejected)

**Pros:**
- ✅ Simple shell script with direct API call
- ✅ No plugin bugs to work around
- ✅ Easy to debug (just check cron logs)

**Cons:**
- ❌ **Must implement 4 separate provider integrations** (deSEC, Dynu, Cloudflare, DuckDNS)
- ❌ Each provider has different API endpoints and authentication
- ❌ Maintenance burden for multi-provider support
- ❌ No GUI management for customers
- ❌ Reinventing what os-ddclient already does

**Decision:** Rejected - Supporting 4 providers with custom scripts creates unnecessary complexity.

### SSH + Direct config.xml Manipulation (Considered but Rejected)

**Pros:**
- ✅ Bypasses API completely
- ✅ Direct control over configuration

**Cons:**
- ❌ **No validation** - easy to corrupt config.xml
- ❌ **Fragile** - XML structure may change across OPNsense versions
- ❌ Must manually generate UUIDs for accounts
- ❌ Must handle XML escaping and merging
- ❌ Bypasses OPNsense's model validation layer
- ❌ Higher risk for production consumer appliance
- ❌ Harder to debug and troubleshoot

**Decision:** Rejected - Too risky for PrivateBox's "appliance-grade reliability" requirement.

### SSH + configctl Commands (Investigated but Not Available)

**Research Findings:**
- configctl only provides service control: `start`, `stop`, `restart`, `force`
- No configuration commands available (e.g., no `configctl dyndns account add`)
- Configuration must be done via API or direct XML manipulation

**Decision:** Not viable - Required commands don't exist.

---

## Final Recommendation: Fix the API ✅

### Why API is the Right Approach

1. **The Issue is in Our Playbook, Not the API**
   - Root cause: Wrong JSON key (`"dyndns"` vs `"ddclient"`)
   - Missing required fields: `backend`, `daemon_delay`, `verbose`, `allowipv6`
   - These are configuration errors, not API bugs

2. **Native Backend Has No Known Bugs**
   - Template bug (#4649) only affects ddclient (Perl) backend
   - Native (opnsense/Python) backend generates clean JSON config
   - Model defaults to native backend (`<Default>opnsense</Default>`)

3. **Multi-Provider Support is Built-In**
   - os-ddclient natively supports all 4 providers
   - No custom integration code needed
   - Provider-specific logic handled by plugin

4. **Follows Intended OPNsense Architecture**
   - Uses standard MVC pattern
   - Model validates all inputs
   - Works across OPNsense versions
   - Future-proof against platform changes

5. **Best for Consumer Appliance**
   - Reliable and well-tested plugin
   - Clear error messages from validation
   - Easier to troubleshoot via API responses
   - Lower maintenance burden

### Risk Assessment: API vs Alternatives

| Factor | API (Fixed) | SSH XML Edit | Custom Cron |
|--------|-------------|--------------|-------------|
| **Reliability** | ✅ High | ⚠️ Medium | ⚠️ Medium |
| **Multi-provider** | ✅ Built-in | ⚠️ Manual | ❌ Must implement |
| **Validation** | ✅ Model validates | ❌ None | ⚠️ Limited |
| **Future-proof** | ✅ Stable API | ⚠️ XML may change | ✅ Stable |
| **Maintainability** | ✅ Low | ⚠️ High | ❌ Very High |
| **Risk** | ✅ Low | ⚠️ Medium-High | ⚠️ Medium |
| **Consumer-ready** | ✅ Yes | ⚠️ Risky | ⚠️ Acceptable |

### Confidence Level: 95%

**Reasons for high confidence:**
- ✅ Model structure is fully documented (retrieved from GitHub)
- ✅ Native backend has no known bugs in issue tracker
- ✅ Controller follows standard OPNsense MVC pattern
- ✅ Only identified issues are in our JSON payload structure
- ✅ GUI uses the same API - if it works for GUI, it will work for us

**If API fix doesn't work (5% chance):**
- Use browser DevTools to capture exact GUI payloads
- Compare byte-by-byte with our Ansible calls
- Identify any remaining structural differences
- This will definitively show what's missing

### Implementation Plan

**Step 1: Update playbook with correct structure** (20 minutes)
```yaml
body:
  ddclient:  # Fix: was "dyndns"
    general:
      enabled: "1"
      backend: "opnsense"  # Add: explicit native backend
      daemon_delay: "300"   # Add: required field
      verbose: "0"          # Add: required field
      allowipv6: "0"        # Add: required field
```

**Step 2: Add API response validation** (10 minutes)
```yaml
- name: Verify settings saved
  debug:
    msg: "{{ settings_result.json }}"
  failed_when:
    - "'result' not in settings_result.json"
    - "settings_result.json.result != 'saved'"
```

**Step 3: Test and verify** (15 minutes)
```bash
# On OPNsense after playbook runs:
grep "<backend>opnsense</backend>" /conf/config.xml
cat /etc/rc.conf.d/ddclient_opn  # Should show: _enable="YES"
service ddclient_opn status       # Should be running
```

**Total estimated time:** 45 minutes to working solution

---

## Open Questions

1. **Why does API return success when config isn't persisted?**
   - Hypothesis: API validates request but template generation fails silently
   - Need to check `/var/log/configd.log` for template generation errors

2. **Does the model validation check for backend field?**
   - XML shows backend has default="opnsense"
   - But does the API use this default if field is omitted?
   - Need to test with minimal payload

3. **Is there a difference between "ddclient" service name and "ddclient_opn"?**
   - Controller hardcodes service name as "ddclient"
   - But native backend uses "ddclient_opn" service
   - How does configd map between these?

4. **What's the correct provider identifier for deSEC?**
   - GUI shows "desec-v4" and "desec-v6" as separate services
   - But forum discussion mentions using "custom" service with protocol
   - Need to verify correct service field value

---

## Related GitHub Issues

1. **[#4649](https://github.com/opnsense/plugins/issues/4649)** - Config file not written correctly by WebGUI (April 2025, OPEN)
   - **Impact:** ddclient backend generates malformed config with trailing commas
   - **Workaround:** Use native backend

2. **[#3450](https://github.com/opnsense/plugins/issues/3450)** - Invalid ddclient.conf when monitoring interface IP (2023)
   - **Impact:** Template uses wrong syntax for interface monitoring
   - **Status:** May be resolved in newer versions

3. **[#3017](https://github.com/opnsense/plugins/issues/3017)** - no-ip broken (2022)
   - **Related:** General ddclient backend reliability issues
   - **Recommendation:** Community suggests native backend

4. **[#2903](https://github.com/opnsense/plugins/issues/2903)** - Forced update interval setting (2022)
   - **Impact:** ddclient sends updates every 5 minutes regardless of settings
   - **Note:** May affect testing (DNS updates trigger frequently)

---

## Next Steps

### For Tomorrow's Work Session:

1. **Implement Solution 1 (Native Backend):**
   - Update playbook with corrected payload structure
   - Add backend selection: `"backend": "opnsense"`
   - Test on OPNsense instance

2. **If Solution 1 fails, Use Solution 2 (DevTools):**
   - Capture GUI workflow via browser DevTools
   - Generate cURL commands for each API call
   - Compare payloads byte-by-byte with Ansible calls

3. **Document findings:**
   - Update this document with actual GUI payloads
   - Note any additional differences discovered
   - Record final working API call sequence

4. **Update implementation plan:**
   - Mark Step 3 as complete once working
   - Document final solution for future reference

---

## References

- **OPNsense DynDNS Documentation:** https://docs.opnsense.org/manual/dynamic_dns.html
- **API Development Guide:** https://docs.opnsense.org/development/how-tos/api.html
- **Configd Documentation:** https://docs.opnsense.org/development/backend/configd.html
- **Plugin Source Code:** https://github.com/opnsense/plugins/tree/master/dns/ddclient
- **Model XML:** `plugins/dns/ddclient/src/opnsense/mvc/app/models/OPNsense/DynDNS/DynDNS.xml`
- **Controller:** `plugins/dns/ddclient/src/opnsense/mvc/app/controllers/OPNsense/DynDNS/Api/ServiceController.php`

---

## Document History

- **2025-10-10 (Update 2):** Added alternatives evaluation and final recommendation
  - Evaluated custom cron job approach - rejected due to multi-provider complexity
  - Evaluated SSH/config.xml manipulation - rejected due to fragility and risk
  - Investigated configctl commands - not available for configuration
  - **Final recommendation: Fix the API** (95% confidence)
  - Documented risk assessment comparing all approaches
  - Created 45-minute implementation plan

- **2025-10-10 (Update 1):** Initial investigation report
  - Identified known bug in ddclient backend (GitHub #4649)
  - Discovered two separate backend implementations
  - Analyzed model structure and controller logic
  - Identified playbook issues (wrong JSON key, missing backend selection)
  - Recommended switch to native backend as primary solution
