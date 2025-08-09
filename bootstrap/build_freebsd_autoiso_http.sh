#!/usr/bin/env bash
set -euo pipefail

# ===== Vars =====
FBSD_VER="${FBSD_VER:-14.3}"                       # Target FreeBSD version (for your info)
MFSBSD_VER="${MFSBSD_VER:-$FBSD_VER}"              # mfsBSD version to base on (falls back to 14.2)
BID="${BID:-9970}"                                 # Ephemeral builder VMID
STORAGE="${STORAGE:-local-lvm}"                    # Storage for temp disk (e.g., local-lvm or local)
ISO_STORAGE="${ISO_STORAGE:-local}"                # Storage that serves ISO_DIR
ISO_DIR="${ISO_DIR:-/var/lib/vz/template/iso}"     # Directory for ISO_STORAGE (e.g., /var/lib/vz/template/iso)
PBX_URL="${PBX_URL:-https://raw.githubusercontent.com/Rasped/privatebox/main/bootstrap/config/installerconfig}"  # GitHub installerconfig URL
PBX_INSECURE="${PBX_INSECURE:-0}"                  # 1 = skip TLS verify for PBX_URL
# =================

WORK="/var/lib/vz/tmp-autoiso-$BID"
AUTO_ISO="$ISO_DIR/mfsbsd-freebsd-autoinstaller.iso"

RC_LOCAL_SHIM='#!/bin/sh
# /etc/rc.local inside the installer mfsroot
set -u
umask 022
LOG=/var/log/pbx-rc.log
exec >>"$LOG" 2>&1
echo "[PBX] rc.local start $(date -u +%FT%TZ)"

run_install() {
  echo "[PBX] running installer from: $1"
  bsdinstall script "$1"
  rc=$?
  echo "[PBX] bsdinstall rc=$rc"
  sync; sleep 2
  shutdown -p now
  exit 0
}

# 1) HTTP first (PBX_URL marker)
url=""
[ -r /etc/pbx_url ] && url="$(head -n1 /etc/pbx_url || true)"
if [ -n "$url" ]; then
  echo "[PBX] fetching installerconfig from $url"
  if [ -f /etc/pbx_insecure ]; then
    fetch --no-verify-peer -o /tmp/installerconfig "$url" && run_install /tmp/installerconfig || echo "[PBX] fetch failed"
  else
    fetch -o /tmp/installerconfig "$url" && run_install /tmp/installerconfig || echo "[PBX] fetch failed"
  fi
fi

# 2) Fallback: scan secondary media for /etc/installerconfig
echo "[PBX] probing removable media for installerconfig"
mkdir -p /mnt/cfg
for d in /dev/cd1 /dev/cd0 /dev/da1 /dev/vtbd1; do
  mount_cd9660 "$d" /mnt/cfg 2>/dev/null && break
done
[ -f /mnt/cfg/etc/installerconfig ] && run_install /mnt/cfg/etc/installerconfig

echo "[PBX] no installerconfig found; continuing normal boot"
exit 0
'

BUILD_SH='#!/bin/sh
set -eu

log() { echo "[PBX] $*"; }

# 1) Mount cfg ISO (if present)
log "Mounting cfg ISO…"
mkdir -p /cfg
mount_cd9660 /dev/cd1 /cfg 2>/dev/null || mount_cd9660 /dev/cd0 /cfg 2>/dev/null || true

# 2) Prepare rc.local source: use /cfg/rc.local if available; else write shim
RC_SRC="/tmp/rc.local"
if [ -f /cfg/rc.local ]; then
  log "Using rc.local from cfg ISO"
  cp -f /cfg/rc.local "$RC_SRC"
else
  log "cfg ISO missing rc.local — writing inline shim"
  cat > "$RC_SRC" <<'\''EOF'\''
#!/bin/sh
# /etc/rc.local inside the installer mfsroot
set -u
umask 022
LOG=/var/log/pbx-rc.log
exec >>"$LOG" 2>&1
echo "[PBX] rc.local start $(date -u +%FT%TZ)"

run_install() {
  echo "[PBX] running installer from: $1"
  bsdinstall script "$1"
  rc=$?
  echo "[PBX] bsdinstall rc=$rc"
  sync; sleep 2
  shutdown -p now
  exit 0
}

# 1) HTTP first (PBX_URL marker)
url=""
[ -r /etc/pbx_url ] && url="$(head -n1 /etc/pbx_url || true)"
if [ -n "$url" ]; then
  echo "[PBX] fetching installerconfig from $url"
  if [ -f /etc/pbx_insecure ]; then
    fetch --no-verify-peer -o /tmp/installerconfig "$url" && run_install /tmp/installerconfig || echo "[PBX] fetch failed"
  else
    fetch -o /tmp/installerconfig "$url" && run_install /tmp/installerconfig || echo "[PBX] fetch failed"
  fi
fi

# 2) Fallback: scan secondary media for /etc/installerconfig
echo "[PBX] probing removable media for installerconfig"
mkdir -p /mnt/cfg
for d in /dev/cd1 /dev/cd0 /dev/da1 /dev/vtbd1; do
  mount_cd9660 "$d" /mnt/cfg 2>/dev/null && break
done
[ -f /mnt/cfg/etc/installerconfig ] && run_install /mnt/cfg/etc/installerconfig

echo "[PBX] no installerconfig found; continuing normal boot"
exit 0
EOF
fi
chmod 0755 "$RC_SRC"

# 3) Wait for work disk and mount it
log "Waiting for /dev/vtbd0…"
i=0
while :; do
  [ -e /dev/vtbd0 ] && break
  i=$((i+1)); [ $i -ge 120 ] && break
  sleep 1
done

log "Mounting mfsroot UFS…"
fsck_ufs -y /dev/vtbd0 || true
mkdir -p /mnt/mfs/etc
mount -t ufs -o rw /dev/vtbd0 /mnt/mfs

# 4) Install shim + markers
log "Installing rc.local shim…"
cp -f "$RC_SRC" /mnt/mfs/etc/rc.local && chmod 0755 /mnt/mfs/etc/rc.local
[ -f /cfg/pbx_url ] && cp -f /cfg/pbx_url /mnt/mfs/etc/pbx_url && chmod 0644 /mnt/mfs/etc/pbx_url || true
[ -f /cfg/pbx_insecure ] && cp -f /cfg/pbx_insecure /mnt/mfs/etc/pbx_insecure && chmod 0644 /mnt/mfs/etc/pbx_insecure || true
ls -l /mnt/mfs/etc/rc.local || true

# 5) Cleanly unmount and power off (host continues)
umount /mnt/mfs || true
sync
log "Powering off…"
shutdown -p now
'

KEEP_BUILDER="${KEEP_BUILDER:-0}"
cleanup() {
  set +e
  [ "$KEEP_BUILDER" = "1" ] && { echo "Keeping builder VM $BID for debugging"; return; }
  qm stop "$BID" >/dev/null 2>&1 || true
  qm destroy "$BID" --purge >/dev/null 2>&1 || true
  rm -rf "$WORK"
  rm -f "$ISO_DIR/freebsd-installer-config.iso"
  rm -f "$ISO_DIR/mfsbsd-*-serial-$BID.iso"
}
trap cleanup EXIT

apt-get update -qq
apt-get install -y -qq xorriso expect socat curl >/dev/null

mkdir -p "$ISO_DIR" "$WORK"

# --- Download mfsBSD (prefer MINI, fallback SE; then fallback to 14.2) ---
download_mfsbsd() {
  local ver="$1"
  local mjr="${ver%%.*}"
  local mini="$ISO_DIR/mfsbsd-mini-$ver-RELEASE-amd64.iso"
  local mini_url="https://mfsbsd.vx.sk/files/iso/$mjr/amd64/mfsbsd-mini-$ver-RELEASE-amd64.iso"
  local se="$ISO_DIR/mfsbsd-se-$ver-RELEASE-amd64.iso"
  local se_url="https://mfsbsd.vx.sk/files/iso/$mjr/amd64/mfsbsd-se-$ver-RELEASE-amd64.iso"
  if [ ! -f "$mini" ]; then curl -fL "$mini_url" -o "$mini" || true; fi
  if [ -f "$mini" ]; then echo "$mini"; return 0; fi
  if [ ! -f "$se" ];   then curl -fL "$se_url"   -o "$se"   || true; fi
  if [ -f "$se" ];   then echo "$se";   return 0; fi
  return 1
}

MFSBSD_ISO="$(download_mfsbsd "$MFSBSD_VER" || true)"
if [ -z "${MFSBSD_ISO:-}" ]; then
  echo "mfsBSD $MFSBSD_VER not found online; trying 14.2…" >&2
  MFSBSD_VER="14.2"
  MFSBSD_ISO="$(download_mfsbsd "$MFSBSD_VER")"
fi

# --- Force serial console on the builder ISO (so Expect can log in) ---
SERIAL_LOADER="$WORK/loader.conf.serial"
xorriso -indev "$MFSBSD_ISO" -osirrox on -extract /boot/loader.conf "$SERIAL_LOADER" >/dev/null

# append serial settings if missing
grep -q 'boot_multicons' "$SERIAL_LOADER" || cat >>"$SERIAL_LOADER" <<'EOF'
boot_multicons="YES"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole,vidconsole"
EOF

# remaster a serial-enabled copy and use that for the builder VM
SERIAL_ISO="$ISO_DIR/mfsbsd-${MFSBSD_VER}-serial-$BID.iso"
xorriso -indev "$MFSBSD_ISO" -outdev "$SERIAL_ISO" \
  -map "$SERIAL_LOADER" /boot/loader.conf \
  -boot_image any keep >/dev/null
MFSBSD_ISO="$SERIAL_ISO"

# --- Detect ramdisk path from loader.conf and extract that exact file ---
LOADER="$WORK/loader.conf"
xorriso -indev "$MFSBSD_ISO" -osirrox on -extract /boot/loader.conf "$LOADER" >/dev/null

RAMDISK_PATH=$(
  awk -F\" '/rootfs_image_name|mfsroot_name|mfs_name|mdroot/ {print $2; exit}' "$LOADER"
)
[ -n "$RAMDISK_PATH" ] || { echo "ERROR: No ramdisk path found in loader.conf"; exit 1; }

# Resolve concrete path (with ext if any)
FOUND=""
for ext in "" ".gz" ".uzip"; do
  if xorriso -indev "$MFSBSD_ISO" -osirrox on -find "${RAMDISK_PATH}${ext}" 2>/dev/null | grep -q .; then
    FOUND="${RAMDISK_PATH}${ext}"; break
  fi
done
[ -n "$FOUND" ] || { echo "ERROR: Ramdisk payload not found on ISO"; exit 1; }
RAMDISK_PATH="$FOUND"
echo "Detected ramdisk payload: $RAMDISK_PATH"

# Extract payload and produce uncompressed UFS work image
xorriso -indev "$MFSBSD_ISO" -osirrox on -extract "$RAMDISK_PATH" "$WORK/mfsroot.payload" >/dev/null
case "$RAMDISK_PATH" in
  *.gz)   gunzip -c "$WORK/mfsroot.payload" > "$WORK/mfsroot" ;;
  *.uzip) echo "This ISO uses .uzip; set MFSBSD_VER=14.2 (gz) or add mkuzip support." >&2; exit 1 ;;
  *)      cp "$WORK/mfsroot.payload" "$WORK/mfsroot" ;;
esac
cp "$WORK/mfsroot" "$WORK/mfsroot.img"

# --- Build cfg ISO in the ISO storage path ---
mkdir -p "$WORK/cfg"
printf "%s" "$RC_LOCAL_SHIM" > "$WORK/cfg/rc.local"
printf "%s" "$BUILD_SH"     > "$WORK/cfg/build.sh"
chmod 0755 "$WORK/cfg/rc.local" "$WORK/cfg/build.sh"
[ -n "$PBX_URL" ]      && printf "%s\n" "$PBX_URL" > "$WORK/cfg/pbx_url"
[ "$PBX_INSECURE" = "1" ] && touch "$WORK/cfg/pbx_insecure"
CFG_NAME="freebsd-installer-config.iso"
xorriso -as mkisofs -o "$ISO_DIR/$CFG_NAME" -V BUILDERCFG -J -R "$WORK/cfg" >/dev/null

# --- Create builder VM (no hotplug; boot from SATA CD) ---
MFSBSD_NAME="$(basename "$MFSBSD_ISO")"
qm destroy "$BID" --purge >/dev/null 2>&1 || true
qm create "$BID" --name autoiso-builder --memory 2048 --balloon 0 \
  --cores 1 --serial0 socket --vga serial0 --boot order=sata0 >/dev/null
qm set "$BID" --sata0 "${ISO_STORAGE}:iso/$MFSBSD_NAME",media=cdrom >/dev/null
qm set "$BID" --sata1 "${ISO_STORAGE}:iso/$CFG_NAME",media=cdrom   >/dev/null
qm importdisk "$BID" "$WORK/mfsroot.img" "$STORAGE" --format raw >/dev/null
qm set "$BID" --virtio0 "${STORAGE}:vm-${BID}-disk-0" >/dev/null

# Sanity print
qm config "$BID" | grep -E 'boot|sata|virtio0' || true

qm start "$BID" >/dev/null
sleep 6

# --- Drive build via serial console (mfsBSD root pw: mfsroot) ---
cat > "$WORK/drive.expect" <<'EOT'
#!/usr/bin/expect -f
set vmid [lindex $argv 0]
set timeout 90
spawn socat -,raw,echo=0 UNIX-CONNECT:/var/run/qemu-server/$vmid.serial0

expect -re "(login:|#)"
send -- "root\r"
expect -re "Password:"
send -- "mfsroot\r"
expect -re "#"

# Single compound command: wait for disk, mount cfg, run build
set timeout 120
send -- "i=0; while :; do test -e /dev/vtbd0 && break; i=\$((i+1)); test \$i -ge 120 && break; sleep 1; done; mkdir -p /cfg; mount_cd9660 /dev/cd1 /cfg 2>/dev/null || mount_cd9660 /dev/cd0 /cfg; sh /cfg/build.sh\r"

# Wait for shutdown
set timeout 900
expect eof
EOT
chmod +x "$WORK/drive.expect"
"$WORK/drive.expect" "$BID" || true

# Wait until VM halts itself
for _ in $(seq 1 120); do
  state="$(qm status "$BID" | awk '{print $2}')"
  [ "$state" = "stopped" ] && break
  sleep 2
done

# --- Read back modified mfsroot, re-pack in original format, remaster ISO ---
VOLID="${STORAGE}:vm-${BID}-disk-0"
VOLPATH="$(pvesm path "$VOLID")"
dd if="$VOLPATH" of="$WORK/mfsroot.patched" bs=1M status=none

case "$RAMDISK_PATH" in
  *.gz)   gzip -c "$WORK/mfsroot.patched" > "$WORK/mfsroot.new" ;;
  *.uzip) echo "This ISO uses .uzip; set MFSBSD_VER=14.2 (gz) or add mkuzip support." >&2; exit 1 ;;
  *)      cp "$WORK/mfsroot.patched" "$WORK/mfsroot.new" ;;
esac

xorriso -indev "$MFSBSD_ISO" -outdev "$AUTO_ISO" \
  -map "$WORK/mfsroot.new" "$RAMDISK_PATH" \
  -boot_image any keep >/dev/null

echo "OK -> $AUTO_ISO"
