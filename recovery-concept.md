# PrivateBox Recovery Concept

## Problem
Consumer network appliances need factory reset capability, but PrivateBox runs on generic x86 hardware without reset buttons.

## Solution Discovery
Physical console access can be detected and restricted in Linux, enabling secure recovery options.

## Core Concept
- Create files/scripts that are ONLY accessible from physical console (not SSH)
- Use TTY detection: `[ "$SSH_CONNECTION" ]` and `tty | grep "^/dev/tty[0-9]"`
- Store recovery passwords and original config in console-only directory

## Implementation Ideas
1. **Recovery user**: Immutable account that only works at physical console
2. **Console-only directory**: `/root/.console-only/` with original configs and passwords
3. **Factory reset script**: Detects physical console, offers reset/restore options
4. **Recovery partition**: Small Alpine Linux partition that survives Proxmox reinstall

## Current Status
- Fixed network isolation issue (vmbr1 was bridged to physical interface)
- OPNsense was leaking DHCP to main network - now properly isolated
- Need to verify isolation is complete

## Next Steps
- Prototype console-only access restrictions
- Design recovery menu system
- Test recovery partition approach