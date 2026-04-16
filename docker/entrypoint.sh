#!/bin/sh
set -eu

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&|]/\\&/g'
}

if [ -f /config/ups.conf ]; then
  cp /config/ups.conf /etc/nut/ups.conf
fi

if [ -f /config/upsd.conf ]; then
  cp /config/upsd.conf /etc/nut/upsd.conf
fi

if [ -f /config/nut.conf ]; then
  cp /config/nut.conf /etc/nut/nut.conf
fi

if [ -f /config/upsd.users ]; then
  cp /config/upsd.users /etc/nut/upsd.users
fi

if [ "${NUT_UPS_NAME:-}" != "" ]; then
  UPS_NAME_ESCAPED="$(escape_sed_replacement "${NUT_UPS_NAME}")"
  sed "0,/^\[.*\]$/s//[${UPS_NAME_ESCAPED}]/" /etc/nut/ups.conf > /tmp/ups.conf
  mv /tmp/ups.conf /etc/nut/ups.conf
fi

if [ "${NUT_DRIVER:-}" != "" ]; then
  DRIVER_ESCAPED="$(escape_sed_replacement "${NUT_DRIVER}")"
  sed "s|^[[:space:]]*driver[[:space:]]*=.*|  driver = ${DRIVER_ESCAPED}|" /etc/nut/ups.conf > /tmp/ups.conf
  mv /tmp/ups.conf /etc/nut/ups.conf
fi

if [ "${NUT_PORT:-}" != "" ]; then
  PORT_ESCAPED="$(escape_sed_replacement "${NUT_PORT}")"
  sed "s|^[[:space:]]*port[[:space:]]*=.*|  port = ${PORT_ESCAPED}|" /etc/nut/ups.conf > /tmp/ups.conf
  mv /tmp/ups.conf /etc/nut/ups.conf
fi

chown root:nut /etc/nut/* || echo "warning: failed to set /etc/nut ownership" >&2
chmod 640 /etc/nut/* || echo "warning: failed to set /etc/nut permissions" >&2

upsdrvctl -u root start
exec upsd -F
