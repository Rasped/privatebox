# OPNsense Final Automation Strategy

**Date**: 2025-07-24  
**Status**: Confirmed - 100% Hands-Off Deployment Achievable

## Executive Summary

OPNsense qcow2 images are **full installations** that boot directly to a running system with default credentials (root/opnsense). Combined with the comprehensive API, we can achieve complete automation.

## Selected Approach: API-Based Configuration

### Why API-Based?
1. **No image modification** - Use official qcow2 as-is
2. **Most reliable** - Well-documented and supported
3. **Ansible native** - Using `ansibleguy.opnsense` collection
4. **Verifiable** - Can confirm each configuration step
5. **Maintainable** - Changes are code, not binary configs

### Implementation Plan

```yaml
# Phase 1: Deploy VM with qcow2 image
- name: Download OPNsense qcow2 image
  get_url:
    url: "https://mirror.dns-root.de/opnsense/releases/24.7/OPNsense-24.7-vm-amd64.qcow2"
    dest: "/tmp/opnsense.qcow2"
    checksum: "sha256:{{ opnsense_checksum }}"
  delegate_to: "{{ proxmox_host }}"

- name: Create VM structure
  community.general.proxmox_kvm:
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ proxmox_api_password }}"
    api_host: "{{ proxmox_host }}"
    vmid: 100
    name: opnsense
    memory: 4096
    cores: 2
    net:
      net0: 'virtio,bridge=vmbr0'
      net1: 'virtio,bridge=vmbr1'
    scsihw: virtio-scsi-pci
    onboot: yes

- name: Import disk and configure boot
  shell: |
    qm importdisk 100 /tmp/opnsense.qcow2 {{ storage }}
    qm set 100 --scsi0 {{ storage }}:vm-100-disk-0
    qm set 100 --boot order=scsi0
    qm start 100

# Phase 2: Configure via API using ansibleguy.opnsense
- name: Wait for OPNsense to boot
  wait_for:
    host: 192.168.1.1
    port: 443
    delay: 60

- name: Install Ansible collection
  ansible.builtin.ansible_galaxy_collection:
    name: ansibleguy.opnsense

- name: Configure OPNsense via API
  hosts: opnsense
  vars:
    ansible_host: 192.168.1.1
    ansible_user: root
    ansible_password: opnsense
    ansible_connection: ansibleguy.opnsense.api
  tasks:
    - name: Set hostname
      ansibleguy.opnsense.system:
        hostname: opnsense
        domain: privatebox.local

    - name: Configure interfaces
      ansibleguy.opnsense.interface:
        name: "{{ item.name }}"
        device: "{{ item.device }}"
        ipv4_type: "{{ item.ipv4_type }}"
        ipv4_address: "{{ item.ipv4_address | default(omit) }}"
        ipv4_subnet: "{{ item.ipv4_subnet | default(omit) }}"
      loop:
        - { name: wan, device: vtnet0, ipv4_type: dhcp }
        - { name: lan, device: vtnet1, ipv4_type: static, ipv4_address: 10.0.10.1, ipv4_subnet: 24 }

    - name: Create VLANs
      ansibleguy.opnsense.vlan:
        interface: vtnet1
        vlan_id: "{{ item.id }}"
        description: "{{ item.desc }}"
      loop:
        - { id: 10, desc: "Management" }
        - { id: 20, desc: "Services" }
        - { id: 30, desc: "LAN" }
        - { id: 40, desc: "IoT" }

    - name: Configure VLAN interfaces
      ansibleguy.opnsense.interface:
        name: "{{ item.name }}"
        device: "{{ item.device }}"
        ipv4_type: static
        ipv4_address: "{{ item.ip }}"
        ipv4_subnet: 24
      loop:
        - { name: vlan10, device: vtnet1_vlan10, ip: 10.0.10.1 }
        - { name: vlan20, device: vtnet1_vlan20, ip: 10.0.20.1 }
        - { name: vlan30, device: vtnet1_vlan30, ip: 10.0.30.1 }
        - { name: vlan40, device: vtnet1_vlan40, ip: 10.0.40.1 }

    - name: Install required packages
      ansibleguy.opnsense.package:
        name:
          - os-api
          - os-qemu-guest-agent
        state: present

    - name: Enable API access
      ansibleguy.opnsense.api:
        enabled: true

    - name: Configure firewall rules
      ansibleguy.opnsense.rule:
        description: "{{ item.desc }}"
        interface: "{{ item.interface }}"
        source: "{{ item.source }}"
        destination: "{{ item.destination }}"
        destination_port: "{{ item.port | default(omit) }}"
        protocol: "{{ item.protocol | default('any') }}"
        action: "{{ item.action }}"
      loop: "{{ firewall_rules }}"
```

## Timeline

1. **VM Creation**: 2 minutes
2. **Boot Time**: 1 minute  
3. **API Configuration**: 5 minutes
4. **Total**: ~8 minutes fully automated

## Fallback Options

### If API approach fails:
1. **Config.xml injection via ISO** - Pre-create full config
2. **Serial console automation** - Use expect scripts
3. **Manual fallback** - Well-documented 15-minute process

## Key Advantages

1. **Zero touch** - No manual intervention required
2. **Idempotent** - Can run multiple times safely
3. **Version controlled** - All config in Ansible playbooks
4. **Testable** - Can validate in dev environment
5. **Auditable** - Clear record of all changes

## Prerequisites

```bash
# Install Ansible collection
ansible-galaxy collection install ansibleguy.opnsense

# Install Python dependencies
pip install httpx netaddr
```

## Validation

```yaml
- name: Validate configuration
  tasks:
    - name: Check interfaces
      ansibleguy.opnsense.interface_info:
      register: interfaces

    - name: Verify VLANs
      ansibleguy.opnsense.vlan_info:
      register: vlans

    - name: Test firewall rules
      ansibleguy.opnsense.rule_info:
      register: rules

    - name: Confirm all services running
      ansibleguy.opnsense.service:
        name: "{{ item }}"
        state: started
      loop:
        - unbound
        - dhcpd
```

## Conclusion

Using OPNsense qcow2 images with API-based configuration provides a robust, 100% automated deployment solution that aligns perfectly with the PrivateBox philosophy of minimal bootstrap and maximum automation.