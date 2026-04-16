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

`NUT_PORT` can be used as a fallback when `port = auto` does not work in your environment.

**Option A — Specific USB device node** (preferred when the exact device is known):

```sh
NUT_PORT=/dev/bus/usb/001/005
```

Replace `001/005` with the actual bus and device numbers visible in TrueNAS or from `lsusb` on the host.

**Option B — hidraw interface** (use when the EcoFlow is exposed via `/dev/hidraw*` instead of usbfs):

```sh
NUT_PORT=/dev/hidraw0
```

The startup log will print `info: hidraw device(s) found: ...` if this interface is available, and suggest it as an alternative. You can also provide a full `/config/ups.conf` override with `port = /dev/hidraw0` instead of using the environment variable.

## TrueNAS troubleshooting

If the container logs show `insufficient permissions on everything`, the image reached the USB driver startup step and the failure is at the runtime/device layer.

The startup log now prints detailed diagnostics before NUT launches. Use this sequence:

1. **Check the UID line** — `info: running as uid=0` confirms the container process is root. Any other UID means user namespace remapping is active and likely causing the failure.
2. **Check per-device lines** — lines like `info: /dev/bus/usb/001/005 readable=yes writable=no` indicate the device is visible but libusb cannot open it. Enable privileged mode in the TrueNAS app or ensure the app has write access to the USB device cgroup.
3. **Check for `writable=no` warnings** — `warning: one or more USB device nodes are not writable` with `hint: try enabling privileged mode` is the most common cause after device visibility is confirmed.
4. **Check the hidraw line** — `info: hidraw device(s) found: /dev/hidraw0` means the EcoFlow is exposed through a different interface. Set `NUT_PORT=/dev/hidraw0` (or the shown path) in the TrueNAS app environment variables, and ensure that device is also passed to the container.
5. If `port = auto` still does not find the UPS after confirming writable access, set `NUT_PORT` to the explicit device path shown in the log.

The generated `upsadmin` and `upsmon` credentials are unrelated to this USB access error.

## Security notes

- If `/config/upsd.users` is not provided, the container generates random `upsadmin` and `upsmon` passwords at startup (or uses `NUT_UPSADMIN_PASSWORD` and `NUT_UPSMON_PASSWORD` if set). Generated credentials are written to `/run/nut-generated-credentials` inside the container.
- Retrieve generated credentials with `docker exec <container-name> cat /run/nut-generated-credentials`.
- `upsd` listens on `0.0.0.0:3493` by default for TrueNAS network access. You can override this with `NUT_LISTEN_ADDR` and `NUT_LISTEN_PORT`.
- Restrict NUT access with your network/firewall policy.
