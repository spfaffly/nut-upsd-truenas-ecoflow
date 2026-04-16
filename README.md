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

For TrueNAS Custom App deployments, the important requirement is that the app can access the UPS HID node under `/dev/bus/usb` with read and write permissions. If that device path is missing or inaccessible, NUT will fail with:

```text
libusb1: Could not open any HID devices: insufficient permissions on everything
No matching HID UPS found
```

In the TrueNAS UI, configure the app so that:

- USB devices are exposed to the container.
- Privileged mode is enabled if the standard device mapping still leaves the HID node inaccessible.
- Port `3493` is published.

```bash
docker run -d \
  --name nut-upsd \
  --restart unless-stopped \
  --device /dev/bus/usb \
  -p 3493:3493 \
  nut-upsd-truenas-ecoflow
```

If you are using the TrueNAS UI instead of a raw `docker run`, treat the command above as the equivalent runtime intent rather than a literal copy/paste command.

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

`NUT_PORT` can be used as a fallback when `port = auto` does not work in your environment. For example, if the app runtime exposes a specific USB device node and auto-detection still fails, set `NUT_PORT` to that device path or provide a custom `/config/ups.conf`.

## TrueNAS troubleshooting

If the container logs show `insufficient permissions on everything`, the image reached the USB driver startup step and the failure is at the runtime/device layer.

Use this sequence:

1. Confirm the TrueNAS app exposes the UPS USB device to the container.
2. If the app still cannot open the HID device, enable privileged mode as a diagnostic step.
3. Redeploy the app and review the startup logs.
4. Look for the new startup diagnostics.

- `warning: /dev/bus/usb is not present inside the container`
- `warning: /dev/bus/usb is present but no USB device nodes were found`
- `warning: some USB device nodes are not readable by the container`
- `info: detected USB device nodes under /dev/bus/usb`

1. If USB nodes are present but `port = auto` still does not find the UPS, set `NUT_PORT` explicitly or mount a custom `/config/ups.conf`.

The generated `upsadmin` and `upsmon` credentials are unrelated to this USB access error.

## Security notes

- If `/config/upsd.users` is not provided, the container generates random `upsadmin` and `upsmon` passwords at startup (or uses `NUT_UPSADMIN_PASSWORD` and `NUT_UPSMON_PASSWORD` if set). Generated credentials are written to `/run/nut-generated-credentials` inside the container.
- Retrieve generated credentials with `docker exec <container-name> cat /run/nut-generated-credentials`.
- `upsd` listens on `0.0.0.0:3493` by default for TrueNAS network access. You can override this with `NUT_LISTEN_ADDR` and `NUT_LISTEN_PORT`.
- Restrict NUT access with your network/firewall policy.
