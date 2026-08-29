# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The release workflow lifts the section matching a pushed tag out of this file
and publishes it as the release notes, so a version with no section here does
not get a release page.

## [0.1.0] - 2026-08-29

The first tagged release. The bridge itself has been working for a while; what
is new is that there is now a version number to say which one you are running,
a test suite that runs without a CEC adapter, and a release to install from
rather than a clone of whatever `main` happened to be.

### Fixed

- **Volume, mute and power presses fire a POST again.** The endpoints the
  example config ships are ESPHome button endpoints, which answer `405` to a
  `GET`, so every press had been failing silently since the `-X POST` flag was
  dropped by accident while the rogue-mute filter was being added. The new test
  suite asserts the method, so it cannot go missing quietly a second time.

### Added

- **A version.** `cec-ir-bridge --version` reports it, and `--help` prints the
  options and where the config lives. The release workflow refuses a tag that
  disagrees with it.
- **A test suite**, in plain bash with no framework and no dependencies. It
  drives both engines with recorded `cec-client` and `cec-ctl` output, so the
  frame decoding, the initiator filtering and the HTTP method are all checked
  without a Raspberry Pi, a TV or an ESP32. `tests/run.sh` runs it.
- **Continuous integration**: ShellCheck over every script, the suite above,
  and an end to end run of `install.sh` into a staged directory, gated behind
  one required check.
- **Releases.** Pushing a `v*` tag builds a tarball, checks the tag is on `main`
  and agrees with the version in the script, and publishes a release page whose
  notes are the section above.
- **`DESTDIR`**, which `install.sh` honours in the usual staged-install sense.
  Set it and every path hangs off it, which is what lets the installer be
  tested without root and without touching `/etc`.
- **`CEC_IR_BRIDGE_CONF`**, which points the bridge at a config file other than
  `/etc/cec-ir-bridge.conf`.
- An MIT licence, this changelog, and `AGENTS.md`.

### Changed

- **Every setting now has a default in the script itself.** A hand-edited
  config that dropped a line used to kill the service on the first frame that
  referenced the missing setting, because the script runs under `set -u`. The
  defaults and `cec-ir-bridge.conf.example` are checked against each other by
  the test suite, so the two cannot drift.
- **The engine parsing moved into `parse_cec_client` and `parse_cec_ctl`**,
  which read frames on standard input. Behaviour is unchanged; what changed is
  that a recorded capture can be piped through them, which is what the tests
  do.

[0.1.0]: https://github.com/mjaksn/cec-ir-bridge/releases/tag/v0.1.0
