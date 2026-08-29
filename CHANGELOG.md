# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The release workflow lifts the section matching a pushed tag out of this file
and publishes it as the release notes, so a version with no section here does
not get a release page.

## [0.1.1] - 2026-08-29

Documentation only. The bridge, the installer and the unit behave exactly as
they did in 0.1.0, and nothing already running has a reason to move for it.
The reason it is a release at all is that the tarball on the release page is
how this gets installed, so a correction to the README reaches nobody until a
tag ships one.

### Fixed

- **The example log line named an endpoint that no longer exists.** The
  debugging section showed `http://192.168.1.50/volup`, which stopped being a
  default before 0.1.0 shipped. Anybody comparing their journal against it
  would have concluded something was wrong when nothing was.
- **The re-install note undersold what the installer does.** It said an
  existing config was preserved, which is true and incomplete: settings the
  example has gained since are appended, with their comments, and it is the
  values already in the file that are left alone.
- **The reason initiator 11 is a test case was wrong**, in `AGENTS.md` and in
  `tests/engines.test.sh` both. It is there because its nibble is a letter,
  `b`, not because it is the first initiator that reading as decimal would
  misread. That would be 10.
- **`AGENTS.md` counted four shell scripts** where the repository holds
  twelve.

### Changed

- **The architecture diagram is Mermaid** rather than ASCII art, so GitHub
  draws it. Line style carries meaning now, and a legend says what: cables
  solid, the audio thick, and anything without a cable of its own dotted,
  which turns out to be the whole control path from the remote to the
  soundbar.
- **`--help` names the `-h` alias** it has accepted since 0.1.0 without
  mentioning.
- **The systemd unit says what it actually bridges.** The description named
  volume alone, though mute and power were handled in 0.1.0 too, so
  `systemctl status` now reports the full set.

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

[0.1.1]: https://github.com/mjaksn/cec-ir-bridge/releases/tag/v0.1.1
[0.1.0]: https://github.com/mjaksn/cec-ir-bridge/releases/tag/v0.1.0
