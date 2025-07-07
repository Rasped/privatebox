# Testing: Proxmox Cloud Image Support

## Overview

Comprehensive testing plan for cloud image support in the proxmox role, ensuring all functionality works correctly and follows conventions.

## Test Environment Setup

```yaml
# test/inventory/hosts.yml
all:
  hosts:
    test-proxmox:
      ansible_host: 192.168.1.10
      ansible_user: root
  vars:
    proxmox_api_host: "{{ ansible_host }}"
    proxmox_api_user: "root@pam"
    proxmox_api_password: "{{ vault_proxmox_password }}"
```

## Unit Tests

### 1. Variable Validation

```yaml
# test_variable_validation.yml
- name: Test variable naming conventions
  hosts: localhost
  tasks:
    - name: Assert correct variable names are used
      assert:
        that:
          - proxmox_vm_name is defined
          - proxmox_vm_vmid is defined
          - vm_name is not defined  # Wrong convention
        fail_msg: "Must use proxmox_vm_* variable naming"
      vars:
        proxmox_vm_name: test
        proxmox_vm_vmid: 100
```

### 2. Cloud Image URL Detection

```yaml
# test_cloud_image_detection.yml
- name: Test cloud image detection logic
  hosts: localhost
  tasks:
    - name: Check detection with URL
      assert:
        that:
          - proxmox_vm_cloud_image_url is defined
          - proxmox_vm_cloud_image_url | length > 0
        success_msg: "Cloud image mode detected"
      vars:
        proxmox_vm_cloud_image_url: "https://example.com/image.img"
    
    - name: Check normal mode without URL
      assert:
        that:
          - proxmox_vm_cloud_image_url is not defined or proxmox_vm_cloud_image_url | length == 0
        success_msg: "Normal VM mode detected"
```

## Integration Tests

### 1. Basic Cloud VM Creation

```yaml
# test_basic_cloud_vm.yml
- name: Test basic cloud VM creation
  hosts: proxmox_hosts
  tasks:
    - name: Remove test VM if exists
      community.general.proxmox_kvm:
        api_host: "{{ proxmox_api_host }}"
        api_user: "{{ proxmox_api_user }}"
        api_password: "{{ proxmox_api_password }}"
        vmid: 9901
        state: absent
      failed_when: false
    
    - name: Create VM from cloud image
      include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_vm_name: test-cloud-basic
        proxmox_vm_vmid: 9901
        proxmox_vm_node: "{{ ansible_hostname }}"
        proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
    
    - name: Verify VM exists
      command: qm status 9901
      register: vm_status
      failed_when: vm_status.rc != 0
    
    - name: Cleanup test VM
      community.general.proxmox_kvm:
        api_host: "{{ proxmox_api_host }}"
        api_user: "{{ proxmox_api_user }}"
        api_password: "{{ proxmox_api_password }}"
        vmid: 9901
        state: absent
```

### 2. Cloud-Init Configuration Test

```yaml
# test_cloud_init.yml
- name: Test cloud-init configuration
  hosts: proxmox_hosts
  tasks:
    - name: Create VM with cloud-init
      include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_vm_name: test-cloud-init
        proxmox_vm_vmid: 9902
        proxmox_vm_node: "{{ ansible_hostname }}"
        proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
        proxmox_vm_cloud_init_user: testuser
        proxmox_vm_cloud_init_password: "TestPass123!"
        proxmox_vm_cloud_init_ssh_keys:
          - "ssh-rsa AAAAB3NzaC1yc2EA... test@example"
    
    - name: Get VM config
      command: qm config 9902
      register: vm_config
    
    - name: Verify cloud-init configuration
      assert:
        that:
          - "'ciuser: testuser' in vm_config.stdout"
          - "'ide2:' in vm_config.stdout"
        fail_msg: "Cloud-init not properly configured"
```

### 3. Static IP Configuration Test

```yaml
# test_static_ip.yml
- name: Test static IP configuration
  hosts: proxmox_hosts
  tasks:
    - name: Create VM with static IP
      include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_vm_name: test-static-ip
        proxmox_vm_vmid: 9903
        proxmox_vm_node: "{{ ansible_hostname }}"
        proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['debian-12'] }}"
        proxmox_vm_cloud_init_ip: "192.168.100.50/24"
        proxmox_vm_cloud_init_gw: "192.168.100.1"
        proxmox_vm_cloud_init_dns: "8.8.8.8 8.8.4.4"
    
    - name: Check IP configuration
      command: qm config 9903
      register: vm_config
    
    - name: Verify network config
      assert:
        that:
          - "'ipconfig0: ip=192.168.100.50/24,gw=192.168.100.1' in vm_config.stdout"
```

## Performance Tests

### 1. Image Caching Test

```yaml
# test_image_caching.yml
- name: Test image caching performance
  hosts: proxmox_hosts
  tasks:
    - name: Time first download
      block:
        - name: Clear cache
          file:
            path: "{{ proxmox_cloud_image_cache_dir }}/ubuntu-24.04-server-cloudimg-amd64.img"
            state: absent
        
        - name: Record start time
          set_fact:
            start_time: "{{ ansible_date_time.epoch }}"
        
        - name: Create VM (triggers download)
          include_role:
            name: proxmox
          vars:
            proxmox_operation: create_vm
            proxmox_vm_name: test-cache-1
            proxmox_vm_vmid: 9910
            proxmox_vm_node: "{{ ansible_hostname }}"
            proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
        
        - name: Calculate download time
          set_fact:
            first_run_time: "{{ ansible_date_time.epoch | int - start_time | int }}"
    
    - name: Time cached creation
      block:
        - name: Record start time
          set_fact:
            start_time: "{{ ansible_date_time.epoch }}"
        
        - name: Create VM (uses cache)
          include_role:
            name: proxmox
          vars:
            proxmox_operation: create_vm
            proxmox_vm_name: test-cache-2
            proxmox_vm_vmid: 9911
            proxmox_vm_node: "{{ ansible_hostname }}"
            proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
        
        - name: Calculate cached time
          set_fact:
            cached_run_time: "{{ ansible_date_time.epoch | int - start_time | int }}"
    
    - name: Verify caching works
      assert:
        that:
          - cached_run_time | int < (first_run_time | int / 2)
        fail_msg: "Caching not working - cached run should be much faster"
```

## Error Handling Tests

### 1. Invalid URL Test

```yaml
# test_invalid_url.yml
- name: Test invalid URL handling
  hosts: proxmox_hosts
  tasks:
    - name: Try invalid URL
      include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_vm_name: test-invalid-url
        proxmox_vm_vmid: 9920
        proxmox_vm_node: "{{ ansible_hostname }}"
        proxmox_vm_cloud_image_url: "https://invalid.example.com/nonexistent.img"
      register: result
      failed_when: false
    
    - name: Verify proper failure
      assert:
        that:
          - result is failed
          - "'download' in result.msg | lower or 'url' in result.msg | lower"
```

### 2. Duplicate VMID Test

```yaml
# test_duplicate_vmid.yml
- name: Test duplicate VMID handling
  hosts: proxmox_hosts
  tasks:
    - name: Create first VM
      include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_vm_name: test-dup-1
        proxmox_vm_vmid: 9930
        proxmox_vm_node: "{{ ansible_hostname }}"
    
    - name: Try duplicate VMID
      include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_vm_name: test-dup-2
        proxmox_vm_vmid: 9930
        proxmox_vm_node: "{{ ansible_hostname }}"
      register: result
      failed_when: false
    
    - name: Verify proper failure
      assert:
        that:
          - result is failed
          - "'exists' in result.msg or 'duplicate' in result.msg | lower"
```

## Backward Compatibility Tests

### 1. Traditional VM Creation

```yaml
# test_backward_compatibility.yml
- name: Test traditional VM creation still works
  hosts: proxmox_hosts
  tasks:
    - name: Create traditional VM (no cloud image)
      include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_vm_name: test-traditional
        proxmox_vm_vmid: 9940
        proxmox_vm_node: "{{ ansible_hostname }}"
        proxmox_vm_cores: 2
        proxmox_vm_memory: 2048
        proxmox_vm_disks:
          scsi0: "local-lvm:10,format=raw"
    
    - name: Verify VM created
      command: qm status 9940
      register: vm_status
      failed_when: vm_status.rc != 0
```

## Test Execution

### Running All Tests

```bash
# Create test playbook
cat > run_all_tests.yml << 'EOF'
---
- import_playbook: test_variable_validation.yml
- import_playbook: test_cloud_image_detection.yml
- import_playbook: test_basic_cloud_vm.yml
- import_playbook: test_cloud_init.yml
- import_playbook: test_static_ip.yml
- import_playbook: test_image_caching.yml
- import_playbook: test_invalid_url.yml
- import_playbook: test_duplicate_vmid.yml
- import_playbook: test_backward_compatibility.yml

- name: Cleanup all test VMs
  hosts: proxmox_hosts
  tasks:
    - name: Remove test VMs
      community.general.proxmox_kvm:
        api_host: "{{ proxmox_api_host }}"
        api_user: "{{ proxmox_api_user }}"
        api_password: "{{ proxmox_api_password }}"
        vmid: "{{ item }}"
        state: absent
      loop: "{{ range(9901, 9950) | list }}"
      failed_when: false
EOF

# Run tests
ansible-playbook -i test/inventory/hosts.yml run_all_tests.yml
```

## Manual Verification

After automated tests, manually verify:

1. **SSH Access**: Can you SSH into a cloud-init VM?
2. **Console Access**: Does the console show cloud-init progress?
3. **Network Connectivity**: Is the network properly configured?
4. **Service Status**: Are expected services running?

```bash
# Test SSH
ssh testuser@192.168.100.50

# Check cloud-init status
cloud-init status --wait

# Verify network
ip addr show
ip route show
```

## CI/CD Integration

```yaml
# .gitlab-ci.yml or similar
test_proxmox_cloud_image:
  stage: test
  script:
    - ansible-playbook -i test/inventory/hosts.yml run_all_tests.yml
  only:
    changes:
      - ansible/roles/proxmox/**/*
      - documentation/features/proxmox-cloud-image-support/**/*
```

## Success Criteria

- ✅ All variable validation tests pass
- ✅ Cloud image detection works correctly
- ✅ VMs created successfully from cloud images
- ✅ Cloud-init properly configured
- ✅ Static IP configuration works
- ✅ Image caching provides performance benefit
- ✅ Error handling works properly
- ✅ Backward compatibility maintained
- ✅ Manual verification successful