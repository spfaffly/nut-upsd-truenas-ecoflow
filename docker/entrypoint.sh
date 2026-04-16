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
  # This reveals whether the EcoFlow is actually present in the container's USB view.
  # HID class devices show class=03; the EcoFlow River 3 should appear in this list.
  if [ -d /sys/bus/usb/devices ]; then
    echo "info: USB devices visible in sysfs (class=03 means HID):" >&2
    found_hid=0
    for dev_dir in /sys/bus/usb/devices/*/; do
      [ -f "${dev_dir}idVendor" ] || continue
      vendor="$(cat "${dev_dir}idVendor" 2>/dev/null || echo '????')"
      product="$(cat "${dev_dir}idProduct" 2>/dev/null || echo '????')"
      class="$(cat "${dev_dir}bDeviceClass" 2>/dev/null || echo '??')"
      manuf="$(cat "${dev_dir}manufacturer" 2>/dev/null || true)"
      prod_name="$(cat "${dev_dir}product" 2>/dev/null || true)"
      echo "info:   ${dev_dir##/*/} vendor=$vendor product=$product class=$class${manuf:+ $manuf}${prod_name:+ $prod_name}" >&2
      if [ "$class" = "03" ]; then
        found_hid=1
      fi
    done
    if [ "$found_hid" -eq 0 ]; then
      echo "warning: no HID class (class=03) USB devices found in sysfs" >&2
      echo "hint: the EcoFlow is likely not being passed through to this container" >&2
      echo "hint: in TrueNAS, assign the specific EcoFlow USB device to this app, not just /dev/bus/usb" >&2
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
