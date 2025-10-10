# Dynamic DNS + Let's Encrypt Implementation Plan

## Overview

Enable custom domain support with automatic DynDNS updates and Let's Encrypt certificates while maintaining existing `.lan` domain functionality.

**Key Principles:**
- No additional OPNsense ports exposed (access via Tailscale VPN only)
- DNS-01 challenge for Let's Encrypt (no HTTP-01, no port 80 exposure)
- Dual-domain support: `.lan` (self-signed) + custom domain (Let's Encrypt)
- All services remain on Management VM (10.10.20.10)

---

## Architecture

### Current State
- Services: `portainer.lan`, `semaphore.lan`, `adguard.lan`, etc.
- Caddy: Self-signed certificates
- AdGuard: DNS rewrites for `*.lan` → `10.10.20.10`
- Access: Internal only

### Target State
- Services accessible via BOTH:
  - `*.lan` → `10.10.20.10` (self-signed cert)
  - `*.customer.dedyn.io` → `10.10.20.10` (Let's Encrypt cert)
- OPNsense: Updates DynDNS record when WAN IP changes
- AdGuard: Rewrites for both domains → `10.10.20.10`
- External users: Connect via Tailscale → resolve custom domain internally
- Valid certificates: No browser warnings

---

## Marketing & User Guidance

**Primary Recommendation: deSEC**

PrivateBox actively recommends **deSEC** as the default DNS provider for the following reasons:

1. **European Values Alignment:**
   - German non-profit foundation (deSEC e.V.)
   - GDPR-compliant by design, no user tracking
   - Data sovereignty (servers in EU)
   - Transparent, open-source philosophy

2. **Superior Security:**
   - DNSSEC enabled by default (not optional)
   - Protection against DNS spoofing/cache poisoning
   - Cryptographic authentication of DNS responses

3. **No Lock-in:**
   - Free subdomains (e.g., `yourname.dedyn.io`)
   - No expiration, no renewal hassles
   - Standard RFC2136 support (portable)

4. **Perfect for Privacy-Conscious Consumers:**
   - Aligns with PrivateBox's "no cloud dependencies" promise
   - No commercial interests or data monetization
   - Community-driven development

**Alternative Options:**

- **Dynu**: Strong alternative with fastest updates (30s TTL) and global distribution
- **Cloudflare**: For technical users who already own domains
- **DuckDNS**: Supported for compatibility (existing users only, not recommended for new setups)

**In Documentation/UI:**
> "PrivateBox recommends **deSEC**, a European non-profit DNS provider with built-in DNSSEC security. **Dynu** is an excellent alternative. We also support Cloudflare (own domain) and DuckDNS (compatibility only)."

**Provider Comparison:**

| Feature | deSEC ⭐ | Dynu | DuckDNS | Cloudflare |
|---------|---------|------|---------|------------|
| **Cost** | Free | Free | Free | Free (domain not included) |
| **Location** | 🇪🇺 Germany | 🌍 Global (US-based) | 🇦🇺 AWS (Sydney) | 🇺🇸 USA |
| **Privacy** | ✅ Non-profit, no tracking | ✅ No ads/tracking | ⚠️ AWS-hosted | ⚠️ Commercial CDN |
| **DNSSEC** | ✅ Default | ❌ Not available | ❌ Not available | ✅ Available |
| **GDPR** | ✅ Compliant by design | ⚠️ No EU servers | ⚠️ AWS DPA | ✅ Compliant |
| **Renewal** | ✅ Never | ✅ Never | ✅ Never | ✅ Never |
| **TTL** | 60s | **30s** (fastest) | 60s | Variable |
| **Subdomains** | ✅ Free `.dedyn.io` | ✅ Free `.dynu.com` | ✅ Free `.duckdns.org` | ❌ Own domain required |
| **OPNsense** | ✅ Native (via RFC2136) | ✅ Native (22.7+) | ✅ Native | ✅ Native |
| **Caddy Plugin** | ✅ Official | ✅ Official | ✅ Official | ✅ Official |
| **Best For** | Privacy, security | Speed, reliability | Simplicity | Power users |

---

## Implementation Steps

### 1. Caddy DNS Plugins - ✅ ALREADY COMPLETE

**Status:** Caddy installation already includes DNS plugin support for all 4 providers.

**Supported Providers:**
```
- caddy-dns/desec       # PRIMARY: deSEC (EU-based, GDPR, non-profit, DNSSEC)
- caddy-dns/dynu        # SECONDARY: Dynu (free forever, 30s TTL, global network)
- caddy-dns/cloudflare  # POWER USERS: Cloudflare (own domain, enterprise-grade)
- caddy-dns/duckdns     # COMPATIBILITY: DuckDNS (option for existing users, not recommended)
```

**No action required** - proceed directly to Step 2.

---

### 2. DynamicDNS Semaphore Environment - ✅ ALREADY COMPLETE

**Status:** Environment ID 8 created successfully via playbook `ddns-1-setup-environment.yml` (Template 16).

**Current Configuration:**
- Provider: deSEC
- Domain: subrosa.dedyn.io
- Email: rasped@gmail.com
- API Token: Stored securely in Semaphore environment
- Test Status: API connectivity verified (1 domain found)

**No action required** - environment ready for use by subsequent playbooks.

---

### 3. OPNsense DynDNS Configuration - **⚠️ BLOCKED**

**Status:** API calls succeed but service does not start. Configuration not persisted.

**Objective:** Configure OPNsense to update DNS records when WAN IP changes.

**Playbooks:**
- `ansible/playbooks/services/ddns-2a-prepare-config.yml` ✅ Working
- `ansible/playbooks/services/ddns-2b-configure-opnsense.yml` ⚠️ Blocked

**Implementation Approach:**
Two-playbook handoff pattern (required because Semaphore templates can only reference one environment):
1. **Playbook 2a**: Reads DNS credentials from `DynamicDNS` environment, writes to `/tmp/ddns-handoff.json`
2. **Playbook 2b**: Reads handoff file, uses `OPNsenseAPI` environment to configure OPNsense, deletes handoff

**Current API Call Sequence (Playbook 2b):**
```yaml
1. POST /api/dyndns/accounts/addItem          # Add DynDNS account ✅
2. POST /api/dyndns/service/reconfigure        # Apply account config ✅
3. POST /api/dyndns/settings/set               # Enable service ✅
   Body: {"dyndns": {"general": {"enabled": "1"}}}
4. POST /api/dyndns/service/reconfigure        # Apply settings ✅
5. POST /api/dyndns/service/start              # Start service ✅
6. GET  /api/dyndns/service/status             # Check status ✅ Returns "running"
```

**The Problem:**
All API calls return HTTP 200/201 (success), but actual OPNsense system state shows:
- `ddclient_enable="NO"` in `/etc/rc.conf.d/ddclient` (should be YES)
- `service ddclient status` → "ddclient is not running"
- `/usr/local/etc/ddclient.conf` → only 2 default lines (no account configuration)
- DynDNS section missing from `/conf/config.xml`

**Root Cause Analysis:**
- API returns success codes but does not persist configuration to disk
- `settings/set` with `enabled: "1"` does not update rc.conf
- `service/reconfigure` does not generate ddclient configuration file
- `service/start` claims success but service not actually running
- Configuration exists only in memory, lost on reboot

**Attempted Fixes:**
1. ✅ Added `/api/dyndns/settings/set` with `enabled: "1"` (based on DynDNS.xml model)
2. ✅ Added reconfigure call after account creation (standard OPNsense API pattern)
3. ✅ Added reconfigure call after settings enable (apply changes pattern)
4. ❌ None of these fixed the issue

**Next Investigation Steps:**
1. Test configuration via OPNsense GUI to capture browser network requests
2. Check if API requires additional parameters (savepoint mechanism?)
3. Verify os-ddclient plugin is fully installed and configured
4. Check configd actions for DynDNS service triggers
5. Consider alternative: direct SSH to OPNsense with CLI commands instead of API

**Commits:**
- `8a0ba92`: Add settings/set to enable service before start
- `acd54e5`: Add reconfigure after account creation

**Provider Notes:**
- **deSEC**: Supports RFC2136 (DNS UPDATE) or HTTPS API, DNSSEC enabled
- **Dynu**: RESTful API with OAuth/Bearer token, native OPNsense support
- **DuckDNS**: Simple HTTPS GET request, minimal configuration
- **Cloudflare**: Robust API, requires zone_id + api_token

---

### 4. AdGuard DNS Rewrites

**Objective:** Add DNS rewrites for custom domain while preserving `.lan` rewrites.

**Playbook:** `ansible/playbooks/services/ddns-3-configure-adguard.yml`

**vars_prompt:**
```yaml
- domain         # e.g., "customer.dedyn.io"
- services_list  # Default: [portainer, semaphore, adguard, headplane, homer]
```

**Tasks:**
1. Retrieve AdGuard credentials from ServicePasswords environment
2. For each service in services_list:
   - Add DNS rewrite: `{service}.{domain}` → `10.10.20.10`
   - Example: `portainer.customer.dedyn.io` → `10.10.20.10`
3. Verify rewrites via AdGuard API GET `/control/rewrite/list`
4. Test DNS resolution for one service

**AdGuard API:**
- Endpoint: `POST https://10.10.20.10:3443/control/rewrite/add`
- Auth: HTTP Basic Auth (username: `admin`, password: `SERVICES_PASSWORD`)
- Payload: `{"domain": "portainer.customer.dedyn.io", "answer": "10.10.20.10"}`

**Note:** Existing `.lan` rewrites remain unchanged.

---

### 5. Caddy Let's Encrypt Configuration

**Objective:** Update Caddy to obtain Let's Encrypt certificates via DNS-01 challenge.

**Playbook:** `ansible/playbooks/services/ddns-4-configure-caddy-letsencrypt.yml`

**vars_prompt:**
```yaml
- domain        # e.g., "customer.dedyn.io"
- dns_provider  # Must match DynamicDNS environment
```

**Configuration Strategy:**
Use Caddy `import` directive to keep custom domain config separate from base template.

**Main Caddyfile:**
```caddyfile
# Existing .lan domains (self-signed)
*.lan {
    tls internal
    # ... existing config
}

# Import custom domain config
import /etc/caddy/custom-domains.conf
```

**Custom Domain Config:** `/etc/caddy/custom-domains.conf`
```caddyfile
# Generated by configure-caddy-letsencrypt.yml
*.customer.dedyn.io {
    tls {
        dns desec {env.DNS_API_TOKEN}
    }

    @portainer host portainer.customer.dedyn.io
    handle @portainer {
        reverse_proxy localhost:9443
    }

    @semaphore host semaphore.customer.dedyn.io
    handle @semaphore {
        reverse_proxy localhost:2443
    }

    # ... other services
}
```

**Tasks:**
1. Read DNS API token from DynamicDNS environment
2. Write DNS credentials to `/etc/privatebox/ddns-config.env`
3. Generate custom-domains.conf from template
4. Validate Caddy config: `caddy validate --config /etc/caddy/Caddyfile`
5. Reload Caddy: `systemctl reload caddy`
6. Wait for certificate issuance (up to 60 seconds)
7. Verify certificate via: `curl -vI https://portainer.customer.dedyn.io`
8. Check certificate issuer is Let's Encrypt

**Environment Variables:**
```bash
# /etc/privatebox/ddns-config.env
DNS_PROVIDER=desec
DNS_API_TOKEN=xxx
DDNS_DOMAIN=customer.dedyn.io
LETSENCRYPT_EMAIL=admin@example.com
```

**Caddy Systemd Service:**
```ini
[Service]
EnvironmentFile=/etc/privatebox/ddns-config.env
```

**Error Handling:**
- DNS validation failures → clear error message, suggest DNS propagation wait
- Rate limit hit → recommend Let's Encrypt staging environment first
- Invalid credentials → verify DynamicDNS environment

---

### 6. Verification & Testing

**Objective:** Verify complete setup works end-to-end.

**Playbook:** `ansible/playbooks/services/ddns-5-verify-setup.yml` (optional)

**Tests:**
1. **DNS Resolution:**
   - Query `portainer.lan` → returns `10.10.20.10`
   - Query `portainer.customer.dedyn.io` → returns `10.10.20.10` (internal)
   - Query `customer.dedyn.io` → returns WAN IP (external)

2. **Certificate Verification:**
   - Check `.lan` cert is self-signed
   - Check custom domain cert is from Let's Encrypt
   - Verify cert expiry > 60 days

3. **Service Access:**
   - Access `https://portainer.lan` (self-signed warning expected)
   - Access `https://portainer.customer.dedyn.io` (valid cert, no warning)

4. **DynDNS Updates:**
   - Check OPNsense DynDNS service status
   - Verify last update timestamp
   - Verify current DNS record matches WAN IP

**Manual Verification:**
```bash
# Test DNS rewrites
dig @10.10.20.10 portainer.lan
dig @10.10.20.10 portainer.customer.dedyn.io

# Test certificate
openssl s_client -connect portainer.customer.dedyn.io:443 -servername portainer.customer.dedyn.io < /dev/null 2>/dev/null | openssl x509 -noout -issuer -dates

# Test Caddy config
caddy validate --config /etc/caddy/Caddyfile

# Check OPNsense DynDNS status
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" https://10.10.20.1/api/dyndns/status
```

---

## Playbook Execution Order

**Completed:**
- ✅ Step 1: Caddy DNS plugins (already installed)
- ✅ Step 2: DynamicDNS environment (Environment ID 8, domain: subrosa.dedyn.io)

**Remaining - From Semaphore, user runs:**

```
3. ddns-2-configure-opnsense.yml       # Enable DynDNS in OPNsense
4. ddns-3-configure-adguard.yml        # Add DNS rewrites for custom domain
5. ddns-4-configure-caddy-letsencrypt.yml  # Update Caddy, obtain Let's Encrypt certs
6. ddns-5-verify-setup.yml             # (Optional) Verify everything works
```

**Initial Run:** Use Let's Encrypt staging environment to avoid rate limits.

**Production Run:** Switch to production Let's Encrypt after successful staging test.

---

## Error Handling & Rollback

### Common Issues

**DNS Propagation Delays:**
- Wait 5-10 minutes after OPNsense DynDNS update
- Retry DNS-01 challenge if initial attempt fails
- Add retry logic with exponential backoff

**Let's Encrypt Rate Limits:**
- Use staging environment first (unlimited)
- Production: 50 certs/week per domain
- Monitor cert requests, alert before limit

**Caddy Config Errors:**
- Always validate before reload
- Keep backup of working config
- Rollback on validation failure

**Certificate Renewal Failures:**
- Caddy auto-renews 30 days before expiry
- Monitor cert expiry dates
- Alert if renewal fails

### Rollback Strategy

**If Caddy config fails:**
1. Restore previous Caddyfile
2. Delete `/etc/caddy/custom-domains.conf`
3. Reload Caddy with original config

**If DNS rewrites break:**
1. Remove custom domain rewrites via AdGuard API
2. Verify `.lan` rewrites still work
3. Investigate and fix, then re-run playbook

**If OPNsense DynDNS fails:**
1. Disable DynDNS service
2. Manual DNS record update (if needed)
3. Debug and re-enable

---

## Security Considerations

1. **No Additional Port Exposure:**
   - DNS-01 validation via API (no inbound connections)
   - Services remain internal-only
   - External access only via Tailscale VPN

2. **Credential Storage:**
   - DNS API tokens stored in Semaphore (encrypted)
   - Never logged or displayed in playbook output
   - Deleted from filesystem after use

3. **Certificate Security:**
   - Let's Encrypt provides trusted certificates
   - Auto-renewal prevents expiry
   - Private keys stored securely on Management VM

4. **DNS Security:**
   - AdGuard filters ads/trackers for both domains
   - Split-horizon DNS (internal IPs not exposed publicly)
   - DNSSEC validation (if supported by provider)

---

## Future Enhancements

1. **Multi-Domain Support:**
   - Support multiple custom domains per installation
   - Example: `work.customer1.dedyn.io` + `home.customer2.dedyn.io`

2. **Wildcard Certificate Optimization:**
   - Single wildcard cert for `*.customer.dedyn.io`
   - Reduces Let's Encrypt API calls

3. **Certificate Monitoring:**
   - Automated expiry checks
   - Alerts 30 days before expiry
   - Dashboard widget for cert status

4. **Provider-Specific Optimizations:**
   - **deSEC**: RFC2136 integration for faster updates, DNSSEC validation monitoring
   - **Dynu**: Leverage 30s TTL for near-instant failover scenarios
   - **DuckDNS**: IPv6 support integration
   - **Cloudflare**: Proxy mode options, WAF rules, page rules

5. **Automated Testing:**
   - Nightly DNS resolution tests
   - Certificate validity checks
   - DynDNS update verification

---

## Prerequisites

### Bootstrap Must Include:
- Network access for Let's Encrypt API
- DNS provider account with API access

### User Must Provide:
- ✅ Custom domain (subrosa.dedyn.io - already configured)
- ✅ DNS provider API credentials (deSEC - already stored in Environment ID 8)
- ✅ Email for Let's Encrypt notifications (rasped@gmail.com - already configured)

### Existing Infrastructure:
- ✅ Caddy DNS plugins (deSEC, Dynu, Cloudflare, DuckDNS)
- ✅ OPNsense API credentials (already configured)
- ✅ AdGuard API access (via SERVICES_PASSWORD)
- ✅ Semaphore API access (for environment creation)
- ✅ Caddy reverse proxy (base installation)
- ✅ DynamicDNS environment (Environment ID 8)

---

## Testing Strategy

### Staging Environment
1. Use Let's Encrypt staging: `https://acme-staging-v02.api.letsencrypt.org/directory`
2. Test complete flow with dummy domain
3. Verify all playbooks run without errors
4. Check certificates issued (even if untrusted staging certs)

### Production Rollout
1. Run on test instance first
2. Verify with single service (e.g., Portainer)
3. Expand to all services
4. Monitor for 48 hours
5. Document any issues

### Regression Testing
- Verify `.lan` domains still work
- Check existing services unaffected
- Test VPN connectivity
- Validate AdGuard filtering still active

---

## Documentation Updates

After implementation:
1. Update `CLAUDE.md` with DynDNS architecture
2. Create user guide: "Setting Up Custom Domains"
3. Add troubleshooting section for common issues
4. Update network diagram with DNS flow
5. Document provider-specific setup steps

---

## Success Criteria

✅ DynDNS updates WAN IP automatically
✅ Let's Encrypt certificates issued and auto-renew
✅ Both `.lan` and custom domains work
✅ No browser certificate warnings on custom domain
✅ No additional OPNsense ports exposed
✅ All existing functionality preserved
✅ Playbooks are idempotent and can be re-run safely
