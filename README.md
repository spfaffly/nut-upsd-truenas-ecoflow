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

## Security notes

- The included `upsd.users` file uses default credentials for initial setup. Override `/config/upsd.users` before production use.
- `upsd` listens on `0.0.0.0:3493` by default for TrueNAS network access. Restrict access with your network/firewall policy.
