#!/bin/sh
set -eu

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
  sed "s/^\[.*\]$/[${NUT_UPS_NAME}]/" /etc/nut/ups.conf > /tmp/ups.conf
  mv /tmp/ups.conf /etc/nut/ups.conf
fi

if [ "${NUT_DRIVER:-}" != "" ]; then
  sed "s|^[[:space:]]*driver[[:space:]]*=.*|  driver = ${NUT_DRIVER}|" /etc/nut/ups.conf > /tmp/ups.conf
  mv /tmp/ups.conf /etc/nut/ups.conf
fi

if [ "${NUT_PORT:-}" != "" ]; then
  sed "s|^[[:space:]]*port[[:space:]]*=.*|  port = ${NUT_PORT}|" /etc/nut/ups.conf > /tmp/ups.conf
  mv /tmp/ups.conf /etc/nut/ups.conf
fi

chown root:nut /etc/nut/* || true
chmod 640 /etc/nut/* || true

upsdrvctl -u root start
exec upsd -F
