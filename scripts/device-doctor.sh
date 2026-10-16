#!/usr/bin/env bash
# Non-destructive device preflight, run inside WSL. See docs/DEVICE_SETUP.md.
#
# Checks (each printed as OK / MISSING / INFO / WARN with a fix hint):
#   usbmuxd binary + daemon, libimobiledevice tools, USB/IP kernel support, xtool CLI + version,
#   xtool auth state (never prints the account or any token), Darwin SDK, Apple USB device visible in WSL,
#   paired devices (idevice_id -l), Developer Mode (if readable).
# Never installs, starts, pairs or changes anything. Always exits 0 (even with no device); read the output.
#
# Usage: bash scripts/device-doctor.sh
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/toolchain.sh
. "$REPO_ROOT/scripts/lib/toolchain.sh"
tabula_load_toolchain

MISSING_COUNT=0
ok()      { printf 'OK       %s\n' "$1"; }
info()    { printf 'INFO     %s\n' "$1"; }
warn()    { printf 'WARN     %s\n' "$1"; }
missing() { printf 'MISSING  %s\n         fix: %s\n' "$1" "$2"; MISSING_COUNT=$((MISSING_COUNT + 1)); }

APT_HINT="sudo apt-get install -y usbmuxd libimobiledevice-utils libimobiledevice6 ideviceinstaller usbutils"

echo "== Tabula device doctor (read-only) =="

# --- usbmuxd -----------------------------------------------------------------------------------------------
if [ -x /usr/sbin/usbmuxd ] || command -v usbmuxd >/dev/null 2>&1; then
  ok "usbmuxd binary: $(command -v usbmuxd || echo /usr/sbin/usbmuxd)"
else
  missing "usbmuxd binary" "$APT_HINT"
fi
if pgrep -x usbmuxd >/dev/null 2>&1; then
  ok "usbmuxd daemon is running"
else
  info "usbmuxd daemon is not running. Normal until a phone is attached: the udev rule 39-usbmuxd.rules starts it."
  info "  if the phone is attached and it still does not start: sudo usbmuxd -f -v   (leave it running in a second terminal)"
fi

# --- libimobiledevice tools ----------------------------------------------------------------------------------
for t in idevice_id ideviceinfo idevicepair idevicesyslog; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else missing "$t" "$APT_HINT"; fi
done
if command -v ideviceinstaller >/dev/null 2>&1; then
  ok "ideviceinstaller (optional)"
else
  info "ideviceinstaller not installed (optional; xtool installs apps itself)."
fi
if command -v lsusb >/dev/null 2>&1; then ok "lsusb (optional)"; else info "lsusb not installed (optional; sudo apt-get install -y usbutils)"; fi

# --- USB/IP kernel support (for usbipd-win) ---------------------------------------------------------------------
if [ -d /sys/bus/platform/drivers/vhci_hcd ]; then
  ok "kernel USB/IP client driver (vhci_hcd) loaded"
elif command -v modinfo >/dev/null 2>&1 && modinfo vhci_hcd >/dev/null 2>&1; then
  ok "kernel USB/IP client driver (vhci_hcd) available as a module (loads on 'usbipd attach')"
else
  warn "no vhci_hcd driver found in kernel $(uname -r); usbipd-win attach needs WSL kernel >= 5.10.60.1 (wsl --update in Windows)."
fi

# --- xtool ------------------------------------------------------------------------------------------------------
if command -v xtool >/dev/null 2>&1; then
  ok "xtool: $(command -v xtool) ($(xtool --version 2>&1 | head -n 1))"
  # Only the logged-in/out state is reported; the raw output (which may name the account) is never printed.
  auth_out="$(xtool auth status 2>&1 | head -n 1)"
  if printf '%s' "$auth_out" | grep -qi 'logged out'; then
    missing "xtool is not signed in (needed to install on a device, not to build)" \
            "run 'xtool auth login' yourself in an interactive terminal (docs/DEVICE_SETUP.md section 3); never paste credentials into chat"
  elif [ -n "$auth_out" ]; then
    ok "xtool is signed in (details withheld on purpose)"
  else
    warn "xtool auth status printed nothing; run 'xtool auth status' by hand."
  fi
  if sdk_out="$(xtool sdk status 2>&1)" && printf '%s' "$sdk_out" | grep -qi 'is installed'; then
    ok "Darwin SDK installed"
  else
    missing "Darwin SDK" "run 'xtool setup' (docs/ENVIRONMENT.md, human step H3)"
  fi
else
  missing "xtool" "install per docs/ENVIRONMENT.md section 2"
fi

# --- device visibility ---------------------------------------------------------------------------------------------
apple_usb=0
for v in /sys/bus/usb/devices/*/idVendor; do
  [ -r "$v" ] || continue
  if [ "$(cat "$v" 2>/dev/null)" = "05ac" ]; then apple_usb=$((apple_usb + 1)); fi
done
if [ "$apple_usb" -gt 0 ]; then
  ok "Apple USB device visible inside WSL ($apple_usb)"
else
  info "no Apple USB device visible inside WSL (Windows side: usbipd list / bind / attach --wsl)."
fi

devices=""
if command -v idevice_id >/dev/null 2>&1; then
  devices="$(timeout 15 idevice_id -l 2>/dev/null || true)"
fi
if [ -n "$devices" ]; then
  while IFS= read -r udid; do
    [ -n "$udid" ] || continue
    ok "device attached and paired: ${udid:0:8}... (UDID shortened)"
    # Developer Mode (iOS 16+). Query is best-effort and may be unreadable on some versions.
    dm="$(timeout 15 ideviceinfo -u "$udid" -q com.apple.security.mac.amfi -k DeveloperModeStatus 2>/dev/null || true)"
    case "$dm" in
      true)  ok "Developer Mode is ON" ;;
      false) warn "Developer Mode is OFF. Enable: Settings > Privacy & Security > Developer Mode, then restart the phone." ;;
      *)     info "Developer Mode state not readable (menu appears only after the first dev install attempt)." ;;
    esac
  done <<<"$devices"
else
  echo
  echo "NO DEVICE: no paired iPhone is attached. This is expected until the phone is plugged in."
  echo "           Steps: docs/DEVICE_SETUP.md sections 1 and 2 (usbipd bind/attach on Windows, then Trust on the phone)."
  if ! pgrep -x usbmuxd >/dev/null 2>&1; then
    echo "           (idevice_id also reports an error while usbmuxd is not running; that is not a failure by itself.)"
  fi
fi

echo
echo "== summary: $MISSING_COUNT item(s) MISSING (exit status is always 0; read the lines above) =="
exit 0
