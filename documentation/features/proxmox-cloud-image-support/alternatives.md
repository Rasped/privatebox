# Alternatives: Proxmox Cloud Image Support

## Overview

This document examines different approaches for adding cloud image support to the existing proxmox role, with a focus on integration rather than creating new systems.

## Option 1: Enhance Existing create_vm Task (CHOSEN)

### Description
Add cloud image detection and handling to the existing create_vm.yml task file.

### Implementation
```yaml
# In create_vm.yml
- include_tasks: prepare_cloud_image.yml
  when: proxmox_vm_cloud_image_url is defined
```

### Pros
- Single VM creation path
- Minimal code changes
- Follows existing patterns
- Backward compatible
- Easy to understand

### Cons
- Makes create_vm.yml longer
- Mixes concerns (VM creation + image handling)
- May need refactoring later

### Verdict: ✅ Recommended
Best balance of simplicity and functionality while maintaining compatibility.

## Option 2: New Operation Type

### Description
Add a new operation: `proxmox_operation: create_vm_from_cloud_image`

### Implementation
```yaml
# In main.yml
- include_tasks: create_vm_from_cloud_image.yml
  when: proxmox_operation == "create_vm_from_cloud_image"
```

### Pros
- Clean separation of concerns
- Follows existing operation pattern
- Can have specialized logic
- No risk to existing create_vm

### Cons
- Duplicates VM creation logic
- Two paths to maintain
- Users must choose operation type
- More complex documentation

### Verdict: ⚠️ Viable but Over-Engineered
Good pattern but unnecessary complexity for this feature.

## Option 3: Wrapper Task with Delegation

### Description
Create a wrapper task that prepares the image then delegates to create_vm.

### Implementation
```yaml
# New task file
- include_tasks: download_cloud_image.yml
- include_tasks: create_vm.yml
  vars:
    proxmox_vm_disks:
      scsi0: "{{ cloud_image_path }}"
```

### Pros
- Reuses existing VM creation
- Clear separation
- Could be its own operation

### Cons
- Complex variable passing
- May not work with disk import
- Still creates parallel path

### Verdict: ❌ Too Complex
The disk import process doesn't fit well with this approach.

## Option 4: Separate Playbook Calling Role

### Description
Create a playbook that prepares images then calls the proxmox role.

### Implementation
```yaml
# New playbook (NOT recommended)
- name: Prepare cloud image
  hosts: proxmox_hosts
  tasks:
    - name: Download image
      # ...
    
- name: Create VM
  import_playbook: create_vm_playbook.yml
```

### Pros
- Complete separation
- Could be in playbooks/

### Cons
- Creates parallel system
- Breaks role encapsulation
- Not idiomatic Ansible
- Hard to maintain

### Verdict: ❌ Violates Principles
This is exactly what we should NOT do - creates a parallel system.

## Option 5: Shell Script Integration

### Description
Use existing bash scripts from within the role.

### Implementation
```yaml
- name: Run cloud image script
  script: "{{ role_path }}/files/create-cloud-vm.sh"
  environment:
    VMID: "{{ proxmox_vm_vmid }}"
```

### Pros
- Reuses proven bash logic
- Handles complex edge cases
- Fast to implement

### Cons
- Not idiomatic Ansible
- Harder to integrate with role vars
- Breaks role abstraction
- Debug/maintenance issues

### Verdict: ⚠️ Last Resort
Could work but defeats the purpose of using Ansible.

## Option 6: Custom Module

### Description
Create a custom Ansible module for cloud image VMs.

### Implementation
```python
# library/proxmox_cloud_vm.py
def main():
    # Handle all cloud image logic
    module.exit_json(changed=True)
```

### Pros
- Clean interface
- Reusable
- Professional

### Cons
- Significant development effort
- Testing complexity
- Maintenance burden
- Over-engineering

### Verdict: ❌ Over-Engineered
Too much effort for the value provided.

## Comparison Matrix

| Approach | Integration | Complexity | Maintenance | Risk | Convention |
|----------|-------------|------------|-------------|------|------------|
| Enhance create_vm | Excellent | Low | Low | Low | Perfect |
| New Operation | Good | Medium | Medium | Low | Perfect |
| Wrapper Task | Fair | High | Medium | Medium | Good |
| Separate Playbook | Poor | Low | High | High | Poor |
| Shell Script | Fair | Low | High | Medium | Poor |
| Custom Module | Good | Very High | High | Low | Good |

## Decision Factors

### Why Enhance create_vm Wins:

1. **Simplicity**: Least complex solution that works
2. **Integration**: Fits naturally into existing flow
3. **Maintenance**: Single code path to maintain
4. **Convention**: Follows all established patterns
5. **Risk**: Minimal risk of breaking existing functionality

### When to Reconsider:

If cloud image support becomes complex enough that it:
- Requires 200+ lines of tasks
- Needs very different logic from regular VMs
- Becomes a performance bottleneck
- Is used by multiple roles

Then extracting to a new operation type would make sense.

## Lessons Learned

1. **Start Simple**: Begin with the simplest integration
2. **Follow Patterns**: Use existing conventions
3. **Avoid Parallel Systems**: Don't create new ways to do the same thing
4. **Think Evolution**: Design for extraction later if needed
5. **Respect the Role**: Keep logic within role boundaries