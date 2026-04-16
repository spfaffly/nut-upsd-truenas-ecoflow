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

The startup log prints detailed diagnostics before NUT launches. Use this sequence:

1. **Check `uid=0`** — if not, user namespace remapping is active and likely causing the failure.
2. **Check `openable=` for each USB node** — `writable=yes openable=no` means cgroup device filtering is blocking the actual `open()` syscall even though file permissions look correct. Enable privileged mode in the TrueNAS app.
3. **Check the sysfs device list** — each USB device is listed with its class. `class=03` means HID. If `warning: no HID class (class=03) USB devices found` appears, the EcoFlow is not being passed through to the container at all. In TrueNAS, assign the specific EcoFlow USB device to the app rather than exposing the whole `/dev/bus/usb` bus.
4. **Check the hidraw line** — `info: hidraw device(s) found: /dev/hidraw0` means the EcoFlow is present but the kernel's `usbhid` driver has claimed it. Set `NUT_PORT=/dev/hidraw0` and ensure that device is also exposed to the container.
5. If the EcoFlow appears in sysfs (`class=03`) and `openable=yes`, but NUT still fails, set `NUT_PORT` to the explicit USB device path shown in the per-node log lines.

The generated `upsadmin` and `upsmon` credentials are unrelated to this USB access error.

## Security notes

- If `/config/upsd.users` is not provided, the container generates random `upsadmin` and `upsmon` passwords at startup (or uses `NUT_UPSADMIN_PASSWORD` and `NUT_UPSMON_PASSWORD` if set). Generated credentials are written to `/run/nut-generated-credentials` inside the container.
- Retrieve generated credentials with `docker exec <container-name> cat /run/nut-generated-credentials`.
- `upsd` listens on `0.0.0.0:3493` by default for TrueNAS network access. You can override this with `NUT_LISTEN_ADDR` and `NUT_LISTEN_PORT`.
- Restrict NUT access with your network/firewall policy.
