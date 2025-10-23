# PrivateBox Asset Inventory for Offline Recovery

## Overview

This document catalogs all external assets (files, images, packages) that PrivateBox downloads during deployment. For Phase 1 recovery implementation, these assets must be stored locally to enable completely offline operation.

## Asset Categories

### 1. Source Code Repositories

#### Primary Repository
- **URL**: `https://github.com/Rasped/privatebox.git`
- **Download Location**: quickstart.sh (line 210)
- **Size**: 1.9MB (measured)
- **Local Path**: `/recovery-assets/source/privatebox/`
- **Method**: `git clone --depth 1 --branch "$REPO_BRANCH"`
- **Notes**: Keep exact git repo structure, don't create tarballs

### 2. Virtual Machine Images

#### Debian 13 Cloud Image
- **URL**: `https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2`
- **Download Location**: bootstrap/create-vm.sh
- **Size**: 324MB (measured)
- **Local Path**: `/recovery-assets/images/debian-13-genericcloud-amd64.qcow2`
- **Method**: `wget -q --show-progress`
- **Notes**: Latest symlink, actual filename may vary with releases

#### OPNsense VM Template
- **URL**: `https://github.com/Rasped/privatebox/releases/download/v1.0.2-opnsense/vzdump-qemu-105-opnsense.vma.zst`
- **Download Location**: bootstrap/deploy-opnsense.sh (line 60)
- **Size**: 767MB
- **MD5**: `c6d251e1c62f065fd28d720572f8f943`
- **Local Path**: `/recovery-assets/templates/opnsense-template.vma.zst`
- **Method**: `wget --progress=bar:force` with MD5 verification
- **Notes**: Critical for firewall deployment

### 3. Container Images

#### Semaphore Base Image
- **Registry**: `docker.io`
- **Image**: `semaphoreui/semaphore:latest`
- **Download Location**: bootstrap/setup-guest.sh (line 79)
- **Size**: 809MB (measured)
- **Local Path**: `/recovery-assets/containers/semaphore-base-latest.tar`
- **Method**: Used in custom Containerfile build
- **Notes**: Base for custom Semaphore image with Proxmox support

#### Portainer Container
- **Registry**: `docker.io`
- **Image**: `portainer/portainer-ce:latest`
- **Download Location**: bootstrap/setup-guest.sh (line 105)
- **Size**: 178MB (measured)
- **Local Path**: `/recovery-assets/containers/portainer-ce-latest.tar`
- **Method**: Podman quadlet pulls automatically
- **Notes**: Container management UI

#### AdGuard Home Container
- **Registry**: `docker.io`
- **Image**: `adguard/adguardhome:latest`
- **Download Location**: ansible/playbooks/services/adguard-deploy.yml (line 17)
- **Size**: 72MB (measured)
- **Local Path**: `/recovery-assets/containers/adguard-home-latest.tar`
- **Method**: Podman quadlet pulls automatically
- **Notes**: DNS filtering service

#### Homer Dashboard Container
- **Registry**: `docker.io`
- **Image**: `b4bz/homer:latest`
- **Download Location**: ansible/playbooks/services/homer-deploy.yml (line 18)
- **Size**: 16MB (measured)
- **Local Path**: `/recovery-assets/containers/homer-latest.tar`
- **Method**: Explicit pull in playbook: `podman pull docker.io/b4bz/homer:latest`
- **Notes**: Static dashboard service

### 4. Python Dependencies

#### Proxmox API Libraries
- **Packages**: `proxmoxer`, `requests`
- **Download Location**: bootstrap/setup-guest.sh (line 83)
- **Size**: 596KB (measured)
- **Local Path**: `/recovery-assets/python-wheels/`
- **Method**: `pip3 install --no-cache-dir` in Semaphore container build
- **Offline Method**: Pre-download with `pip download`, install with `--no-index --find-links`
- **Notes**: Required for Proxmox automation in Semaphore

### 5. Ansible Collections

#### Community General Collection
- **Collection**: `community.general`
- **Download Location**: bootstrap/setup-guest.sh (line 85)
- **Size**: 2.6MB (measured)
- **Local Path**: `/recovery-assets/ansible-collections/community-general.tar.gz`
- **Method**: `ansible-galaxy collection install -p /usr/share/ansible/collections`
- **Offline Method**: Pre-download with `ansible-galaxy collection download`, install from local file
- **Notes**: Essential Ansible modules for system management

### 6. DNS Blocklists (Runtime Downloads)

#### OISD Basic Blocklist
- **URL**: `https://abp.oisd.nl/basic/`
- **Download Location**: ansible/playbooks/services/adguard-deploy.yml (AdGuard config)
- **Size**: ~1MB
- **Update Frequency**: Daily by AdGuard
- **Notes**: Downloaded by AdGuard at runtime, not during deployment

#### Steven Black Hosts
- **URL**: `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
- **Download Location**: ansible/playbooks/services/adguard-deploy.yml (AdGuard config)
- **Size**: ~5MB
- **Update Frequency**: Weekly by AdGuard
- **Notes**: Downloaded by AdGuard at runtime, not during deployment

### 7. System Packages

#### Host Dependencies (Proxmox)
- **Packages**: `ethtool`, `sshpass`, `zstd`, `curl`, `wget`, `git`
- **Download Location**: bootstrap/prepare-host.sh (line 42) & quickstart.sh (line 172)
- **Method**: `apt-get install -y`
- **Notes**: Installed on Proxmox host during bootstrap

#### Guest Dependencies (Debian VM)
- **Packages**: `curl`, `wget`, `ca-certificates`, `gnupg`, `lsb-release`, `jq`, `git`, `podman`, `buildah`, `skopeo`, `openssh-client`
- **Download Location**: bootstrap/setup-guest.sh (line 45)
- **Method**: `DEBIAN_FRONTEND=noninteractive apt-get install -y`
- **Notes**: Installed in Management VM during Phase 3

## Recovery Assets Directory Structure

```
/recovery-assets/
├── source/
│   └── privatebox/          # Complete git repository
├── images/
│   ├── debian-13-genericcloud-amd64.qcow2
│   └── checksums.sha256
├── containers/
│   ├── semaphore-base-latest.tar
│   ├── portainer-ce-latest.tar
│   ├── adguard-home-latest.tar
│   ├── homer-latest.tar
│   └── manifest.json        # Container metadata
├── templates/
│   └── opnsense-template.vma.zst
├── python-wheels/
│   ├── proxmoxer-*.whl
│   ├── requests-*.whl
│   └── requirements.txt     # Version locks
├── ansible-collections/
│   └── community-general-*.tar.gz
└── packages/
    ├── debian-base.tar.gz   # Essential .deb files
    └── proxmox-host.tar.gz  # Host dependency .deb files
```

## Implementation Priority

### Phase 1A: Container Images (Highest Impact)
1. Semaphore base image (custom build dependency)
2. Portainer image (core management)
3. AdGuard image (DNS service)
4. Homer image (dashboard)

### Phase 1B: Large Downloads
1. OPNsense template (767MB, network critical)
2. Debian cloud image (500MB, VM creation)

### Phase 1C: Dependencies
1. Python wheels (Semaphore functionality)
2. Ansible collections (automation capability)
3. Source code repository (self-contained operation)

### Phase 1D: System Packages (Optional)
1. Debian packages cache (update capability)
2. Host packages cache (bootstrap reliability)

## Storage Requirements - EXACT MEASUREMENTS

### PrivateBox Asset Measurements (Downloaded 2025-09-29)
- **Container images**: 1.1GB total
  - Semaphore: 809MB
  - Portainer: 178MB
  - AdGuard: 72MB
  - Homer: 16MB
- **OPNsense template**: 767MB (vzdump-qemu-105-opnsense.vma.zst)
- **Debian cloud image**: 324MB (debian-13-genericcloud-amd64.qcow2)
- **Ansible collections**: 2.6MB (community-general-11.3.0.tar.gz)
- **Source code**: 1.9MB (PrivateBox git repository)
- **Python wheels**: 596KB (proxmoxer, requests + dependencies)

**Total PrivateBox Assets**: 2.27GB (2,273,558,665 bytes exactly)

### Golden Proxmox Image Measurements (Tested 2025-09-29)
- **Test Platform**: Nested VM with Proxmox VE 9.0 ZFS installation
- **Raw installation size**: 2.1GB (6.57% of 32GB allocated disk)
- **Compressed backup size**: 1.6GB (vzdump with gzip compression)
- **Compression efficiency**: 93% sparse data (mostly zeros)
- **Installation method**: Automated with answer.toml file

### Combined Recovery Requirements
- **PrivateBox assets**: 2.27GB
- **Golden Proxmox image**: 1.6GB
- **Core total**: 3.87GB

### Final Recommendation: 8GB Recovery Partition
- **Core assets**: 3.87GB (measured exactly)
- **Growth buffer**: 2GB (future versions, additional containers)
- **Filesystem overhead**: 1GB (ext4 metadata, reserved blocks)
- **Safety margin**: 1.13GB
- **Total**: 8GB (provides 2.07x safety margin over actual requirements)

## Offline Validation Strategy

Each asset category should be testable offline:

1. **Container images**: `podman load` + `podman run` test
2. **VM images**: checksum verification + qemu probe
3. **Python packages**: `pip install --no-index` test
4. **Ansible collections**: `ansible-galaxy list` verification
5. **Source code**: directory structure + key file existence

## Notes for Implementation

- **Checksums required**: All binary assets need verification
- **Version locking**: Pin versions to prevent drift
- **Atomic updates**: Replace assets as complete sets
- **Fallback behavior**: Scripts must detect missing assets gracefully
- **Testing strategy**: Each asset needs offline installation test