# OPNsense IDE Boot Mystery

## Date: 2025-07-27

### The Problem
When creating an OPNsense VM with automated installation, we encounter a "vm_fault: pager read error" when booting from a disk attached to ide1. However, the SAME disk boots perfectly when attached to ide3.

### Symptoms
1. Fresh disk created on ide1: **FAILS** with pager read error
2. Fresh disk created on ide3: **WORKS** but installation fails
3. Moving disk from ide3 to ide1 AFTER installation: **WORKS**
4. Moving disk from ide1 to ide3: **WORKS**

### What We Tried
1. **SCSI Controller**: Initially failed with pager read error
2. **IDE Controller on ide1**: Still fails with pager read error
3. **IDE Controller on ide3**: Boots fine but OPNsense installer can't find it
4. **Disk size syntax**: Tested with/without 'G' suffix - not the issue

### The Workaround
```yaml
# 1. Create disk on ide3 (allows installation to proceed)
- name: Create fresh disk
  command: qm set {{ vm_id }} --ide3 local-lvm:16

# 2. After installation, move disk to ide1
- name: Attach disk as ide1
  command: qm set {{ vm_id }} --ide1 local-lvm:vm-{{ vm_id }}-disk-0,size=16G
  
- name: Remove disk from ide3
  command: qm set {{ vm_id }} --delete ide3
  
- name: Set boot order to ide1
  command: qm set {{ vm_id }} --boot order=ide1
```

### Why This Works
Unknown. The exact same disk that fails on ide1 when created fresh works perfectly on ide1 when moved from ide3. This suggests:
- Not a disk corruption issue
- Not a boot sector issue
- Possibly a Proxmox disk initialization quirk
- Possibly a FreeBSD/OPNsense driver timing issue

### Current Status
The workaround is implemented in `opnsense-deploy-automated.yml` and allows successful automated installation. The root cause remains a mystery.

### Environment
- Proxmox VE (qemu 9.0.2)
- OPNsense 25.1 DVD installer
- VM OS Type: l26 (Linux)
- Boot failures occur before OPNsense kernel loads