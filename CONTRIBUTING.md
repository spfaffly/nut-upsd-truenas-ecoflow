# Contributing

Thank you for your interest in contributing to nut-upsd-truenas-ecoflow!

## Reporting Issues

If you encounter a problem:

1. Check existing [issues](../../issues) to avoid duplicates.
2. Include:
   - NUT version (from `upsd -V` in container logs)
   - TrueNAS version
   - EcoFlow model or UPS device vendor/product ID
   - Full error message or startup logs
   - Steps to reproduce

## Submitting Changes

1. Fork and create a feature branch: `git checkout -b feature/your-change`
2. Make minimal, focused changes.
3. Test locally:
   - Build: `docker build -t nut-upsd-test .`
   - Run: `docker run -it --device /dev/bus/usb nut-upsd-test`
   - Verify startup logs show NUT version and UPS connection status.
4. Commit with a clear message: `git commit -m "Bump NUT to X.Y.Z"` or `"Fix: /var/state/ups permissions"`
5. Push and open a pull request.

## Guidelines

- **Version bumps**: Update `Dockerfile` ENV, `README.md` defaults, and `CHANGELOG.md`.
- **Config changes**: Ensure backward compatibility; document in `README.md`.
- **Driver changes**: Mention NUT upstream documentation or relevant issue number.
- **Security fixes**: Please disclose privately first if critical.

## License

By contributing, you agree your work is licensed under the MIT License.
