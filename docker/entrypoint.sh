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

upsdrvctl -u root start
exec upsd -F
