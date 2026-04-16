# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.8.5] - 2026-04-16

### Changed
- Bumped NUT version from 2.8.4 to 2.8.5
- Tightened runtime directory permissions on `/var/state/ups` to eliminate world-readable warning in upsd startup logs
- Added MIT LICENSE, CONTRIBUTING.md, and public accessibility documentation

### Security
- Set permissions 750 on `/var/state/ups`, `/run/nut`, and `/var/lib/nut` to restrict access to nut user

## [2.8.4] - 2026-03-01

### Added
- Initial stable release with NUT 2.8.4
- EcoFlow River 3 USB HID configuration (vendor 3746, product ffff)
- Comprehensive TrueNAS deployment guide in README
- Runtime diagnostics and USB debugging utilities
- Support for environment variable config overrides (NUT_UPS_NAME, NUT_DRIVER, NUT_PORT, etc.)
- Optional config mount points for nut.conf, ups.conf, upsd.conf, upsd.users
- Generated credentials for upsadmin and upsmon when not provided
- Detailed troubleshooting guide for insufficient USB permissions
