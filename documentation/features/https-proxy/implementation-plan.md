# Caddy Reverse Proxy Implementation Plan

## Overview
Implement HTTPS access for all PrivateBox services using Caddy as a reverse proxy with `.lan` domain names.

## Phase 1: Core Deployment

### 1.1 Create Ansible Playbook
- **File**: `ansible/playbooks/services/caddy-deploy.yml`
- **Purpose**: Deploy Caddy container via Podman Quadlet
- **Key configurations**:
  - Mount config: `/opt/privatebox/config/caddy`
  - Expose ports: 80, 443
  - Image: `caddy:alpine`
  - Auto-restart on failure

### 1.2 Create Caddyfile Template
- **File**: `ansible/files/caddy/Caddyfile.j2`
- **Initial services**:
  ```caddyfile
  adguard.lan {
      tls internal
      reverse_proxy localhost:8080
  }
  
  semaphore.lan {
      tls internal
      reverse_proxy localhost:3000
  }
  
  portainer.lan {
      tls internal
      reverse_proxy localhost:9000
  }
  ```

### 1.3 Create Quadlet File
- **File**: `ansible/files/quadlet/caddy.container.j2`
- **Features**:
  - Health check: `curl https://localhost/health`
  - Read-only root filesystem
  - Specific write mounts for certificates and config

## Phase 2: DNS Integration

### 2.1 AdGuard DNS Configuration
- **File**: `ansible/playbooks/services/adguard-configure-dns-rewrites.yml`
- **DNS Rewrites**:
  - `*.lan` → 192.168.1.20 (wildcard for all services)
  - Individual entries as fallback
- **Method**: AdGuard API calls

## Phase 3: Service Discovery

### 3.1 Service Registry
- **File**: `ansible/group_vars/all/services.yml`
- **Structure**:
  ```yaml
  privatebox_services:
    - name: adguard
      port: 8080
      domain: adguard.lan
    - name: semaphore
      port: 3000
      domain: semaphore.lan
    - name: portainer
      port: 9000
      domain: portainer.lan
  ```

### 3.2 Dynamic Caddyfile Generation
- Template loops through service registry
- Auto-generates reverse proxy entries
- Easy to add new services

## Phase 4: Integration

### 4.1 Update Existing Infrastructure
- Add Caddy to bootstrap sequence
- Deploy after core services
- Update firewall rules (ports 80, 443)

### 4.2 Documentation
- **File**: `documentation/features/https-proxy/README.md`
- **Contents**:
  - Certificate trust instructions
  - Service access URLs
  - Adding new services guide

## Deployment Sequence
1. Deploy Caddy container
2. Configure DNS in AdGuard
3. Test HTTPS access to all services
4. Create user documentation

## Success Criteria
- All services accessible via `https://service.lan`
- Automatic HTTPS with self-signed certificates
- Single configuration point for new services
- Clean URLs without port numbers