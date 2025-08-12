#!/usr/bin/env bash
set -euo pipefail

# ---- defaults (hands-off) ----
FBSD_VER="${FBSD_VER:-14.3}"
MFSBSD_VER="${MFSBSD_VER:-14.2}"
BID="${BID:-9970}"
STORAGE="${STORAGE:-local-lvm}"
ISO_STORAGE="${ISO_STORAGE:-local}"
ISO_DIR="${ISO_DIR:-/var/lib/vz/template/iso}"
PBX_URL="${PBX_URL:-https://raw.githubusercontent.com/Rasped/privatebox/main/bootstrap/config/installerconfig}"
PBX_INSECURE="${PBX_INSECURE:-0}"
KEEP_BUILDER="${KEEP_BUILDER:-0}"

# ---- optional config files (override defaults) ----
for cfg in /etc/privatebox/autoiso.conf "$(dirname "$0")/autoiso.conf"; do
  [ -r "$cfg" ] && . "$cfg"
done

# ---- optional CLI flags (override everything) ----
while [ $# -gt 0 ]; do
  case "$1" in
    --fbsd-ver=*)        FBSD_VER="${1#*=}";;
    --mfsbsd-ver=*)      MFSBSD_VER="${1#*=}";;
    --bid=*)             BID="${1#*=}";;
    --storage=*)         STORAGE="${1#*=}";;
    --iso-storage=*)     ISO_STORAGE="${1#*=}";;
    --iso-dir=*)         ISO_DIR="${1#*=}";;
    --pbx-url=*)         PBX_URL="${1#*=}";;
    --pbx-insecure=*)    PBX_INSECURE="${1#*=}";;
    --keep-builder=1)    KEEP_BUILDER=1;;
    --config=*)          . "${1#*=}";;   # load another config file
    *) echo "Unknown flag: $1" >&2; exit 2;;
  esac
  shift
done

WORK="/var/lib/vz/tmp-autoiso-$BID"
AUTO_ISO="$ISO_DIR/mfsbsd-freebsd-autoinstaller.iso"

say(){ echo "[$(date +%H:%M:%S)] $*"; }

cleanup(){
  set +e
  [ "$KEEP_BUILDER" = "1" ] && { say "Keeping builder $BID"; return; }
  qm stop "$BID" >/dev/null 2>&1 || true
  qm destroy "$BID" --purge >/dev/null 2>&1 || true
  rm -rf "$WORK"
  rm -f "$ISO_DIR/mfsbsd-"*"-serial-$BID.iso" "$ISO_DIR/auto-cfg-$BID.iso"
}
trap cleanup EXIT

apt-get update -qq
apt-get install -y -qq xorriso expect socat curl >/dev/null
mkdir -p "$ISO_DIR" "$WORK"

# 0) sanity: PBX_URL reachable?
say "Probing PBX_URL…"
if ! curl -fsL --head "$PBX_URL" >/dev/null; then
  say "WARN: PBX_URL not reachable now; will still bake the value"
fi

# 1) download mfsBSD SE (fall back to mini)
download_mfsbsd(){
  local ver="$1" mjr="${1%%.*}"
  local se="$ISO_DIR/mfsbsd-se-$ver-RELEASE-amd64.iso"
  local mini="$ISO_DIR/mfsbsd-mini-$ver-RELEASE-amd64.iso"
  [ -f "$se" ]   || curl -fL "https://mfsbsd.vx.sk/files/iso/$mjr/amd64/$(basename "$se")"   -o "$se"   || true
  [ -f "$se" ]   && { echo "$se"; return; }
  [ -f "$mini" ] || curl -fL "https://mfsbsd.vx.sk/files/iso/$mjr/amd64/$(basename "$mini")" -o "$mini" || true
  [ -f "$mini" ] && { echo "$mini"; return; }
  return 1
}
MFSBSD_ISO="$(download_mfsbsd "$MFSBSD_VER" || true)"
if [ -z "${MFSBSD_ISO:-}" ]; then
  say "mfsBSD $MFSBSD_VER not found; trying 14.2"
  MFSBSD_VER="14.2"
  MFSBSD_ISO="$(download_mfsbsd "$MFSBSD_VER")"
fi
say "Using mfsBSD ISO: $(basename "$MFSBSD_ISO")"

# 2) make a serial-enabled builder ISO
SERIAL_LOADER="$WORK/loader.serial.conf"
xorriso -indev "$MFSBSD_ISO" -osirrox on -extract /boot/loader.conf "$SERIAL_LOADER" >/dev/null
grep -q 'boot_multicons' "$SERIAL_LOADER" || cat >>"$SERIAL_LOADER" <<'EOF'
boot_multicons="YES"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole,vidconsole"
EOF
SERIAL_ISO="$ISO_DIR/mfsbsd-${MFSBSD_VER}-serial-$BID.iso"
xorriso -indev "$MFSBSD_ISO" -outdev "$SERIAL_ISO" \
  -map "$SERIAL_LOADER" /boot/loader.conf \
  -boot_image any keep >/dev/null
MFSBSD_ISO="$SERIAL_ISO"

# 3) detect ramdisk payload path
LOADER="$WORK/loader.conf"
xorriso -indev "$MFSBSD_ISO" -osirrox on -extract /boot/loader.conf "$LOADER" >/dev/null
RAMDISK_PATH=$(
  awk -F\" '/rootfs_image_name|mfsroot_name|mfs_name|mdroot/ {print $2; exit}' "$LOADER"
)
[ -n "$RAMDISK_PATH" ] || { echo "ERROR: no ramdisk key in loader.conf"; exit 1; }

FOUND=""
for ext in "" ".gz" ".uzip"; do
  if xorriso -indev "$MFSBSD_ISO" -osirrox on -find "${RAMDISK_PATH}${ext}" 2>/dev/null | grep -q .; then
    FOUND="${RAMDISK_PATH}${ext}"; break
  fi
done
[ -n "$FOUND" ] || { echo "ERROR: ramdisk payload not found"; exit 1; }
RAMDISK_PATH="$FOUND"
say "Ramdisk: $RAMDISK_PATH"

# 4) extract payload, normalize uncompressed UFS image for patching
xorriso -indev "$MFSBSD_ISO" -osirrox on -extract "$RAMDISK_PATH" "$WORK/mfsroot.payload" >/dev/null
case "$RAMDISK_PATH" in
  *.gz)  gunzip -c "$WORK/mfsroot.payload" > "$WORK/mfsroot" ;;
  *.uzip) echo "ERROR: .uzip not supported; use MFSBSD_VER=14.2"; exit 1 ;;
  *)     cp "$WORK/mfsroot.payload" "$WORK/mfsroot" ;;
esac
cp "$WORK/mfsroot" "$WORK/mfsroot.img"

# 5) build tiny cfg ISO with files we'll bake into the ramdisk
mkdir -p "$WORK/cfg"
install -m 0755 "bootstrap/iso/rc.local" "$WORK/cfg/rc.local"
printf "%s\n" "$PBX_URL" > "$WORK/cfg/pbx_url"
[ "$PBX_INSECURE" = "1" ] && : > "$WORK/cfg/pbx_insecure" || true
install -m 0755 "bootstrap/iso/build.sh" "$WORK/cfg/build.sh"
CFG_ISO="$ISO_DIR/auto-cfg-$BID.iso"
xorriso -as mkisofs -o "$CFG_ISO" -V BUILDERCFG -J -R "$WORK/cfg" >/dev/null

# 6) create builder VM, attach: sata0=serial-iso, sata1=cfg, virtio0=mfsroot.img
qm destroy "$BID" --purge >/dev/null 2>&1 || true
qm create "$BID" --name autoiso-builder --memory 1024 --balloon 0 \
  --cores 1 --serial0 socket --vga serial0 --boot order=sata0 >/dev/null
qm set "$BID" --sata0 "${ISO_STORAGE}:iso/$(basename "$MFSBSD_ISO")",media=cdrom >/dev/null
qm set "$BID" --sata1 "${ISO_STORAGE}:iso/$(basename "$CFG_ISO")",media=cdrom   >/dev/null
qm importdisk "$BID" "$WORK/mfsroot.img" "$STORAGE" --format raw >/dev/null
qm set "$BID" --virtio0 "${STORAGE}:vm-${BID}-disk-0" >/dev/null

qm start "$BID" >/dev/null
sleep 6

# 7) log in over serial and run build.sh (expect is simple, no [ ])
cat > "$WORK/drive.expect" <<'EOT'
#!/usr/bin/expect -f
set vmid [lindex $argv 0]
set timeout 180
spawn socat -,raw,echo=0 UNIX-CONNECT:/var/run/qemu-server/$vmid.serial0
expect -re "(login:|#)"
send -- "root\r"
expect -re "Password:"
send -- "mfsroot\r"
expect -re "#"
send -- "mkdir -p /cfg; mount_cd9660 /dev/cd1 /cfg 2>/dev/null || mount_cd9660 /dev/cd0 /cfg; sh /cfg/build.sh\r"
set timeout 900
expect eof
EOT
chmod +x "$WORK/drive.expect"
"$WORK/drive.expect" "$BID" || true

# wait until the builder powers off
for _ in $(seq 1 150); do
  state="$(qm status "$BID" | awk '{print $2}')"
  [ "$state" = "stopped" ] && break
  sleep 2
done

# 8) read back modified UFS image from virtio0
VOLID="${STORAGE}:vm-${BID}-disk-0"
VOLPATH="$(pvesm path "$VOLID")"
dd if="$VOLPATH" of="$WORK/mfsroot.patched" bs=1M status=none

# 9) create both compressed and plain payloads
gzip -c "$WORK/mfsroot.patched" > "$WORK/mfsroot.patched.gz"

# 10) remaster to new auto ISO: map BOTH /mfsroot and /mfsroot.gz
xorriso -indev "$MFSBSD_ISO" -outdev "$AUTO_ISO" \
  -map "$WORK/mfsroot.patched.gz" "/mfsroot.gz" \
  -map "$WORK/mfsroot.patched"    "/mfsroot"    \
  -boot_image any keep >/dev/null

# 11) normalize loader to use .gz (safer across variants)
AUTO_LOADER="$WORK/auto.loader.conf"
xorriso -indev "$AUTO_ISO" -osirrox on -extract /boot/loader.conf "$AUTO_LOADER" >/dev/null
sed -E -i 's/^(rootfs_image_name|mfsroot_name|mfs_name|mdroot)=.*/mfs_name="\/mfsroot.gz"/' "$AUTO_LOADER"
xorriso -indev "$AUTO_ISO" -outdev "$AUTO_ISO" \
  -map "$AUTO_LOADER" /boot/loader.conf \
  -boot_image any keep >/dev/null

# 12) final sanity: ensure rc.local & pbx_url were baked (check our work image)
if ! strings "$WORK/mfsroot.patched" | grep -q "/etc/rc.local"; then
  echo "ERROR: rc.local not present in mfsroot"; exit 1
fi
if ! strings "$WORK/mfsroot.patched" | grep -q "pbx_url"; then
  echo "WARN: pbx_url marker not detected (continuing)"
fi

say "OK -> $AUTO_ISO"