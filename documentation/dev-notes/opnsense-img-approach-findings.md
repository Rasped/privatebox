# OPNsense IMG Approach Findings

## Date: 2025-07-27

### What We Tried
1. Downloaded OPNsense VGA IMG (pre-installed disk image)
2. Imported IMG as VM disk using `qm importdisk`
3. Resized disk from 2.5GB to 16GB
4. Created FAT32 USB with config.xml
5. Attempted installation

### Issues Discovered

#### 1. IMG is NOT Pre-installed
- Documentation was misleading
- VGA IMG still boots to live environment
- Requires full installation process just like ISO

#### 2. Disk Corruption After Import/Resize
- Imported IMG disk shows as corrupt during installation
- Error: "Operation is not permitted, table da0 is corrupt"
- Likely caused by:
  - IMG contains partition table that doesn't handle resize well
  - Import process doesn't properly initialize disk structure
  - Resize operation corrupts partition table

#### 3. Serial Console Issues
- Serial IMG outputs to VGA by default
- Expect script couldn't monitor serial console
- No actual serial output without boot parameters

### Conclusion
The IMG approach doesn't provide any advantages over ISO:
- Still requires installation
- Adds complexity with import/resize
- Causes disk corruption issues
- No time saved vs ISO approach

### Recommended Approach
Return to DVD ISO with:
1. Create VM with fresh empty disk
2. Attach DVD ISO as boot device
3. Attach USB config for post-install import
4. Automate installation prompts
5. Let config import happen on first boot

The ISO approach is cleaner and avoids disk corruption issues.