# OPNsense ISO Remastering Guide for 100% Hands-Off Deployment

## Deployment Architecture

**Order of Operations:**
1. **Semaphore** (on privatebox VM) triggers Ansible playbook
2. **Ansible** connects to Proxmox host via SSH
3. **All operations execute on Proxmox host**:
   - Download OPNsense ISO
   - Generate custom config.xml from template
   - Remaster ISO with embedded configuration
   - Create and deploy VM
   - Verify deployment

**Key Point**: No scripts or files are copied to Proxmox. Everything is executed via Ansible tasks running on the Proxmox host.

## Objective

Achieve **100% hands-off automated OPNsense deployment** on Proxmox VE with the following requirements:
- No manual console interaction required
- No network disruption during deployment
- Pre-configured static IP address (192.168.1.69)
- Pre-configured gateway (192.168.1.3)
- SSH access enabled with key authentication
- Root password set to known value
- Ready for production use immediately after boot

## Why ISO Remastering?

After extensive testing of multiple approaches, ISO remastering emerged as the superior solution:

### Failed Approaches
1. **Disk Mounting**: Linux kernel has read-only UFS support, cannot modify config.xml directly
2. **Serial Console Automation**: Proxmox serial console has tcgetattr issues, unreliable
3. **qm sendkey Automation**: Timing issues, boot sequence varies, fragile
4. **Cloud-init**: OPNsense (FreeBSD) lacks proper cloud-init support

### ISO Remastering Advantages
- No filesystem compatibility issues (modify ISO9660, not UFS)
- No console interaction needed
- Works with standard Proxmox ISO upload/deployment
- 100% repeatable and reliable
- Can version control your configurations
- Deploy unlimited instances with same config

## Technical Background

### OPNsense ISO Structure
```
OPNsense-XX.X-OpenSSL-dvd-amd64.iso
├── boot/
│   ├── cdboot          # BIOS boot loader (El Torito)
│   └── loader.efi      # UEFI boot loader
├── usr/
│   └── local/
│       └── etc/
│           └── config.xml  # <-- Inject custom config here
└── [other system files]
```

### Boot System
- **BIOS Boot**: Uses `boot/cdboot` with El Torito boot catalog
- **UEFI Boot**: Uses EFI system partition
- **Critical**: Must preserve exact boot structure when remastering

### Config Loading Process
1. OPNsense installer boots from ISO
2. Checks for `/usr/local/etc/config.xml` on the ISO
3. If found, uses it as the initial system configuration
4. No user interaction required if config is complete

## Prerequisites

### Execution Environment
- **Ansible Playbook** runs from Semaphore on privatebox VM
- **All operations** execute on Proxmox host via SSH
- **No manual steps** - everything automated through Ansible

### Software Requirements (on Proxmox Host)
The Ansible playbook will ensure these tools are installed on Proxmox:
- `xorriso` - ISO creation with boot support
- `bzip2` - ISO decompression
- `xmllint` - XML validation
- Standard Unix tools (mount, rsync, etc.)

### Required Information
1. **SSH Key** - Your public key for OPNsense access
2. **Root Password** - Will be hashed by Ansible
3. **Network Configuration**:
   - Static IP: 192.168.1.69/24
   - Gateway: 192.168.1.3
   - Interface mappings (vtnet0/vtnet1)

## Configuration Preparation

### 1. Generate Base Configuration

Option A: From existing OPNsense installation:
```bash
# Export from running OPNsense
scp root@existing-opnsense:/conf/config.xml ./config-base.xml
```

Option B: Start with sample configuration:
```bash
# Download sample from OPNsense repository
wget https://raw.githubusercontent.com/opnsense/core/master/src/etc/config.xml.sample
mv config.xml.sample config-base.xml
```

### 2. Customize Configuration

Key sections to modify in config.xml:

#### Network Configuration
```xml
<system>
    <hostname>opnsense</hostname>
    <domain>privatebox.local</domain>
    <!-- ... -->
</system>

<interfaces>
    <wan>
        <if>vtnet1</if>  <!-- Adjust for your environment -->
        <descr>WAN</descr>
        <enable>1</enable>
        <ipaddr>dhcp</ipaddr>
    </wan>
    <lan>
        <if>vtnet0</if>  <!-- Adjust for your environment -->
        <descr>LAN</descr>
        <enable>1</enable>
        <ipaddr>192.168.1.69</ipaddr>
        <subnet>24</subnet>
        <gateway>192.168.1.3</gateway>
    </lan>
</interfaces>

<gateways>
    <gateway_item>
        <interface>lan</interface>
        <gateway>192.168.1.3</gateway>
        <name>LAN_GW</name>
        <weight>1</weight>
        <ipprotocol>inet</ipprotocol>
        <descr>LAN Gateway</descr>
    </gateway_item>
</gateways>
```

#### SSH Configuration
```xml
<system>
    <!-- Enable SSH -->
    <ssh>
        <enabled>enabled</enabled>
        <permitrootlogin>1</permitrootlogin>
        <passwordauth>0</passwordauth>
        <port>22</port>
    </ssh>
    
    <!-- Add SSH key for root -->
    <user>
        <name>root</name>
        <authorizedkeys>ssh-rsa AAAAB3... your-key-here</authorizedkeys>
        <password>$2b$10$... (bcrypt hash)</password>
    </user>
</system>
```

#### Generate Password Hash
```bash
# Generate bcrypt hash for root password
htpasswd -bnBC 10 "" "YourPasswordHere" | tr -d ':\n' | sed 's/$2y/$2b/'
```

### 3. Validate Configuration
```bash
# Validate XML syntax
xmllint --noout config.xml

# Check for required elements
grep -E "(ipaddr|subnet|gateway|ssh)" config.xml
```

## ISO Remastering Process

### Pure Ansible Implementation

The entire remastering process is implemented as Ansible tasks that execute on the Proxmox host. No scripts are copied or created on the target system.

### Key Ansible Tasks

1. **Install Required Tools** (if not present)
   - Ansible ensures xorriso, bzip2, and xmllint are installed
   
2. **Download OPNsense ISO**
   - Check if ISO already exists in Proxmox storage
   - Download compressed ISO if needed
   - Extract using bzip2
   
3. **Prepare Configuration**
   - Generate bcrypt password hash using Ansible's password_hash filter
   - Template config.xml with SSH key, password, and network settings
   
4. **Mount Original ISO**
   - Create temporary mount point
   - Mount ISO as loop device (read-only)
   
5. **Copy ISO Contents**
   - Create working directory for new ISO
   - Copy all files preserving structure and permissions
   
6. **Inject Configuration**
   - Place templated config.xml at `/usr/local/etc/config.xml`
   - Set correct permissions (644)
   - Validate XML syntax
   
7. **Create Custom ISO**
   - Use xorriso to create new ISO with preserved boot parameters:
     ```
     xorriso -as mkisofs \
  -R -J -joliet-long \
  -b boot/cdboot \
  -c boot.catalog \
  -no-emul-boot \
  -boot-load-size 4 \
       -boot-info-table \
       -o opnsense-custom.iso \
       iso-contents
     ```
   
8. **Cleanup**
   - Unmount original ISO
   - Remove temporary directories
   - Move custom ISO to Proxmox ISO storage

### Reference Script

For understanding the process, a reference bash script is included in this repository (`remaster-opnsense.sh`). However, the production deployment uses pure Ansible tasks as described above.

## Proxmox Deployment

The deployment is fully automated through Ansible. The custom ISO is created on the Proxmox host and then used to deploy the VM.

### Automated Deployment Process

1. **ISO Creation** (on Proxmox via Ansible)
   - Download OPNsense ISO
   - Generate custom config.xml
   - Remaster ISO with configuration
   - Store in Proxmox ISO storage

2. **VM Creation** (on Proxmox via Ansible)
   - Create VM with appropriate specs
   - Attach custom ISO
   - Configure network interfaces
   - Start VM

3. **Verification** (from Ansible)
   - Wait for HTTPS availability
   - Verify SSH access
   - Confirm deployment success

## Verification

### 1. Check VM Status
```bash
# On Proxmox
qm status 8000
```

### 2. Test Network Access
```bash
# Ping OPNsense
ping 192.168.1.69

# Test HTTPS
curl -k https://192.168.1.69
```

### 3. SSH Access (if configured)
```bash
ssh -i ~/.ssh/opnsense_key root@192.168.1.69
```

## Troubleshooting

### ISO Won't Boot
- Verify boot parameters match original ISO
- Use `xorriso -indev original.iso -report_el_torito cmd` to check
- Ensure cdboot file is not corrupted

### Config Not Applied
- Check config.xml location: `/usr/local/etc/config.xml` in ISO
- Validate XML syntax with xmllint
- Check file permissions (should be 644)

### Network Not Accessible
- Verify interface names match your environment (vtnet0 vs em0)
- Check VLAN configuration if applicable
- Ensure IP doesn't conflict with existing devices

### Boot Takes Too Long
- Normal first boot can take 3-5 minutes
- Check Proxmox console for errors
- Verify sufficient RAM allocated (minimum 1GB, recommended 2GB)

## Advanced Topics

### Multiple Configurations
Create different ISOs for different environments:
```bash
./remaster-opnsense.sh config-prod.xml  # -> opnsense-prod.iso
./remaster-opnsense.sh config-test.xml  # -> opnsense-test.iso
./remaster-opnsense.sh config-dev.xml   # -> opnsense-dev.iso
```

### CI/CD Integration
```yaml
# GitLab CI example
build-iso:
  stage: build
  script:
    - ./remaster-opnsense.sh config.xml
    - mv opnsense-custom.iso opnsense-${CI_COMMIT_SHORT_SHA}.iso
  artifacts:
    paths:
      - opnsense-*.iso
    expire_in: 1 week
```

### Version Control
```bash
# Track configurations
git add config.xml remaster-opnsense.sh
git commit -m "OPNsense config for production deployment"
git tag v1.0.0
```

## Security Considerations

1. **Protect config.xml**: Contains sensitive data (passwords, keys)
2. **Secure ISO Storage**: Custom ISOs contain your configuration
3. **Use Strong Passwords**: Even with key auth, set strong root password
4. **Limit SSH Access**: Configure firewall rules after deployment
5. **Regular Updates**: Rebuild ISO with latest OPNsense version

## Conclusion

ISO remastering provides the most reliable method for 100% hands-off OPNsense deployment. By embedding configuration directly into the installation ISO, we eliminate all manual steps and achieve true automation. This approach is:

- **Reliable**: No dependency on console access or filesystem drivers
- **Repeatable**: Same ISO produces identical deployments
- **Scalable**: Deploy hundreds of instances with same configuration
- **Maintainable**: Version control your infrastructure

The investment in setting up the remastering process pays off immediately with consistent, automated deployments that require zero manual intervention.