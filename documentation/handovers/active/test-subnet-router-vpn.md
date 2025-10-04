# Handover: Test Headscale Subnet Router VPN

**Status**: Ready for Testing
**Created**: 2025-10-04
**Updated**: 2025-10-04 (Firewall configuration added)
**Context**: Implementation complete, needs full end-to-end validation including internet access

---

## What Was Implemented

### 1. Network Fixes (Committed, Tested)
- ✅ DNS configuration: Changed from 10.10.20.1 to 10.10.20.10 (AdGuard) in all VLANs
- ✅ VLAN tagging: Removed tag=10 from subnet router net0 (LAN is untagged)
- ✅ Verified: Subnet router has internet access, can reach LAN gateway

### 1.5. Firewall Configuration (Committed, NOT Tested)
**Added to `/bootstrap/configs/opnsense/config.xml`:**

**NAT Port Forwards:**
- ✅ WAN:8082/TCP → 10.10.20.10:8082 (Headscale control server)
- ✅ WAN:41641/UDP → 10.10.10.10:41641 (Subnet router WireGuard)

**WAN Firewall Rules:**
- ✅ Allow inbound TCP on 8082 (Headscale control from internet)
- ✅ Allow inbound UDP on 41641 (WireGuard tunnels from internet)

**Purpose**: Enable VPN clients from internet to access Trusted LAN via direct WireGuard tunnels (Option B - full performance)

### 2. Headscale Subnet Router Automation (Committed, NOT Tested)

**Four playbooks** for complete automation:

1. **Headscale Deploy** (modified)
   - Generates 30-minute pre-auth key
   - Creates Semaphore environment `HeadscalePreauthKey`
   - Stores key as secret variable `HEADSCALE_PREAUTH_KEY`

2. **Subnet Router Deploy** (modified)
   - Installs Tailscale + iptables via SSH
   - Enables IP forwarding (`/etc/sysctl.d/ip_forward.conf`)
   - Enables Tailscale service (`rc-update add tailscale default`)
   - Creates SSH key and Semaphore inventory

3. **Subnet Router Configure** (new)
   - Runs on `subnet-router` inventory
   - Uses `HeadscalePreauthKey` environment
   - Connects: `tailscale up --login-server=http://10.10.20.10:8082 --authkey=$KEY --port=41641`
   - Advertises routes: `10.10.10.0/24`
   - Fixed port: 41641/UDP (for OPNsense NAT forwarding)

4. **Subnet Router Approve** (new)
   - Runs on `container-host`
   - Approves route in Headscale
   - Deletes `HeadscalePreauthKey` environment (cleanup)

**Template Names** (for orchestration):
- Subnet Router 1: Create Alpine VM
- Subnet Router 2: Configure VPN Connection
- Subnet Router 3: Approve Routes

---

## What Needs Testing

### Test 1: Fresh Bootstrap
**Objective**: Verify all 4 playbooks execute during orchestration

**Steps**:
1. Delete all VMs: `qm stop 100 101 9000 && qm destroy 100 101 9000`
2. Run quickstart: `ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"`
3. Wait ~7 minutes for completion
4. Check orchestration ran all templates

**Expected Results**:
- ✅ Bootstrap completes successfully
- ✅ All services deployed (Portainer, Semaphore, AdGuard, Headscale, Homer)
- ✅ Subnet Router VM (101) created
- ✅ Headscale deployed (container running)

**Check Commands**:
```bash
# From workstation
ssh root@192.168.1.10 "qm list | grep -E '100|101|9000'"

# Check orchestration tasks (via Proxmox)
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/tasks | jq '.[] | {template_id, status}'"
```

**Success Criteria**:
- VM 100 (OPNsense): running
- VM 101 (Subnet Router): running
- VM 9000 (Management): running
- All templates show `"status": "success"`

---

### Test 2: HeadscalePreauthKey Environment
**Objective**: Verify pre-auth key stored in Semaphore

**Steps**:
```bash
# Login to Semaphore (from Proxmox)
ssh root@192.168.1.10 'curl -sS --cookie-jar /tmp/sem.cookies -X POST -H "Content-Type: application/json" -d "{\"auth\":\"admin\",\"password\":\"<SERVICES_PASSWORD>\"}" http://10.10.20.10:3000/api/auth/login'

# List environments
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/environment | jq '.[] | {id, name}'"
```

**Expected Results**:
- ✅ Environment `HeadscalePreauthKey` exists
- ✅ Contains secret variable `HEADSCALE_PREAUTH_KEY`

**NOTE**: After "Subnet Router 3" runs, this environment should be DELETED (cleanup step).

---

### Test 3: Tailscale Installation
**Objective**: Verify Tailscale installed on subnet router

**Steps**:
```bash
# SSH to subnet router (from Proxmox)
ssh root@192.168.1.10 "sshpass -p alpine ssh -o StrictHostKeyChecking=no alpine@10.10.20.11 'which tailscale && tailscale --version'"
```

**Expected Results**:
- ✅ Tailscale binary exists: `/usr/bin/tailscale`
- ✅ Version shown (e.g., `1.x.x`)

**Check IP Forwarding**:
```bash
ssh root@192.168.1.10 "sshpass -p alpine ssh -o StrictHostKeyChecking=no alpine@10.10.20.11 'cat /proc/sys/net/ipv4/ip_forward'"
```
**Expected**: `1` (enabled)

**Check Service**:
```bash
ssh root@192.168.1.10 "sshpass -p alpine ssh -o StrictHostKeyChecking=no alpine@10.10.20.11 'rc-status | grep tailscale'"
```
**Expected**: `tailscale | default` (enabled at boot)

---

### Test 4: Headscale Connection
**Objective**: Verify subnet router connected to Headscale

**Steps**:
```bash
# List nodes in Headscale (from Proxmox)
ssh root@192.168.1.10 "ssh -o StrictHostKeyChecking=no debian@10.10.20.10 'sudo podman exec headscale headscale nodes list'"
```

**Expected Results**:
- ✅ One node listed
- ✅ Hostname contains "subnet-router" or "privatebox-subnet-router"
- ✅ IP address in range: `100.64.x.x` (Headscale CGNAT range)
- ✅ Status: Connected

**Sample Output**:
```
ID | Hostname                     | Name | User  | IP addresses | Connected
1  | privatebox-subnet-router     | ...  | admin | 100.64.0.1   | online
```

---

### Test 5: Route Advertisement
**Objective**: Verify route advertised and approved

**Steps**:
```bash
# List routes (from Proxmox)
ssh root@192.168.1.10 "ssh -o StrictHostKeyChecking=no debian@10.10.20.10 'sudo podman exec headscale headscale routes list'"
```

**Expected Results**:
- ✅ Route `10.10.10.0/24` listed
- ✅ Node: subnet-router
- ✅ Enabled: `true`

**Sample Output**:
```
Route        | Node          | Enabled
10.10.10.0/24| subnet-router | true
```

---

### Test 5.5: Firewall Configuration Verification
**Objective**: Verify NAT and firewall rules are active in OPNsense

**Steps**:
```bash
# From workstation (via Proxmox to OPNsense)
# Check NAT rules
ssh root@192.168.1.10 "ssh root@10.10.20.1 'cat /conf/config.xml | grep -A10 \"<nat>\"'"

# Verify port forwards exist
ssh root@192.168.1.10 "ssh root@10.10.20.1 'cat /conf/config.xml | grep -E \"8082|41641\"'"
```

**Expected Results**:
- ✅ NAT rule for 8082/TCP → 10.10.20.10
- ✅ NAT rule for 41641/UDP → 10.10.10.10
- ✅ WAN firewall rule allowing 8082/TCP
- ✅ WAN firewall rule allowing 41641/UDP

**Check OPNsense GUI** (optional):
1. Login to https://10.10.20.1
2. Navigate to Firewall → NAT → Port Forward
3. Verify two rules: Headscale (8082) and Subnet Router (41641)
4. Navigate to Firewall → Rules → WAN
5. Verify allow rules for both ports

---

### Test 6: VPN Client Connection (Local Network First)
**Objective**: Verify VPN client can connect and access LAN

**Prerequisites**:
- Test device (laptop/phone) with Tailscale installed
- Generate new pre-auth key for client

**Steps**:

1. **Generate client pre-auth key** (from Proxmox):
```bash
ssh root@192.168.1.10 "ssh -o StrictHostKeyChecking=no debian@10.10.20.10 'sudo podman exec headscale headscale preauthkeys create --user 1 --expiration 1h' | tail -1"
```

2. **Connect client**:
```bash
# On test device
tailscale up --login-server=http://10.10.20.10:8082 --authkey=<KEY>
```

3. **Verify connection**:
```bash
# On test device
tailscale status
```
**Expected**: Shows connected to Headscale, lists subnet-router peer

4. **Test LAN access**:
```bash
# From VPN client
ping 10.10.10.1           # OPNsense LAN gateway
ping 10.10.10.10          # Subnet router LAN IP
ping 10.10.20.10          # Management VM
curl http://10.10.20.10:8080  # AdGuard web UI
```

**Expected Results**:
- ✅ All pings succeed
- ✅ Can access AdGuard web UI
- ✅ VPN client IP: `100.64.x.x`
- ✅ Traffic routes through subnet router (not direct)

---

### Test 7: VPN Client Connection (From Internet)
**Objective**: Verify VPN works from external network (the real test!)

**Prerequisites**:
- Test device with Tailscale installed
- Device on **different network** (mobile data, coffee shop WiFi, etc.)
- Your public IP address known

**Steps**:

1. **Get your public IP** (from Proxmox):
```bash
ssh root@192.168.1.10 "curl -s https://ifconfig.me"
```

2. **Generate client pre-auth key** (from Proxmox):
```bash
ssh root@192.168.1.10 "ssh -o StrictHostKeyChecking=no debian@10.10.20.10 'sudo podman exec headscale headscale preauthkeys create --user 1 --expiration 1h' | tail -1"
```

3. **Connect client using public IP**:
```bash
# On external device
tailscale up --login-server=http://<YOUR_PUBLIC_IP>:8082 --authkey=<KEY>
```

4. **Verify connection**:
```bash
# On external device
tailscale status
# Should show: Connected to Headscale, subnet-router peer listed
```

5. **Test WireGuard tunnel** (check if direct connection established):
```bash
# On external device
tailscale netcheck
# Look for: "DERP latency" vs "Direct connection"
# Direct connection = firewall working! ✅
```

6. **Test LAN access** (from external device):
```bash
ping 10.10.10.10          # Subnet router LAN IP
ping 10.10.20.10          # Management VM
curl http://10.10.20.10:8080  # AdGuard web UI
```

**Expected Results**:
- ✅ Client connects via public IP:8082
- ✅ WireGuard establishes **direct tunnel** (not DERP relay) on port 41641
- ✅ All pings succeed
- ✅ Can access AdGuard web UI from internet
- ✅ Low latency (<50ms typically, vs 100-200ms on DERP)

**Troubleshooting**:
- If client connects but uses DERP: Firewall port 41641/UDP not open correctly
- If client can't connect at all: Port 8082/TCP not forwarded
- If connection works but no LAN access: Route not approved in Headscale

---

### Test 8: Environment Cleanup
**Objective**: Verify HeadscalePreauthKey deleted after approval

**Steps**:
```bash
# After "Subnet Router 3" completes, list environments
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/environment | jq '.[] | {name}'"
```

**Expected Results**:
- ✅ `HeadscalePreauthKey` NOT in list (deleted)
- ✅ Other environments remain: `SemaphoreAPI`, `ServicePasswords`, `HeadscaleAPI`, `OPNsenseAPI`

---

## Known Issues / Edge Cases

### Issue 1: Pre-Auth Key Expiration
**Symptom**: "Subnet Router 2" fails with authentication error

**Cause**: Pre-auth key expired (30-minute window)

**Solution**:
- Run "Headscale 1" again to regenerate key
- Then immediately run "Subnet Router 2"
- Or increase expiration to 1 day if orchestration takes longer

### Issue 2: Node Already Registered
**Symptom**: "Subnet Router 2" fails, node already exists

**Cause**: Re-running configure on already-connected node

**Solution**:
- Playbook should handle this (checks `tailscale status`)
- If not, manually delete node:
```bash
ssh root@192.168.1.10 "ssh debian@10.10.20.10 'sudo podman exec headscale headscale nodes delete <NODE_ID>'"
```

### Issue 3: Route Not Advertised
**Symptom**: "Subnet Router 3" fails, route not found

**Cause**: Tailscale didn't connect or advertise routes

**Check**:
```bash
ssh root@192.168.1.10 "sshpass -p alpine ssh alpine@10.10.20.11 'tailscale status'"
```

**Solution**: Re-run "Subnet Router 2"

### Issue 4: SSH Password Changed
**Symptom**: Cannot SSH to subnet router with "alpine" password

**Cause**: Password may have been changed or SSH config different

**Solution**: Use SSH key from Semaphore inventory instead of password

---

## Rollback Plan

If testing fails and you need to start fresh:

```bash
# 1. Delete all VMs
ssh root@192.168.1.10 "qm stop 100 101 9000 && qm destroy 100 101 9000"

# 2. Delete Semaphore environments (optional, if corrupted)
# Login to Semaphore UI: http://10.10.20.10:3000
# Delete: HeadscalePreauthKey (if exists)

# 3. Re-run quickstart
ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"
```

---

## Success Criteria

✅ **All tests pass**:
1. Fresh bootstrap completes without errors
2. HeadscalePreauthKey environment created (then deleted)
3. Tailscale installed on subnet router
4. Subnet router connected to Headscale
5. Route `10.10.10.0/24` advertised and approved
6. VPN client can connect and access Trusted LAN
7. Pre-auth key environment cleaned up

✅ **End-to-end flow works**:
- VPN client anywhere → Headscale mesh → Subnet router → Trusted LAN devices

✅ **No manual intervention needed** after quickstart

---

## Next Steps After Testing

If all tests pass:
1. Document VPN client setup for users
2. Consider adding to orchestration sequence (automatic during bootstrap)
3. Test subnet router persistence (reboot VM, verify reconnection)
4. Test multiple VPN clients simultaneously
5. Performance testing (bandwidth, latency)

If tests fail:
1. Check logs: `/tmp/privatebox-bootstrap.log` (Proxmox)
2. Check Semaphore task logs (http://10.10.20.10:3000)
3. Check Headscale logs: `podman logs headscale`
4. Report findings, fix issues, re-test

---

## Reference Commands

**Get Services Password** (from Proxmox):
```bash
ssh root@192.168.1.10 "grep SERVICES_PASSWORD /tmp/privatebox-bootstrap.log | tail -1"
```

**Access Semaphore** (from workstation via Proxmox):
```bash
ssh root@192.168.1.10 -L 3000:10.10.20.10:3000
# Then open http://localhost:3000 in browser
```

**Check Headscale Health**:
```bash
ssh root@192.168.1.10 "curl -s http://10.10.20.10:8082/health"
```
Expected: `{"status":"pass"}`

**Subnet Router Quick Check**:
```bash
ssh root@192.168.1.10 "sshpass -p alpine ssh alpine@10.10.20.11 'tailscale status && echo --- && cat /proc/sys/net/ipv4/ip_forward'"
```

---

## Questions for Testing

1. Does bootstrap complete in expected time (~7 minutes)?
2. Do all 3 subnet router playbooks execute in sequence?
3. Does pre-auth key work within 30-minute window?
4. Can VPN client access all LAN subnets (10.10.10.x)?
5. Does cleanup (environment deletion) work correctly?
6. What happens if you re-run "Subnet Router 2" on already-connected node?
7. Does subnet router survive reboot and reconnect automatically?

---

**End of Handover**
