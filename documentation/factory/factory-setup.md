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
  status ENUM('building', 'ready', 'failed') NOT NULL,
  build_time TIMESTAMP,
  build_duration_seconds INT,
  test_results JSON,
  error_log TEXT,
  last_heartbeat TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_status (status),
  INDEX idx_last_heartbeat (last_heartbeat)
);

-- Records deleted after successful labeling
-- Only 'failed' units remain for analysis
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

## Stuck Build Detection

```
Server-side monitoring:
- If heartbeat stops for >5 minutes without success/failure POST
- Mark unit as "stuck"
- Alert operator to check physical unit on that port
- Common causes:
  * Network cable unplugged
  * Power loss
  * Proxmox installer hung
  * Bootstrap script error
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

### Phase 4: Debug Support
- [ ] Debug station monitors port 22
- [ ] Automated log collection script
- [ ] Debug log storage endpoint
- [ ] Failure analysis queries

### Phase 5: Testing & Refinement
- [ ] Test with 5 units (find edge cases)
- [ ] Measure actual build times
- [ ] Refine self-tests based on real failures
- [ ] Optimize operator workflow at label station
- [ ] Document common failure modes

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
| ProCurve 2810-24G | 1 | [In hand] | Used/refurb acceptable |
| APC SmartUPS 1500 | 1 | [Pending] | ~2,000 DKK used |
| Zebra TLP 2844 | 4 | 830 | Excellent price |
| PrivateBox (production) | 1 | 1,150 | Dogfooding unit |
| Cables, misc | - | 500 | Estimate |
| **Total** | | **~4,500 DKK** | One-time setup cost |

**Per-unit production cost:** 1,150 DKK (hardware only)
**Factory infrastructure:** 4,500 DKK (reusable, scales to 1000s of units)

---

**Document Status:** Ready for implementation
**Last Updated:** 2025-09-29
**Next Review:** After first 20-unit production run