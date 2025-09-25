# Verify Script Hang Investigation

## Problem Summary
The `verify-install.sh` script hangs during PrivateBox deployment, preventing completion of the installation process.

## Root Cause Analysis

### The Chain of Events
1. **Port Configuration Change**: Unbound DNS was changed from port 53 to 5353 on OPNsense
2. **DNS Resolution Failure**: Management VM (10.10.20.10) cannot resolve DNS
3. **APT Package Update Stuck**: `setup-guest.sh` hangs on `apt-get update`
4. **Missing Marker File**: `/etc/privatebox-install-complete` never gets created
5. **Verification Timeout**: `verify-install.sh` waits indefinitely for the marker file

### Technical Details

#### 1. DNS Configuration Issue
**VM DNS Configuration** (`/etc/resolv.conf`):
```
nameserver 10.10.20.1
```
- VM expects DNS on standard port 53
- OPNsense Unbound now listening on port 5353
- Result: DNS queries timeout

**Evidence**:
```bash
# From VM 10.10.20.10
$ host deb.debian.org
;; communications error to 10.10.20.1#53: timed out
;; no servers could be reached

# But network connectivity is fine
$ ping 8.8.8.8
64 bytes from 8.8.8.8: icmp_seq=1 ttl=114 time=23.4 ms
```

#### 2. Setup Script Stuck on APT
**Process Tree**:
```
bash(822)-+-apt-get(828)-+-file(833)
          |              |-https(835)
          |              `-mirror+file(831)
          `-tee(825)
```
- PID 822: `/bin/bash /usr/local/bin/setup-guest.sh`
- Stuck at: "Updating package lists..."
- Unable to resolve: `deb.debian.org`

**Log Output** (`/var/log/privatebox-guest-setup.log`):
```
[2025-09-25 20:25:27] Starting guest configuration...
[2025-09-25 20:25:27] Updating package lists...
Get:1 file:/etc/apt/mirrors/debian.list Mirrorlist [30 B]
Ign:3 https://deb.debian.org/debian trixie InRelease
```

#### 3. Verification Script Design
The `verify-install.sh` script:
- Waits for VM to be accessible (✓ works)
- Waits for `/etc/privatebox-install-complete` marker file
- Has a 900-second (15-minute) timeout
- Uses SSH with `ConnectTimeout=5` (good practice)
- But the marker file never appears because setup is stuck

## Impact

### Immediate Effects
- Deployment appears to hang indefinitely
- Services (Portainer, Semaphore) never fully configure
- Installation never completes successfully
- User must manually kill the process

### Cascading Issues
- Management VM remains partially configured
- No DNS resolution for package management
- Cannot install or update software
- Services may not start properly

## Solutions

### Option 1: NAT Port Forwarding (Quick Fix)
Configure OPNsense to forward DNS queries:
- Forward 10.10.20.1:53 → 10.10.20.1:5353
- Maintains port 5353 for Unbound
- Allows standard DNS queries to work

### Option 2: Configure VM for Port 5353 (Proper Fix)
Update VM configuration to use non-standard DNS port:
- Modify cloud-init to configure systemd-resolved
- Set DNS to `10.10.20.1:5353`
- Requires changes to VM provisioning

### Option 3: Run DNS on Both Ports (Compatibility)
Configure Unbound to listen on both ports:
- Primary: Port 5353 (for AdGuard)
- Secondary: Port 53 (for VMs and standard clients)
- Most compatible but uses standard DNS port

### Option 4: Use Different DNS During Setup
Configure VM to use external DNS during setup:
- Use 8.8.8.8 or 9.9.9.9 during provisioning
- Switch to OPNsense DNS after setup completes
- Requires cloud-init modification

## Recommended Fix

**Short Term**: Option 1 (NAT Port Forwarding)
- Quickest to implement
- No changes to VM provisioning
- Maintains port separation goal

**Long Term**: Option 2 (Configure VM for Port 5353)
- Properly configured infrastructure
- Clear port usage separation
- Requires updating provisioning scripts

## Verification Script Improvements

While not the root cause, the script could be improved:
1. Add timeout to apt-get operations in setup-guest.sh
2. Add DNS connectivity check before apt operations
3. Implement health checks with better error reporting
4. Add circuit breaker for repeated failures

## Key Takeaway

The port change from 53 to 5353 for Unbound DNS has broader implications than initially considered. Any system using OPNsense for DNS needs to be configured for the non-standard port, or a forwarding mechanism needs to be in place. This is a classic example of how infrastructure changes can have cascading effects on dependent systems.