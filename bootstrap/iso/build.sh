#!/bin/sh
# Runs inside the mfsBSD builder VM to patch the ramdisk
set -eu
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/rescue:$PATH"
log(){ echo "[PBX] $*"; }

# 1) Mount cfg ISO (contains rc.local + markers written by host)
mkdir -p /cfg
for d in /dev/cd*; do
  mount_cd9660 "$d" /cfg 2>/dev/null || continue
  [ -f /cfg/rc.local ] && break
  umount /cfg 2>/dev/null || true
done

# 2) Wait for work disk (virtio0 holds uncompressed mfsroot UFS)
i=0; while :; do
  [ -e /dev/vtbd0 ] && break
  i=$((i+1)); [ $i -ge 180 ] && { echo "vtbd0 missing"; exit 1; }
  sleep 1
done

# 3) Mount UFS and install shim + markers
fsck_ufs -y /dev/vtbd0 || true
mkdir -p /mnt/mfs/etc
mount -t ufs -o rw /dev/vtbd0 /mnt/mfs

install -m 0755 /cfg/rc.local /mnt/mfs/etc/rc.local
[ -f /cfg/pbx_url ]      && install -m 0644 /cfg/pbx_url /mnt/mfs/etc/pbx_url || true
[ -f /cfg/pbx_insecure ] && install -m 0644 /cfg/pbx_insecure /mnt/mfs/etc/pbx_insecure || true

ls -l /mnt/mfs/etc/rc.local
[ -r /mnt/mfs/etc/pbx_url ] && echo "[PBX] baked URL: $(cat /mnt/mfs/etc/pbx_url)" || echo "[PBX] no pbx_url marker"

umount /mnt/mfs || true
sync
shutdown -p now