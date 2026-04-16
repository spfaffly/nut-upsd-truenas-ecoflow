# nut-upsd-truenas-ecoflow
This is a very specific Docker image that works specifically on Truenas Custom apps with configuration for Ecoflow River 3

## Included defaults

- NUT mode: `standalone`
- UPS name: `ecoflow-river3`
- Driver: `usbhid-ups`
- Port: `auto`
- NUT server listen: `0.0.0.0:3493`

## Build

```bash
docker build -t nut-upsd-truenas-ecoflow .
```

## Run (TrueNAS Custom App container)

Use host USB device passthrough for the EcoFlow River 3 and expose port `3493`.

```bash
docker run -d \
  --name nut-upsd \
  --restart unless-stopped \
  --device /dev/bus/usb \
  -p 3493:3493 \
  nut-upsd-truenas-ecoflow
```

## Optional config override

You can mount your own NUT config files to `/config`:

- `/config/nut.conf`
- `/config/ups.conf`
- `/config/upsd.conf`
- `/config/upsd.users`

Optional environment overrides:

- `NUT_UPS_NAME`
- `NUT_DRIVER`
- `NUT_PORT`
- `NUT_LISTEN_ADDR`
- `NUT_LISTEN_PORT`
- `NUT_UPSADMIN_PASSWORD`
- `NUT_UPSMON_PASSWORD`

## Security notes

- If `/config/upsd.users` is not provided, the container generates random `upsadmin` and `upsmon` passwords at startup (or uses `NUT_UPSADMIN_PASSWORD` and `NUT_UPSMON_PASSWORD` if set).
- `upsd` listens on `0.0.0.0:3493` by default for TrueNAS network access. You can override this with `NUT_LISTEN_ADDR` and `NUT_LISTEN_PORT`.
- Restrict NUT access with your network/firewall policy.
