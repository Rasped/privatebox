# OPNsense Zero-Touch Installation Options

**Date**: 2025-07-24  
**Purpose**: Achieve 100% hands-off OPNsense deployment

## Option 1: Pre-built VM Image (RECOMMENDED)

### Overview
Instead of installing from ISO, use OPNsense's pre-built VM images that bypass installation entirely.

### Implementation
```yaml
# Download and prepare VM image
- name: Download OPNsense VM image
  get_url:
    url: "https://mirror.dns-root.de/opnsense/releases/24.7/OPNsense-24.7-vm-amd64.qcow2"
    dest: "/var/lib/vz/images/{{ vmid }}/vm-{{ vmid }}-disk-0.qcow2"
    checksum: "sha256:{{ opnsense_vm_checksum }}"
  delegate_to: "{{ proxmox_host }}"

# Import as VM disk
- name: Import VM disk
  shell: |
    qm importdisk {{ vmid }} /var/lib/vz/images/{{ vmid }}/vm-{{ vmid }}-disk-0.qcow2 {{ storage }}
  delegate_to: "{{ proxmox_host }}"

# No installation needed - VM boots directly to OPNsense
```

### Advantages
- **Zero manual steps** - VM boots directly into OPNsense
- **Faster deployment** - No installation process
- **Predictable** - Same image every time

### Post-Boot Automation
```yaml
# Wait for boot and configure via console
- name: Configure initial settings via console
  expect:
    command: virsh console opnsense
    responses:
      "login:": "root"
      "Password:": "opnsense"  # Default password
      "Enter an option:": "8"  # Shell access
    timeout: 300

# Or use opnsense-bootstrap for conversion
- name: Run opnsense-bootstrap to configure
  shell: |
    fetch -o /tmp/opnsense-bootstrap.sh https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh
    sh /tmp/opnsense-bootstrap.sh -y
```

## Option 2: Custom Pre-configured Image

### Overview
Build a custom OPNsense image with pre-configured settings using OPNsense build tools.

### Build Process
```bash
# Clone OPNsense tools
git clone https://github.com/opnsense/tools.git
cd tools

# Create custom config
cat > config/24.7/build.conf << EOF
# Pre-configure network interfaces
INTERFACES="vtnet0:wan:dhcp vtnet1:lan:10.0.10.1/24"
# Enable SSH by default
SERVICES="sshd"
# Set initial password
ROOTPW="$(openssl passwd -1 'temporarypass')"
EOF

# Build VM image with config
make vm-qcow2 CONFIG=config/24.7/build.conf
```

### Advantages
- **Fully customized** - Interfaces pre-assigned
- **SSH enabled** - Immediate Ansible access
- **Production ready** - No default passwords

## Option 3: opnsense-bootstrap Method

### Overview
Deploy minimal FreeBSD, then convert to OPNsense using official bootstrap script.

### Implementation
```yaml
# Start with FreeBSD VM (has cloud-init!)
- name: Create FreeBSD VM with cloud-init
  community.general.proxmox_kvm:
    vmid: "{{ vmid }}"
    name: opnsense
    node: "{{ proxmox_node }}"
    memory: 4096
    cores: 2
    net:
      net0: 'virtio,bridge=vmbr0'
      net1: 'virtio,bridge=vmbr1'
    ide:
      ide2: "{{ storage }}:cloudinit"
    boot: order=scsi0
    
# Cloud-init user-data
- name: Configure cloud-init
  copy:
    content: |
      #cloud-config
      hostname: opnsense
      ssh_authorized_keys:
        - "{{ ssh_public_key }}"
      runcmd:
        - fetch -o /tmp/bootstrap.sh https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh
        - sh /tmp/bootstrap.sh -y -r 24.7
        - echo 'vtnet0:wan:dhcp' > /tmp/interfaces.txt
        - echo 'vtnet1:lan:10.0.10.1/24' >> /tmp/interfaces.txt
    dest: "/var/lib/vz/snippets/opnsense-cloud-init.yml"
```

### Advantages
- **Cloud-init support** - Full automation
- **Clean conversion** - Official method
- **Flexible** - Can customize during bootstrap

## Option 4: Configuration Import USB (Semi-Automated)

### Overview
Create virtual USB with config.xml, attach to VM for automatic import during install.

### Implementation
```yaml
# Create USB image with config
- name: Create config USB image
  shell: |
    # Create small disk image
    qemu-img create -f raw /tmp/config-usb.img 10M
    
    # Format as FAT32
    mkfs.vfat /tmp/config-usb.img
    
    # Mount and add config
    mkdir -p /tmp/usb
    mount -o loop /tmp/config-usb.img /tmp/usb
    mkdir -p /tmp/usb/conf
    cp /path/to/config.xml /tmp/usb/conf/
    umount /tmp/usb
    
    # Convert to qcow2
    qemu-img convert -O qcow2 /tmp/config-usb.img /var/lib/vz/images/config-usb.qcow2

# Attach to VM
- name: Attach config USB
  shell: |
    qm set {{ vmid }} --usb0 host=/var/lib/vz/images/config-usb.qcow2
```

### Still Requires
- Manual boot from installer
- Manual selection of USB import

## Recommendation: Option 1 - Pre-built VM Image

**Why**:
1. **Truly zero-touch** - No installation process at all
2. **Fastest deployment** - Boot and configure via API
3. **Reliable** - Same starting point every time
4. **Supported** - Official OPNsense images

**Updated Ansible Approach**:
```yaml
- name: Deploy OPNsense VM
  block:
    - name: Download VM image
      get_url:
        url: "{{ opnsense_vm_image_url }}"
        dest: "/tmp/opnsense.qcow2"
        
    - name: Create VM
      community.general.proxmox_kvm:
        vmid: 100
        name: opnsense
        node: "{{ proxmox_node }}"
        memory: 4096
        cores: 2
        net:
          net0: 'virtio,bridge=vmbr0'
          net1: 'virtio,bridge=vmbr1'
        scsihw: virtio-scsi-pci
        
    - name: Import disk image
      shell: |
        qm importdisk 100 /tmp/opnsense.qcow2 {{ storage }}
        qm set 100 --scsi0 {{ storage }}:vm-100-disk-0
        qm set 100 --boot order=scsi0
        
    - name: Start VM
      community.general.proxmox_kvm:
        vmid: 100
        state: started
        
    - name: Wait for boot
      wait_for:
        port: 22
        host: "{{ opnsense_ip }}"
        delay: 60
        timeout: 300
        
    - name: Configure via SSH
      # Now we can use SSH/API for everything!
```

This achieves 100% hands-off deployment!