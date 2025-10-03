# Headplane Deployment Plan

**Status**: Ready for Implementation
**Created**: 2025-10-03
**Prerequisites**: ✅ Completed (Headscale API key generation added)

## Overview

Deploy Headplane web UI for Headscale VPN control server. Headplane provides a modern, feature-complete web interface for managing Headscale nodes, users, routes, and ACLs.

**Container Image**: `ghcr.io/tale/headplane:latest`
**Port**: 8083 (internal 3000)
**Integration Mode**: Docker (recommended)

---

## Research Findings

### Configuration Method (v0.5+)
- **Primary**: YAML config file at `/etc/headplane/config.yaml`
- **Override**: Environment variables (requires `HEADPLANE_LOAD_ENV_OVERRIDES=true`)
- **Data Storage**: `/var/lib/headplane`

### Integration Modes
1. **Docker Integration** (RECOMMENDED)
   - Auto-discovers Headscale container
   - Manages DNS automatically
   - Full feature set
   - Requires: Docker socket mount, same network as Headscale

2. **Simple Mode** (NOT RECOMMENDED)
   - Manual configuration only
   - Limited features

### Authentication Options
1. **API Key** (simplest) - Use Headscale API key
2. **OIDC** (optional) - SSO with Google/Authelia/etc.

**Recommendation**: Start with API key only, add OIDC later if needed.

---

## Prerequisites

### ✅ Completed
1. **Headscale API Key Generation**
   - Added to `headscale-deploy.yml` (commit 74e08ab)
   - Generates 999-day API key
   - Saves to `/opt/privatebox/headscale-api-key.txt` (mode 0600)
   - Available for Headplane to use

2. **Port Allocation**
   - 8080: AdGuard
   - 8081: Homer
   - 8082: Headscale
   - 8083: **AVAILABLE for Headplane** ✅

3. **Headscale User**
   - Created during Headscale deployment
   - Default: `admin`

### ⏳ To Be Generated During Headplane Deployment
1. **Cookie Secret** (32 characters exactly)
   ```bash
   openssl rand -base64 32 | head -c 32
   ```

2. **Config Directory**
   - `/opt/privatebox/config/headplane/` (matches pattern)

---

## Minimal Configuration

### config.yaml Structure
```yaml
server:
  host: "0.0.0.0"
  port: 3000
  cookie_secret: "<32-char-secret-generated-during-deployment>"
  cookie_secure: false  # true for HTTPS in production

headscale:
  url: "http://10.10.20.10:8082"  # Headscale URL on Services VLAN
  api_key: "<read-from-/opt/privatebox/headscale-api-key.txt>"

integration:
  docker:
    enabled: true
    socket: "/var/run/docker.sock"
```

### Environment Variables (Alternative)
If using env vars instead of config file:
```bash
HEADPLANE_SERVER__HOST=0.0.0.0
HEADPLANE_SERVER__PORT=3000
HEADPLANE_SERVER__COOKIE_SECRET=<32-char-secret>
HEADPLANE_HEADSCALE__URL=http://10.10.20.10:8082
HEADPLANE_HEADSCALE__API_KEY=<from-file>
HEADPLANE_INTEGRATION__DOCKER__ENABLED=true
HEADPLANE_LOAD_ENV_OVERRIDES=true
```

---

## Implementation Plan

### Phase 1: Create Playbook (`headplane-deploy.yml`)

**Location**: `ansible/playbooks/services/headplane-deploy.yml`

**Structure** (follow `headscale-deploy.yml` pattern):
```yaml
---
- name: "Headplane 1: Deploy Headscale Web UI"
  hosts: container-host
  become: true
  gather_facts: true

  environment:
    ANSIBLE_JINJA2_NATIVE: "True"

  vars:
    service_name: "headplane"
    service_description: "Modern web UI for Headscale VPN control server"
    service_tag: "headplane"

    # Template configuration for Semaphore
    template_config:
      semaphore_environment: "ServicePasswords"

    # Headplane configuration
    headplane_image: "ghcr.io/tale/headplane"
    headplane_version: "latest"
    headplane_web_port: 8083
    headplane_data_dir: "/opt/privatebox/data/headplane"
    headplane_config_dir: "/opt/privatebox/config/headplane"

    # Headscale connection (Services VLAN)
    headscale_url: "http://{{ ansible_default_ipv4.address }}:8082"
    headscale_api_key_file: "/opt/privatebox/headscale-api-key.txt"

    # Quadlet configuration
    use_system_quadlet: true
    quadlet_system_path: "/etc/containers/systemd"

    # Container runtime
    container_image_registry: "ghcr.io"
    volume_mount_options: "Z"
    timezone: "UTC"
```

**Tasks Flow**:
1. **Pre-flight Checks**
   - Verify Podman installed
   - Check port 8083 available
   - Verify Headscale running at :8082
   - Verify API key file exists

2. **Generate Secrets**
   - Generate 32-char cookie secret
   - Read Headscale API key from file

3. **Create Directories**
   - `/opt/privatebox/data/headplane`
   - `/opt/privatebox/config/headplane`

4. **Create config.yaml**
   - Use template/copy module
   - Inject cookie secret
   - Inject API key from file
   - Configure Docker integration

5. **Deploy Quadlet**
   - Use template from `ansible/files/quadlet/headplane.container.j2`
   - Reload systemd
   - Enable and start service

6. **Post-Deployment**
   - Wait for health check
   - Verify web UI accessible
   - Display access info

### Phase 2: Create Quadlet Template

**Location**: `ansible/files/quadlet/headplane.container.j2`

```jinja2
[Unit]
Description=Headplane - Modern web UI for Headscale
Documentation=https://github.com/tale/headplane
Wants=network-online.target
After=network-online.target headscale.service
Before=multi-user.target

[Container]
Image={{ container_image_registry }}/{{ headplane_image }}:{{ headplane_version }}
ContainerName=headplane

# Network - bind to Services VLAN IP
PublishPort={{ ansible_default_ipv4.address }}:8083:3000

# Volumes
Volume={{ headplane_config_dir }}:/etc/headplane:{{ volume_mount_options }}
Volume={{ headplane_data_dir }}:/var/lib/headplane:{{ volume_mount_options }}
Volume=/var/run/docker.sock:/var/run/docker.sock:ro

# Environment
Environment="TZ={{ timezone }}"
Environment="HEADPLANE_CONFIG_PATH=/etc/headplane/config.yaml"

# Security
SecurityLabelDisable=false
NoNewPrivileges=true

# Health check
HealthCmd=/bin/sh -c "wget -q --spider http://localhost:3000 || exit 1"
HealthInterval=30s
HealthRetries=3
HealthStartPeriod=60s
HealthTimeout=10s

# Pull policy
Pull=missing

[Service]
Restart=always
RestartSec=30
TimeoutStartSec=900
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target default.target
```

### Phase 3: Update Orchestration

**File**: `tools/orchestrate-services.py`

**Add to sequence** (after Headscale):
```python
self.template_sequence = [
    "Subnet Router 1: Create Alpine VM",
    "OPNsense 1: Establish Secure Access",
    "OPNsense 2: Semaphore Integration",
    "OPNsense 3: Post-Configuration",
    "AdGuard 1: Deploy Container Service",
    "Headscale 1: Deploy VPN Control Server",
    "Headplane 1: Deploy Headscale Web UI",  # ← Add here
    "Homer 1: Deploy Dashboard Service"
]
```

**Update success message**:
```python
print("  - Headscale VPN control server at 10.10.20.10:8082")
print("  - Headplane web UI at http://10.10.20.10:8083")  # ← Add
```

### Phase 4: Homer Dashboard Integration

**When homer-update.yml exists**, add Headplane entry:
```yaml
- name: "Headplane"
  subtitle: "Headscale Web UI"
  tag: "vpn"
  icon: "fas fa-network-wired"
  url: "http://10.10.20.10:8083"
  target: "_blank"
```

---

## Key Implementation Notes

### 1. API Key Handling
**Read from file during deployment**:
```yaml
- name: Read Headscale API key
  slurp:
    src: "{{ headscale_api_key_file }}"
  register: api_key_content

- name: Parse API key
  set_fact:
    headscale_api_key: "{{ api_key_content.content | b64decode | trim }}"
```

### 2. Cookie Secret Generation
**Generate during deployment**:
```yaml
- name: Generate cookie secret
  shell: openssl rand -base64 32 | head -c 32
  register: cookie_secret_result
  changed_when: false

- name: Set cookie secret
  set_fact:
    cookie_secret: "{{ cookie_secret_result.stdout }}"
```

### 3. Docker Socket Security
- Mount as **read-only** (`:ro`)
- Only needed for Docker integration mode
- Headplane uses it to discover Headscale container

### 4. Health Check
- Wait for HTTP 200 on `http://localhost:3000`
- Retry for up to 60 seconds (standard pattern)

### 5. Firewall Configuration
If ufw is active, allow port 8083:
```yaml
- name: Allow Headplane web interface
  ufw:
    rule: allow
    port: "8083"
    proto: tcp
    comment: "Headplane Web UI"
```

---

## Testing Plan

### Post-Deployment Verification
1. **Container Status**
   ```bash
   podman ps | grep headplane
   systemctl status headplane.service
   ```

2. **Web UI Access**
   ```bash
   curl -I http://10.10.20.10:8083
   # Expected: HTTP 200
   ```

3. **API Connection**
   - Open http://10.10.20.10:8083 in browser
   - Should see Headplane login/dashboard
   - Should show connected to Headscale
   - Should list nodes from Headscale

4. **Docker Integration**
   ```bash
   podman logs headplane | grep -i "docker"
   # Should show successful Docker connection
   ```

---

## Troubleshooting Guide

### Issue: "Cannot connect to Headscale"
**Check**:
- Headscale is running: `systemctl status headscale.service`
- Port 8082 accessible: `curl http://10.10.20.10:8082/health`
- API key is valid: `cat /opt/privatebox/headscale-api-key.txt`

**Fix**: Regenerate API key in Headscale deployment

### Issue: "Docker integration failed"
**Check**:
- Docker socket mounted: `podman inspect headplane | grep /var/run/docker.sock`
- Socket permissions: `ls -la /var/run/docker.sock`

**Fix**: Ensure socket mounted as `:ro` in Quadlet file

### Issue: "Cookie secret error"
**Check**: Length must be exactly 32 characters

**Fix**: Regenerate with `openssl rand -base64 32 | head -c 32`

---

## References

### Documentation
- Headplane GitHub: https://github.com/tale/headplane
- Configuration docs: https://github.com/tale/headplane/blob/main/docs/Configuration.md
- Integrated mode: https://github.com/tale/headplane/blob/main/docs/Integrated-Mode.md

### Community Examples
- https://github.com/shrunbr/headscale-configs
- https://thinkinggeek.stewartclan.ca/a-ui-for-headscale-headplane-setup/

### Related PrivateBox Files
- Headscale playbook: `ansible/playbooks/services/headscale-deploy.yml`
- Headscale Quadlet: `ansible/files/quadlet/headscale.container.j2`
- Similar pattern: `ansible/playbooks/services/adguard-deploy.yml`

---

## Status Checklist

- [x] Research completed
- [x] Prerequisites identified
- [x] API key generation implemented in Headscale
- [x] Port allocation confirmed (8083)
- [x] Configuration structure documented
- [ ] Playbook created (`headplane-deploy.yml`)
- [ ] Quadlet template created (`headplane.container.j2`)
- [ ] Orchestration updated
- [ ] Testing completed
- [ ] Homer integration added

---

## Next Session Tasks

1. **Create** `ansible/playbooks/services/headplane-deploy.yml`
2. **Create** `ansible/files/quadlet/headplane.container.j2`
3. **Update** `tools/orchestrate-services.py`
4. **Test** deployment on clean system
5. **Add** to Homer dashboard

**Estimated Time**: 1-2 hours for implementation + testing
