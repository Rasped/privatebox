#!/bin/sh
# Debug version - Runs inside the mfsBSD builder VM to patch the ramdisk
set -eu
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/rescue:$PATH"
log(){ echo "[PBX] $*"; }

log "Starting build-debug.sh"

# 1) Mount cfg ISO (contains rc.local + markers written by host)
log "Looking for cfg ISO..."
mkdir -p /cfg
for d in /dev/cd*; do
  log "Trying $d"
  mount_cd9660 "$d" /cfg 2>/dev/null || continue
  [ -f /cfg/rc.local ] && { log "Found rc.local on $d"; break; }
  umount /cfg 2>/dev/null || true
done

log "Contents of /cfg:"
ls -la /cfg

# 2) Wait for work disk (virtio0 holds uncompressed mfsroot UFS)
log "Waiting for vtbd0..."
i=0; while :; do
  [ -e /dev/vtbd0 ] && { log "Found vtbd0"; break; }
  i=$((i+1)); [ $i -ge 180 ] && { log "ERROR: vtbd0 missing"; exit 1; }
  sleep 1
done

# 3) Mount UFS and check what's there
log "Running fsck on vtbd0..."
fsck_ufs -y /dev/vtbd0 || true

log "Mounting vtbd0 to /mnt/mfs..."
mkdir -p /mnt/mfs
mount -t ufs -o rw /dev/vtbd0 /mnt/mfs

log "Contents of /mnt/mfs after mount:"
ls -la /mnt/mfs/

log "Checking if /mnt/mfs/etc exists:"
if [ -d /mnt/mfs/etc ]; then
  log "/mnt/mfs/etc exists"
  ls -la /mnt/mfs/etc/
else
  log "/mnt/mfs/etc does NOT exist, creating it"
  mkdir -p /mnt/mfs/etc
fi

# Try copying files instead of install
log "Copying rc.local..."
cp /cfg/rc.local /mnt/mfs/etc/rc.local
chmod 755 /mnt/mfs/etc/rc.local

if [ -f /cfg/pbx_url ]; then
  log "Copying pbx_url..."
  cp /cfg/pbx_url /mnt/mfs/etc/pbx_url
  chmod 644 /mnt/mfs/etc/pbx_url
fi

if [ -f /cfg/pbx_insecure ]; then
  log "Copying pbx_insecure..."
  cp /cfg/pbx_insecure /mnt/mfs/etc/pbx_insecure
  chmod 644 /mnt/mfs/etc/pbx_insecure
fi

log "Final contents of /mnt/mfs/etc:"
ls -la /mnt/mfs/etc/

[ -r /mnt/mfs/etc/pbx_url ] && log "baked URL: $(cat /mnt/mfs/etc/pbx_url)" || log "no pbx_url marker"

log "Unmounting..."
umount /mnt/mfs || true
sync

log "Done - shutting down"
shutdown -p now