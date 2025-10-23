# Factory Setup - Parallel Production System

## Overview

Zero-touch parallel production of PrivateBox units. Each unit self-builds, self-tests, and reports completion to production server. No human intervention until labeling station.

**Key Design Principles:**
- Fully automated from power-on to ready-to-ship
- Self-reporting via production API (units tell us when done)
- MAC-based tracking (physical identifier, no confusion)
- No confidential data retention (credentials deleted after labeling)
- Scales to 20 parallel builds

## Hardware Configuration

### ProCurve 2810 Switch Port Map

```
Ports 1-20:  Build Stations (factory network, 192.168.100.0/24)
Port 21:     Labeling Station (monitored by print server)
Port 22:     Debug Station (for failed units)
Port 23:     Production Server (API + CDN + print monitor)
Port 24:     Uplink (internet access)
```

### Per-Unit Physical Setup

```
PrivateBox Unit:
├── WAN Port → ProCurve Port N (ports 1-20)
└── LAN Port → UNPLUGGED (stays unplugged during build)

Why LAN unplugged:
- Allows 20 parallel builds (no port conflicts)
- LAN only used by end customer
- All build communication via WAN
```

### Network Architecture During Build

```
Factory Network (192.168.100.0/24):
├── Ports 1-20: Build units (get DHCP, build behind OPNsense)
├── Port 23: Production server (192.168.100.250)
└── Port 24: Internet gateway

Inside Each Unit (after OPNsense deploys):
├── OPNsense WAN: 192.168.100.X (temporary, factory only)
├── OPNsense LAN: 10.10.20.1 (production network)
├── Proxmox: 10.10.20.20 (behind OPNsense)
└── Management VM: 10.10.20.10 (behind OPNsense)
```

## Build Flow (Automated, Zero-Touch)

### Phase 1: Proxmox Installation
```
1. Unit powered on, boots from Proxmox installer USB
2. answer.toml runs post-install script:
   curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash
3. Proxmox boots with WAN on factory network (192.168.100.X via DHCP)
```

### Phase 2: Bootstrap Execution
```
4. Quickstart detects factory network, runs bootstrap
5. Bootstrap generates unique credentials:
   - SERIAL: UUID (e.g., a1b2c3d4-5678-90ab-cdef-1234567890ab)
   - ADMIN_PASSWORD: Phonetic password for SSH
   - SERVICES_PASSWORD: Phonetic password for web UIs
6. Deploys OPNsense VM:
   - WAN: Connected to vmbr0 (factory network)
   - LAN: Creates 10.10.20.0/24 internal network
7. Deploys Management VM behind OPNsense
8. Starts services: Portainer, Semaphore, AdGuard, Homer
```

### Phase 3: Heartbeat (During Build)
```
9. Every 60 seconds during build, unit sends heartbeat:
   POST https://192.168.100.250/api/heartbeat
   {
     "mac_wan": "aa:bb:cc:dd:ee:ff",
     "status": "building",
     "stage": "deploying_services",
     "timestamp": "2025-09-29T12:34:56Z"
   }

Purpose:
- Production server knows which units are actively building
- If heartbeat stops without success POST, unit is stuck
- Helps identify which port has problem unit
```

### Phase 4: Self-Test Execution
```
10. Bootstrap completes, self-test script runs:
    ├── OPNsense routing to internet ✓
    ├── Management VM accessible at 10.10.20.10 ✓
    ├── Portainer UI loads (9000) ✓
    ├── Semaphore API responds (3000) ✓
    ├── AdGuard resolving DNS (53) ✓
    ├── Homer dashboard loads (8080) ✓
    └── All systemd services active ✓

11. If all tests pass:
    - Remove Proxmox WAN IP (now fully behind OPNsense)
    - Verify isolation (Proxmox only reachable via 10.10.20.20)

12. If removal fails or isolation test fails:
    - Restore Proxmox WAN IP
    - POST failure to production server
    - Unit remains accessible for debugging
```

### Phase 5: Success Reporting
```
13. POST to production server:
    POST https://192.168.100.250/api/units
    {
      "mac_wan": "aa:bb:cc:dd:ee:ff",
      "serial": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
      "admin_password": "confett1-j0gging-App3NDix",
      "services_password": "4ntENNAe-B4sil-mat3rnIty",
      "status": "ready",
      "build_time": "2025-09-29T12:45:23Z",
      "build_duration_seconds": 847,
      "test_results": {
        "opnsense_routing": "pass",
        "management_vm": "pass",
        "portainer": "pass",
        "semaphore": "pass",
        "adguard": "pass",
        "homer": "pass",
        "isolation": "pass"
      }
    }

14. Unit is now in "ready" state, waiting for labeling
```

### Phase 6: Failure Handling
```
If any test fails:
1. Restore Proxmox WAN IP (for remote access)
2. Collect diagnostic data:
   - /tmp/privatebox-bootstrap.log
   - /var/log/privatebox-guest-setup.log
   - systemctl status output for all services
   - Network configuration
3. POST failure to production server:
   POST https://192.168.100.250/api/units
   {
     "mac_wan": "aa:bb:cc:dd:ee:ff",
     "status": "failed",
     "build_time": "2025-09-29T12:45:23Z",
     "error_log": "...",
     "failed_tests": ["adguard"],
     "diagnostic_data": "..."
   }
4. Unit remains on build port for debugging
```

## Quality Control & Burn-In Testing

### Overview

After successful bootstrap deployment, each unit undergoes 22-hour automated burn-in testing. Tests run unattended, results POST to production server, no manual intervention required.

**Why 22 hours:**
- Catches thermal issues (temperature cycling overnight)
- RAM stress testing (most failures <8 hours, 22h for confidence)
- SSD thermal stability validation (cold vs warm testing)
- Professional standard ("24-hour burn-in tested")
- Time available at current scale (3 batches/month = 60 units)

**Automated workflow:**
- Units test overnight
- Dashboard shows pass/fail status
- Failed units flagged for RMA
- Passed units ready to ship
- Zero manual monitoring

### Testing Strategy

**Focus: SSD quality > RAM quality**

Modern DDR5 RAM is highly reliable (<0.1% failure rate). Budget SSDs have higher failure rates (1-3%) and quality variance.

**SSD risks:**
- Used drives sold as new (check Data Units Written)
- Component lottery (UMIS vs Samsung quality difference)
- Thermal throttling (controller overheats under load)
- Silent corruption (bad sectors accumulate)
- Fake capacity drives

**RAM risks:**
- Catastrophic failure (rare, caught immediately)
- Subtle bit flips (very rare with modern DDR5)

### Phase 7: Extended Burn-In Testing

```
15. Bootstrap complete, begin 22-hour burn-in:

    Hour 0 - Initial SSD Test (Cold):
    ├── Check Data Units Written (<100GB = new)
    ├── SMART health check (no errors/warnings)
    ├── Write performance test (~10GB write)
    ├── Read back + checksum verify
    ├── Document: brand, model, serial, performance
    └── POST baseline metrics to server

    Hour 0-22 - Continuous RAM Stress:
    ├── RAM stress test (stress-ng --vm, 90% memory)
    ├── CPU load (4 cores active)
    ├── VMs + containers remain running
    ├── Thermal monitoring (CPU, SSD temps)
    └── Heartbeat every 60 seconds

    Hour 16 - Warm SSD Test:
    ├── System running hot (8+ hours under load)
    ├── Repeat performance test (~10GB write)
    ├── Compare to hour 0 baseline
    ├── Check for thermal throttling (>20% slowdown)
    ├── SMART check (any new errors?)
    └── POST comparison metrics

    Hour 22 - Final Validation:
    ├── RAM stress complete (0 errors = pass)
    ├── All services still responding
    ├── System stable under prolonged load
    ├── Thermal performance acceptable
    └── Ready for final reporting

Total SSD writes during testing:
- Bootstrap deployment: ~50GB
- Hour 0 test: ~10GB
- Hour 16 test: ~10GB
- Monitoring/logs: ~10GB
- Total: ~80GB (still "new" drive, <100GB acceptable)
```

### Component Validation

**Every unit documents:**
- RAM: Brand, part number, capacity, speed
- SSD: Brand, model, serial, Data Units Written
- NIC: Intel i226-V revision (must be rev 03+)
- Performance baselines (cold/warm comparison)

**Consistency checking:**
- Units 1-10 should have same component brands
- Component lottery = quality variance
- Flag mismatches for supplier discussion

**Supplier negotiation leverage:**
- "Units 1-5 had Crucial RAM, units 6-10 had no-name brand"
- "Lock in component brands for future orders"
- "I'll pay €10 more for Crucial SSDs vs UMIS"

### Test Results POST Format

```json
POST https://192.168.100.250/api/units
{
  "mac_wan": "aa:bb:cc:dd:ee:ff",
  "serial": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
  "status": "burn_in_complete",
  "build_time": "2025-09-29T12:45:23Z",
  "burn_in_duration_hours": 22,

  "components": {
    "ram_manufacturer": "Crucial Technology",
    "ram_part_number": "CT8G48C40S5.M4A1",
    "ram_capacity_gb": 16,
    "ssd_model": "Samsung 980 PRO",
    "ssd_serial": "S5GXNX0T123456",
    "ssd_initial_writes_gb": 45,
    "nic_model": "Intel i226-V",
    "nic_revision": "04"
  },

  "test_results": {
    "bootstrap": "pass",
    "services": "pass",

    "ssd_cold_test": {
      "status": "pass",
      "write_iops": 35240,
      "write_mbps": 1820,
      "smart_status": "PASSED",
      "critical_warning": 0,
      "available_spare": 100,
      "temperature_c": 42
    },

    "ram_stress_test": {
      "status": "pass",
      "duration_hours": 22,
      "errors": 0,
      "max_temperature_c": 68
    },

    "ssd_warm_test": {
      "status": "pass",
      "write_iops": 33180,
      "write_mbps": 1750,
      "performance_drop_percent": 6,
      "temperature_c": 58,
      "throttling_detected": false
    },

    "thermal_stability": "pass",
    "overall": "pass"
  }
}
```

### Failure Scenarios

**RAM stress test failure:**
```
Status: "burn_in_failed"
Failed test: "ram_stress_test"
Error: "Memory errors detected after 8 hours"
Action: RMA unit, bad RAM
```

**SSD thermal throttling:**
```
Status: "burn_in_failed"
Failed test: "ssd_warm_test"
Error: "Performance drop 35% (cold: 1800 MB/s, warm: 1170 MB/s)"
Action: Investigate cooling, possible RMA
```

**SSD used/fake:**
```
Status: "burn_in_failed"
Failed test: "ssd_cold_test"
Error: "Data Units Written: 2.4TB (not new)"
Action: RMA unit, supplier sent used drive
```

**System instability:**
```
Status: "burn_in_failed"
Failed test: "thermal_stability"
Error: "System crashed after 14 hours under load"
Action: Check logs, investigate root cause, likely RMA
```

### DIY User Considerations

**Burn-in tests are optional for DIY users:**

Environment variable controls testing:
- `SKIP_BURN_IN=1` → Skip 22-hour tests
- `BURN_IN_HOURS=4` → Shorter test (4 hours)
- Default (no variable) → Full 22-hour test

**Why skip for DIY:**
- They want faster deployment (not QC)
- They'll discover issues in their own usage
- Production server not reachable (tests fail gracefully)

**Test behavior when production server unreachable:**
- Tests run normally
- Results logged locally: `/var/log/privatebox-burn-in.log`
- POST attempts fail silently (no error to user)
- Unit still fully functional

### Production Dashboard

**Real-time burn-in monitoring:**

```
Burn-In Testing Dashboard (http://192.168.100.250/burn-in)

Active Tests (10 units):
├── Port 1: Hour 18/22 (RAM: pass, awaiting warm SSD test)
├── Port 2: Hour 22/22 (Complete ✓, ready to ship)
├── Port 3: Hour 4/22 (RAM: testing, SSD cold: pass)
├── Port 4: FAILED (SSD thermal throttling detected)
└── Ports 5-10: Testing...

Completed Today: 3 units
Failed Today: 1 unit (thermal issue)
Success Rate This Batch: 75% (processing)

Component Consistency:
├── RAM: All units Crucial CT8G48C40S5.M4A1 ✓
├── SSD: Units 1-5 Samsung, Units 6-10 UMIS ⚠️ (inconsistent)
└── NIC: All units i226-V rev 04 ✓
```

### Quality Metrics to Track

**Per batch (10-20 units):**
- Burn-in failure rate
- Most common failure type
- Component brand consistency
- Average burn-in duration
- SSD thermal performance (cold vs warm)

**Supplier quality trends:**
- DOA rate over time
- Component lottery frequency
- Used drive incidents
- Warranty claim rate (first 90 days)

**Decision triggers:**
- Failure rate >10% → Full batch inspection
- Failure rate >20% → Reject batch, demand replacement
- Used drives detected → Stop orders, investigate supplier
- Component inconsistency → Lock in brands with supplier

## Production Server

### Hardware: PrivateBox Unit (Dogfooding)

**Why use our own product as production server:**
- Real-world stress test (24/7 operation, critical role)
- Validates hardware reliability before selling
- Tests full software stack under load
- Demonstrates confidence in product
- Same hardware customers receive (authentic testing)
- If it can't handle factory coordination, it's not ready to ship

**Configuration:**
- Standard PrivateBox unit (Intel N150, 16GB RAM, 256GB SSD)
- Connected to factory network (192.168.100.250)
- Runs all factory services:
  - Proxmox VE (hypervisor)
  - Production API VM (FastAPI/Flask)
  - Database VM (PostgreSQL or SQLite)
  - CDN server (nginx)
  - Print server (monitors port 21)
  - Monitoring dashboard
- Additional load: 4x USB printers, ProCurve monitoring

**What this proves:**
- Hardware handles 24/7 operation
- RAM sufficient for multiple VMs + database
- Storage performs under continuous read/write
- Network interfaces stable under sustained traffic
- Thermal management adequate
- Power consumption reasonable (on UPS)

If production server fails, we know there's a hardware issue before it ships to customers.

### Responsibilities
1. **Factory coordination API** - Track build status, store credentials
2. **CDN for offline assets** - Serve Debian images, containers, templates
3. **Print server** - Monitor labeling port, trigger label printing
4. **Heartbeat monitoring** - Detect stuck builds
5. **Remote unit monitoring** - SSH to stuck units, auto-collect diagnostics
6. **PXE boot server** - Network boot Proxmox installer (eliminates USB sticks)

### API Endpoints

```
POST /api/heartbeat
- Units report progress every 60 seconds
- Body: { "mac_wan", "status", "stage", "timestamp" }

POST /api/units
- Unit reports success or failure
- Body: { "mac_wan", "serial", "passwords", "status", "test_results" }

GET /api/units/{mac_wan}
- Query unit status and credentials by MAC
- Returns: { "serial", "passwords", "status", "build_time" }

DELETE /api/units/{mac_wan}
- Delete unit record after successful labeling
- No credentials remain in database
```

### Database Schema

```sql
CREATE TABLE units (
  mac_wan VARCHAR(17) PRIMARY KEY,
  serial VARCHAR(36) NOT NULL,
  admin_password VARCHAR(128),
  services_password VARCHAR(128),
  status ENUM('building', 'testing', 'burn_in', 'ready', 'failed') NOT NULL,
  build_time TIMESTAMP,
  build_duration_seconds INT,
  burn_in_start TIMESTAMP,
  burn_in_duration_hours INT,
  test_results JSON,
  error_log TEXT,
  last_heartbeat TIMESTAMP,

  -- Component information
  ram_manufacturer VARCHAR(64),
  ram_part_number VARCHAR(64),
  ram_capacity_gb INT,
  ssd_model VARCHAR(128),
  ssd_serial VARCHAR(128),
  ssd_initial_writes_gb INT,
  nic_model VARCHAR(64),
  nic_revision VARCHAR(16),

  -- Burn-in test results
  ssd_cold_write_mbps INT,
  ssd_cold_temp_c INT,
  ssd_warm_write_mbps INT,
  ssd_warm_temp_c INT,
  ssd_throttling_detected BOOLEAN,
  ram_stress_errors INT,
  ram_max_temp_c INT,

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_status (status),
  INDEX idx_last_heartbeat (last_heartbeat),
  INDEX idx_ram_manufacturer (ram_manufacturer),
  INDEX idx_ssd_model (ssd_model)
);

-- Records deleted after successful labeling
-- Only 'failed' units remain for analysis

-- Query component consistency
-- SELECT ram_manufacturer, COUNT(*) FROM units
-- WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
-- GROUP BY ram_manufacturer;
```

### CDN Asset Storage

```
Production server serves locally:
/cdn/
├── images/
│   └── debian-13-genericcloud-amd64.qcow2 (324MB)
├── containers/
│   ├── semaphore-base-latest.tar (809MB)
│   ├── portainer-ce-latest.tar (178MB)
│   ├── adguard-home-latest.tar (72MB)
│   └── homer-latest.tar (16MB)
├── templates/
│   └── opnsense-template.vma.zst (767MB)
└── source/
    └── privatebox-main.tar.gz (2MB)

Bootstrap checks local CDN first, falls back to internet if missing
Speeds up builds and reduces internet dependency
```

### PXE Boot Server

**Purpose:** Eliminate USB stick requirement - units boot Proxmox installer over network

```
/pxe/
├── pxelinux.0 (TFTP bootloader)
├── proxmox-ve_*.iso (Proxmox installer ISO)
├── answer.toml (automated installation configuration)
└── post-install.sh (calls quickstart.sh after Proxmox install)
```

**How it works:**

1. **DHCP Configuration:**
   - Production server runs DHCP on factory network
   - Offers IP to booting units (192.168.100.10-230)
   - Points to PXE boot server: `next-server 192.168.100.250`

2. **PXE Boot Process:**
   - Unit powers on, requests DHCP
   - Gets IP + PXE server address
   - TFTP downloads pxelinux.0 bootloader
   - Bootloader downloads Proxmox installer
   - Installer uses answer.toml for automated installation

3. **Answer File (answer.toml):**
```toml
[global]
keyboard = "dk"
country = "dk"
fqdn = "privatebox.local"
mailto = ""
timezone = "Europe/Copenhagen"
root_password = "changeme"  # Changed by customer

[network]
source = "from-dhcp"  # Uses factory DHCP

[disk-setup]
filesystem = "zfs"
disk_list = ["sda"]
zfs_opts = "compress=on"

[post-install]
# Run quickstart after installation completes
run = "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"
```

4. **Post-Install Hook:**
   - Proxmox installs automatically
   - Post-install hook runs quickstart.sh
   - Bootstrap begins immediately
   - Zero human intervention from power-on to self-test

**Benefits:**
- No USB sticks to manage (lose, corrupt, wear out)
- Faster deployment (network boot faster than USB)
- Consistent installation (same answer file every time)
- Easy updates (change answer.toml once, affects all units)
- True zero-touch (power on → built → labeled)

**ProCurve DHCP Configuration:**
```
# DHCP server on production VM (192.168.100.250)
# ProCurve forwards DHCP requests
ip helper-address 192.168.100.250
```

**Production Server DHCP (dnsmasq):**
```
dhcp-range=192.168.100.10,192.168.100.230,12h
dhcp-boot=pxelinux.0,192.168.100.250
enable-tftp
tftp-root=/srv/tftp
```

## Labeling Station (Port 21)

### Workflow

```
1. Operator moves completed unit from build port to labeling port (21)

2. Print server detects new MAC address on port 21:
   - Monitors ProCurve via SNMP or port mirroring
   - Detects link-up event with new MAC

3. Print server queries production API:
   GET /api/units/{mac_wan}
   Returns: {
     "serial": "a1b2c3d4-5678-90ab...",
     "admin_password": "confett1-j0gging-App3NDix",
     "services_password": "4ntENNAe-B4sil-mat3rnIty",
     "status": "ready"
   }

4. Print server prompts operator:
   "Print label for unit {serial}? (yes/no)"

5. If yes, prints label containing:
   ┌─────────────────────────────┐
   │ PrivateBox                  │
   │ Serial: a1b2c3d4-5678...    │
   │ SSH: confett1-j0gging...    │
   │ Web: 4ntENNAe-B4sil...      │
   │ privatebox.dk/setup         │
   └─────────────────────────────┘

6. Print server prompts operator:
   "Label printed successfully? (yes/no)"

7. If yes:
   - DELETE /api/units/{mac_wan}
   - Credential record removed from database
   - Unit ready for packaging

8. If no (label jam, print failure):
   - Operator can retry: replug unit into port 21
   - Process repeats from step 2
```

### Label Misprint Recovery

If operator says "no" to successful print:
- Unit remains in database
- Simply replug into port 21
- Print server re-queries and prints again
- No manual intervention needed

### Zebra TLP 2844 Printer Details

**Specifications:**
- Resolution: 203 DPI (8 dots/mm)
- Max print width: 4 inches (102mm)
- Max print speed: 4 inches/second
- Interface: USB to production server
- Language: ZPL (Zebra Programming Language)
- Media: Thermal transfer labels (no ink required)

**Label Format (ZPL):**
```zpl
^XA
^FO50,50^A0N,40,40^FDPrivateBox^FS
^FO50,100^BY2^BCN,100,Y,N,N^FD{serial}^FS
^FO50,220^A0N,25,25^FDSSH: {admin_password}^FS
^FO50,260^A0N,25,25^FDWeb: {services_password}^FS
^FO50,300^A0N,20,20^FDprivatebox.dk/setup^FS
^XZ
```

**Print Command (Python):**
```python
import usb.core
import usb.util

def print_label(serial, admin_pass, services_pass):
    # Find Zebra printer on USB
    dev = usb.core.find(idVendor=0x0a5f, idProduct=0x0009)

    zpl = f"""
    ^XA
    ^FO50,50^A0N,40,40^FDPrivateBox^FS
    ^FO50,100^BY2^BCN,100,Y,N,N^FD{serial}^FS
    ^FO50,220^A0N,25,25^FDSSH: {admin_pass}^FS
    ^FO50,260^A0N,25,25^FDWeb: {services_pass}^FS
    ^FO50,300^A0N,20,20^FDprivatebox.dk/setup^FS
    ^XZ
    """

    dev.write(1, zpl.encode())
```

**Benefits of Zebra TLP 2844:**
- Industrial reliability (100,000+ labels)
- Fast printing (label in ~2 seconds)
- No consumables except labels
- Simple USB interface
- Standard ZPL language (well documented)
- 2 spares ensure production continuity

## Debug Station (Port 22)

### For Failed Units

```
1. Failed unit moved to debug port 22
2. Debug script auto-executes (monitors port 22):
   - SSH to unit via factory network (still has WAN IP)
   - Pull all logs:
     * /tmp/privatebox-bootstrap.log
     * /var/log/privatebox-guest-setup.log
     * journalctl -u portainer.service
     * journalctl -u semaphore.service
     * systemctl --failed
     * ip addr show
     * ss -tlnp
   - Save to production server: POST /api/debug-logs
3. Unit formatted and retried, or set aside for hardware inspection
```

### Failure Analysis

```sql
-- Query failed builds
SELECT mac_wan, error_log, failed_tests, build_time
FROM units
WHERE status = 'failed'
ORDER BY build_time DESC;

-- Common failure patterns
SELECT failed_tests, COUNT(*) as count
FROM units
WHERE status = 'failed'
GROUP BY failed_tests
ORDER BY count DESC;
```

## Build Monitoring Dashboard (Optional)

Real-time view on production server:

```
Factory Dashboard (http://192.168.100.250)

Active Builds:
├── Port 1: Building... (Stage: deploying_services) [3m 24s]
├── Port 2: Building... (Stage: self_test) [8m 12s]
├── Port 3: Ready ✓ (awaiting labeling)
└── Port 4-20: Empty

Ready for Labeling: 5 units
Failed: 1 unit (Port 17 - adguard test failed)

Last 10 Completed:
1. MAC aa:bb:cc... → Labeled at 12:34:56 ✓
2. MAC dd:ee:ff... → Labeled at 12:28:43 ✓
...
```

## Stuck Build Detection & Remote Diagnostics

### Detection
```
Server-side monitoring:
- If heartbeat stops for >5 minutes without success/failure POST
- Mark unit as "stuck"
- Automatically SSH to unit and collect diagnostics
- Alert operator with debug data

Common causes:
  * Network cable unplugged
  * Power loss
  * Proxmox installer hung
  * Bootstrap script error
  * Out of memory/disk space
  * CDN download timeout
```

### Automatic Diagnostic Collection

When a unit is stuck, production server automatically collects diagnostics via SSH:

```python
def debug_stuck_unit(mac_wan, proxmox_ip):
    """SSH to stuck unit and collect logs automatically"""

    diagnostics = {}

    # Bootstrap log (where did it fail?)
    diagnostics['bootstrap_log'] = ssh_exec(
        f"root@{proxmox_ip}",
        "tail -100 /tmp/privatebox-bootstrap.log"
    )

    # Guest setup log (if VM exists)
    diagnostics['guest_log'] = ssh_exec(
        f"root@{proxmox_ip}",
        "ssh debian@10.10.20.10 'tail -100 /var/log/privatebox-guest-setup.log' 2>/dev/null"
    )

    # System status
    diagnostics['vms'] = ssh_exec(f"root@{proxmox_ip}", "qm list")
    diagnostics['disk'] = ssh_exec(f"root@{proxmox_ip}", "df -h")
    diagnostics['memory'] = ssh_exec(f"root@{proxmox_ip}", "free -h")

    # Store for operator review
    save_debug_data(mac_wan, diagnostics)

    return diagnostics
```

**Security:** Only works during build phase (Proxmox has WAN IP). After self-test, Proxmox WAN removed - SSH no longer possible.

### Enhanced Heartbeat

Include Proxmox IP in heartbeat to enable SSH access:

```bash
POST /api/heartbeat
{
  "mac_wan": "aa:bb:cc:dd:ee:ff",
  "proxmox_ip": "192.168.100.17",  # For SSH debugging
  "status": "building",
  "stage": "deploying_services",
  "timestamp": "2025-09-29T12:34:56Z"
}
```

## Quality Control Metrics

Track over time:
- Build success rate
- Average build duration
- Most common test failures
- Failed hardware patterns (MAC address clusters)
- Operator labeling errors (how many reprints?)

```sql
-- Success rate by date
SELECT DATE(build_time) as date,
       COUNT(*) FILTER (WHERE status='ready') as success,
       COUNT(*) FILTER (WHERE status='failed') as failed,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status='ready') / COUNT(*), 2) as success_rate
FROM units
GROUP BY DATE(build_time)
ORDER BY date DESC;
```

## Implementation Checklist

### Phase 1: Core Build System
- [ ] Proxmox answer.toml with post-install hook
- [ ] Self-test script (tests all services)
- [ ] Proxmox WAN removal automation
- [ ] Isolation verification test
- [ ] Success POST implementation
- [ ] Failure POST with diagnostic collection

### Phase 2: Production Server
- [ ] Database schema creation
- [ ] API endpoints (heartbeat, units CRUD)
- [ ] Heartbeat monitoring (detect stuck builds)
- [ ] CDN asset storage and serving
- [ ] Web dashboard (optional, for monitoring)

### Phase 3: Print Integration
- [ ] Print server monitors port 21 (MAC detection)
- [ ] Query API for credentials
- [ ] Operator prompts (print? success?)
- [ ] Label template design
- [ ] DELETE record after confirmation

### Phase 4: Burn-In Testing
- [ ] SSD cold test script (hour 0)
- [ ] RAM stress test script (22 hours continuous)
- [ ] SSD warm test script (hour 16)
- [ ] Component documentation script
- [ ] Test results POST to production API
- [ ] Burn-in dashboard (real-time monitoring)
- [ ] DIY skip option (SKIP_BURN_IN environment variable)

### Phase 5: Debug Support
- [ ] Debug station monitors port 22
- [ ] Automated log collection script
- [ ] Debug log storage endpoint
- [ ] Failure analysis queries
- [ ] Component consistency tracking
- [ ] SSD quality metrics (thermal throttling detection)

### Phase 6: Testing & Refinement
- [ ] Test with 5 units (find edge cases)
- [ ] Measure actual build times + burn-in duration
- [ ] Refine self-tests based on real failures
- [ ] Optimize operator workflow at label station
- [ ] Document common failure modes
- [ ] Track component lottery patterns
- [ ] Establish acceptable SSD thermal performance baselines

## Operating Procedures

### Starting Production Run

1. Ensure production server is running (port 23)
2. Verify internet uplink (port 24)
3. Clear any old records from database
4. Boot units on ports 1-20
5. Monitor dashboard for progress
6. Process completed units at labeling station as they finish

### End of Day

1. Check for stuck builds (no heartbeat)
2. Review failed units (debug station)
3. Export metrics (success rate, build times)
4. Verify no "ready" units left in database (all should be labeled and deleted)

### Maintenance

Weekly:
- Archive failed unit logs
- Update CDN assets (new Debian image, container versions)
- Review quality metrics (trending failures?)

Monthly:
- Test disaster recovery (production server failure)
- Verify backup of critical data
- Update documentation based on learnings

## Security Considerations

### During Build
- Factory network isolated (no internet exposure of units)
- Production server only accessible from factory network
- SSH keys generated uniquely per unit

### Post-Build
- No credentials stored after labeling (deleted from DB)
- Customer gets unique passwords on physical label
- No remote access to built units (everything behind OPNsense)

### Production Server
- Database encrypted at rest
- API authentication for sensitive endpoints (future)
- Regular backups of failure logs (for quality analysis only)

## Future Enhancements (Not v1)

- PXE boot server (eliminate USB stick requirement)
- Automated hardware testing (CPU, RAM, disk health)
- Barcode scanning at label station (instead of MAC detection)
- Customer-specific pre-configuration (VPN accounts, domain names)
- Batch tracking (group of 20 units = one batch ID)
- Shipping manifest generation (from labeled units)

## Troubleshooting

### Unit not reporting heartbeat
- Check physical connection on ProCurve
- Verify port has DHCP enabled
- Check Proxmox booted successfully (console access)

### All units failing same test
- Check production server is reachable
- Verify CDN assets are available
- Test bootstrap on development system first

### Labeling station not detecting unit
- Verify unit plugged into port 21 specifically
- Check print server monitoring script is running
- Manually query API with MAC to verify unit is "ready"

### Failed unit won't format/retry
- Check if WAN IP was restored (should be accessible)
- Console access via VGA if network unavailable
- Hardware fault likely (set aside for inspection)

## Bill of Materials

### Hardware (Actual)

**Network Infrastructure:**
- ProCurve 2810-24G switch (in hand)
- APC SmartUPS 1500 (battery backup + surge protection)
- Network cables (CAT6, various lengths)

**Production Server:**
- PrivateBox unit (Intel N150, 16GB RAM, 256GB SSD)
- Purpose: Factory coordination, API server, CDN, print server
- Benefit: Dogfooding - production server runs on same hardware we sell
- Connected to port 23 on factory network

**Printers (4x Zebra TLP 2844):**
- Primary unit labeling printer (port 21 station)
- Shipping label printer (separate workflow)
- 2x Spare units (production continuity)
- Cost: 830 DKK total (~208 DKK each)
- Type: Thermal transfer (reliable, fast, no ink/toner)
- Interface: USB to production server

**Build Hardware:**
- USB sticks for Proxmox installer (if not using PXE)
- VGA cables for console access (troubleshooting)
- KVM switch (optional, for debugging multiple units)

### Software

**Production Server Stack:**
- Proxmox VE 9.0 (hypervisor)
- Production API VM (FastAPI/Flask)
  - API server (units, heartbeat, debug logs)
  - CDN server (nginx serving local assets)
  - Print server (monitors ProCurve port 21)
  - Database (SQLite for simplicity, PostgreSQL if needed)
- Zebra printer driver (ZPL support)

**Build Software:**
- Proxmox VE installer with custom answer.toml
- PrivateBox bootstrap (from GitHub main)
- Self-test scripts
- Heartbeat reporting

### Network Configuration

**Factory Network: 192.168.100.0/24**
- Gateway: 192.168.100.1 (router/firewall)
- Production server: 192.168.100.250
- DHCP pool: 192.168.100.10-230 (build units)
- Isolated from corporate/office network

**Power Protection:**
- SmartUPS 1500 backs up:
  - ProCurve switch
  - Production server
  - Primary label printer
  - Router/internet gateway
- Build units NOT on UPS (can handle power loss mid-build)

### Cost Summary

| Item | Quantity | Cost (DKK) | Notes |
|------|----------|------------|-------|
| ProCurve 2810-24G | 1 | 100 | Excellent used deal |
| APC SmartUPS 1500 | 1 | 1,400 | Used market |
| Zebra TLP 2844 | 4 | 830 | 208 DKK each |
| PrivateBox (production) | 1 | 1,150 | Dogfooding unit |
| Cables, misc | - | 500 | Estimate |
| **Total** | | **~4,000 DKK** | One-time setup cost |

**Per-unit production cost:** 1,150 DKK (hardware only)
**Factory infrastructure:** 4,000 DKK (reusable, scales to 1000s of units)

**ROI calculation:**
- Infrastructure investment: 4,000 DKK
- Profit per unit: ~1,100 DKK (at 45% margin)
- Break-even: 4 units sold
- After 20 units: 22,000 DKK profit (infrastructure paid off 5.5x)

---

**Document Status:** Ready for implementation
**Last Updated:** 2025-09-29
**Next Review:** After first 20-unit production run