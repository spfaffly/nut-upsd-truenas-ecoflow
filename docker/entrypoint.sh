#!/bin/sh
set -eu

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&|]/\\&/g'
}

update_ups_conf() {
  expression="$1"
  tmp_file="$(mktemp)"
  sed "$expression" /etc/nut/ups.conf > "$tmp_file"
  mv "$tmp_file" /etc/nut/ups.conf
}

generate_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

log_nut_versions() {
  upsd -V 2>&1 | sed 's/^/info: /' >&2 || true
  upsdrvctl -V 2>&1 | sed 's/^/info: /' >&2 || true
}

ensure_runtime_dirs() {
  mkdir -p /var/state/ups /run/nut /var/lib/nut
  chown nut:nut /var/state/ups /run/nut /var/lib/nut 2>/dev/null || true
  chmod 750 /var/state/ups /run/nut /var/lib/nut 2>/dev/null || true
}

log_usb_diagnostics() {
  echo "info: running as uid=$(id -u) gid=$(id -g)" >&2

  if [ ! -d /dev/bus/usb ]; then
    echo "warning: /dev/bus/usb is not present inside the container" >&2
    echo "warning: usbhid-ups needs the USB bus exposed by the runtime" >&2
  else
    usb_nodes="$(find /dev/bus/usb -mindepth 2 -maxdepth 2 -type c 2>/dev/null)"
    if [ -z "$usb_nodes" ]; then
      echo "warning: /dev/bus/usb is present but no USB device nodes were found" >&2
    else
      echo "info: detected USB device nodes under /dev/bus/usb" >&2
      echo "$usb_nodes" | while IFS= read -r node; do
        perms="$(ls -la "$node" 2>/dev/null || echo 'unreadable')"
        readable="$([ -r "$node" ] && echo yes || echo no)"
        writable="$([ -w "$node" ] && echo yes || echo no)"
        # Test actual open() with O_RDWR — -w only checks file permissions (access syscall),
        # not cgroup device rules, which are enforced at open() time.
        if (exec 3<>"$node") 2>/dev/null; then
          openable=yes
        else
          openable=no
        fi
        echo "info: $node readable=$readable writable=$writable openable=$openable -- $perms" >&2
        if [ "$writable" = yes ] && [ "$openable" = no ]; then
          echo "warning: $node cannot be opened despite file permissions allowing it" >&2
          echo "hint: cgroup device filtering is likely blocking open(); try enabling privileged mode in TrueNAS" >&2
        fi
      done
    fi
  fi

  # Enumerate USB devices from sysfs to show vendor/product/class for each device.
  # Cross-reference sysfs with /dev/bus/usb using busnum/devnum.
  # For multi-function devices (class=ef), HID is declared at the interface level,
  # not the device level, so we check both.
  if [ -d /sys/bus/usb/devices ]; then
    echo "info: USB devices visible in sysfs:" >&2
    found_hid=0
    for dev_dir in /sys/bus/usb/devices/*/; do
      [ -f "${dev_dir}idVendor" ] || continue
      vendor="$(cat "${dev_dir}idVendor" 2>/dev/null || echo '????')"
      product="$(cat "${dev_dir}idProduct" 2>/dev/null || echo '????')"
      dev_class="$(cat "${dev_dir}bDeviceClass" 2>/dev/null || echo '??')"
      busnum="$(cat "${dev_dir}busnum" 2>/dev/null | tr -d '[:space:]')"
      devnum="$(cat "${dev_dir}devnum" 2>/dev/null | tr -d '[:space:]')"
      manuf="$(cat "${dev_dir}manufacturer" 2>/dev/null || true)"
      prod_name="$(cat "${dev_dir}product" 2>/dev/null || true)"
      dev_node="$(printf '/dev/bus/usb/%03d/%03d' "$busnum" "$devnum" 2>/dev/null || echo unknown)"

      # Collect interface classes (handles class=ef multi-function devices where
      # HID is only declared at the interface level, not the device level)
      iface_classes=""
      for iface_dir in "${dev_dir}"*/; do
        [ -f "${iface_dir}bInterfaceClass" ] || continue
        ic="$(cat "${iface_dir}bInterfaceClass" 2>/dev/null)"
        iface_classes="${iface_classes:+${iface_classes},}${ic}"
        [ "$ic" = "03" ] && found_hid=1
      done
      [ "$dev_class" = "03" ] && found_hid=1

      echo "info:   $dev_node vendor=$vendor product=$product devclass=$dev_class${iface_classes:+ ifaces=$iface_classes}${manuf:+ $manuf}${prod_name:+ $prod_name}" >&2
    done
    if [ "$found_hid" -eq 0 ]; then
      echo "warning: no HID class (03) found at device or interface level in sysfs" >&2
      echo "hint: usbhid-ups requires a HID Power Device Class interface; the EcoFlow may use a proprietary protocol" >&2
      echo "hint: check NUT compatibility for vendor=3746 product=ffff and consider a different driver" >&2
    fi
  else
    echo "info: /sys/bus/usb/devices not accessible; cannot enumerate USB device identities" >&2
  fi

  # Check for hidraw devices as a fallback interface
  hidraw_nodes="$(find /dev -maxdepth 1 -name 'hidraw*' -type c 2>/dev/null)"
  if [ -n "$hidraw_nodes" ]; then
    echo "info: hidraw device(s) found: $hidraw_nodes" >&2
    echo "hint: if usbfs access fails, try setting NUT_PORT to one of these (e.g. NUT_PORT=/dev/hidraw0)" >&2
  else
    echo "info: no /dev/hidraw* devices found" >&2
  fi
}

if [ -f /config/ups.conf ]; then
  cp /config/ups.conf /etc/nut/ups.conf
fi

if [ -f /config/upsd.conf ]; then
  cp /config/upsd.conf /etc/nut/upsd.conf
fi

if [ "${NUT_LISTEN_ADDR:-}" != "" ] || [ "${NUT_LISTEN_PORT:-}" != "" ]; then
  LISTEN_ADDR="${NUT_LISTEN_ADDR:-0.0.0.0}"
  LISTEN_PORT="${NUT_LISTEN_PORT:-3493}"
  printf 'LISTEN %s %s\n' "${LISTEN_ADDR}" "${LISTEN_PORT}" > /etc/nut/upsd.conf
fi

if [ -f /config/nut.conf ]; then
  cp /config/nut.conf /etc/nut/nut.conf
fi

if [ -f /config/upsd.users ]; then
  cp /config/upsd.users /etc/nut/upsd.users
else
  UPSADMIN_PASSWORD="${NUT_UPSADMIN_PASSWORD:-}"
  UPSMON_PASSWORD="${NUT_UPSMON_PASSWORD:-}"
  GENERATED_CREDENTIALS=0

  if [ "$UPSADMIN_PASSWORD" = "" ]; then
    UPSADMIN_PASSWORD="$(generate_password)"
    GENERATED_CREDENTIALS=1
  fi

  if [ "$UPSMON_PASSWORD" = "" ]; then
    UPSMON_PASSWORD="$(generate_password)"
    GENERATED_CREDENTIALS=1
  fi

  if [ "${GENERATED_CREDENTIALS}" -eq 1 ]; then
    mkdir -p /run
    umask 077
    cat > /run/nut-generated-credentials <<EOF
NUT_UPSADMIN_PASSWORD='${UPSADMIN_PASSWORD}'
NUT_UPSMON_PASSWORD='${UPSMON_PASSWORD}'
EOF
    echo "warning: generated credentials were written to /run/nut-generated-credentials" >&2
  fi

  cat > /etc/nut/upsd.users <<EOF
[upsadmin]
  password = ${UPSADMIN_PASSWORD}
  actions = SET
  instcmds = ALL

[upsmon]
  password = ${UPSMON_PASSWORD}
  upsmon master
EOF
fi

if [ "${NUT_UPS_NAME:-}" != "" ]; then
  UPS_NAME_ESCAPED="$(escape_sed_replacement "${NUT_UPS_NAME}")"
  update_ups_conf "0,/^\[.*\]$/s//[${UPS_NAME_ESCAPED}]/"
fi

if [ "${NUT_DRIVER:-}" != "" ]; then
  DRIVER_ESCAPED="$(escape_sed_replacement "${NUT_DRIVER}")"
  update_ups_conf "s|^[[:space:]]*driver[[:space:]]*=.*|  driver = ${DRIVER_ESCAPED}|"
fi

if [ "${NUT_PORT:-}" != "" ]; then
  PORT_ESCAPED="$(escape_sed_replacement "${NUT_PORT}")"
  update_ups_conf "s|^[[:space:]]*port[[:space:]]*=.*|  port = ${PORT_ESCAPED}|"
fi

for config_file in /etc/nut/nut.conf /etc/nut/ups.conf /etc/nut/upsd.conf /etc/nut/upsd.users; do
  if [ -f "${config_file}" ]; then
    chown root:nut "${config_file}" || echo "warning: failed to set ownership on ${config_file}" >&2
    chmod 640 "${config_file}" || echo "warning: failed to set permissions on ${config_file}" >&2
  fi
done

ensure_runtime_dirs
log_nut_versions
log_usb_diagnostics

# The kernel usbhid driver may have auto-bound to the UPS HID device, which
# prevents libusb from claiming it via usbfs. This replicates what NUT's udev
# rules do on a host system but cannot do inside a container.
unbind_kernel_hid_drivers() {
  if [ ! -d /sys/bus/usb/drivers/usbhid ]; then
    echo "info: /sys/bus/usb/drivers/usbhid not found, skipping unbind" >&2
    return
  fi
  found=0
  for iface_path in /sys/bus/usb/drivers/usbhid/*:*; do
    [ -e "$iface_path" ] || continue
    iface_id="$(basename "$iface_path")"
    found=1
    echo "info: unbinding kernel usbhid driver from interface $iface_id" >&2
    if echo "$iface_id" > /sys/bus/usb/drivers/usbhid/unbind 2>/dev/null; then
      echo "info: unbound $iface_id" >&2
    else
      echo "warning: could not unbind $iface_id (may need privileged mode or CAP_SYS_ADMIN)" >&2
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "info: no usbhid-bound interfaces found to unbind" >&2
  fi
}
unbind_kernel_hid_drivers

upsdrvctl -u root start
exec upsd -F
