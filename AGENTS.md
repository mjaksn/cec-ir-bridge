# Working in this repository

cec-ir-bridge registers a Raspberry Pi on the HDMI-CEC bus as an Audio System, so
that the volume buttons in the Apple TV Remote app come alive, and turns the CEC
commands they send into HTTP calls at an ESP32 IR blaster. It is a handful of
shell scripts and a systemd unit. There is no build step, no package and no
runtime dependency beyond what `install.sh` installs from apt.

Those are constraints rather than accidents. It runs on a Pi Zero 2 W, it is
started by systemd before anybody is watching, and the person debugging it at
eleven at night has `journalctl` and nothing else.

## Shape of the project

| Path | What it is |
| --- | --- |
| `bin/cec-ir-bridge` | The bridge. Parses CEC frames, filters by initiator, fires HTTP. |
| `install.sh` | Installs the above, the unit and the config. Safe to re-run. |
| `cec-ir-bridge.conf.example` | The config an operator edits, installed to `/etc`. |
| `systemd/cec-ir-bridge.service` | The unit. |
| `scripts/build.sh` | Builds the release tarball. One file list, used by CI and the release. |
| `tests/` | Plain bash. No framework, no dependencies, no hardware. |

## Rules the tooling enforces

CI runs these on every pull request, so they are worth knowing before rather
than after:

- **The version lives in `bin/cec-ir-bridge`, in `VERSION`, and nowhere else.**
  A release additionally requires the tag to match it and `CHANGELOG.md` to
  have a `## [x.y.z]` section for it.
- **Every setting has a default in `bin/cec-ir-bridge` and the same value in
  `cec-ir-bridge.conf.example`.** `tests/config.test.sh` compares the two
  files, so adding a setting to one and not the other fails.
- **ShellCheck passes on every script**, the test suite and the stubs included.
- **The release tarball installs.** CI unpacks it and runs the installer from
  the unpacked copy, not from the repository.

## Things that are easy to get wrong

- **The calls are POSTs.** ESPHome's `/button/<id>/press` endpoints answer 405
  to a GET, so dropping `-X POST` from `fire()` leaves every press failing
  silently, with nothing in the log to say so. This has happened once already.
  `tests/dispatch.test.sh` asserts the method for that reason.
- **Initiator addresses are decimal everywhere**, and the libcec parser reads
  them out of a hex nibble. `0` is the TV, `4`, `8` and `11` are playback
  devices, `5` is the audio system. Initiator 11 exists as a test case because
  its nibble is a letter (`b`), so reading the nibble as decimal rather than
  hex would go wrong.
- **Filtering must never be silent.** An ignored command still gets a line in
  the journal. The README promises this and the suite checks it, because a
  filter that hides bus activity makes the next fault harder to find, not
  easier.
- **`install.sh` never touches a value an operator has set.** Re-running it
  appends settings the example has gained, with their comments, and nothing
  else. That merge is the least obvious code here and
  `tests/install.test.sh` is mostly about it.
- **Both engines must agree.** `cec-client` and `cec-ctl` are two ways of
  reading the same bus, and a change to how one decodes an event belongs in the
  other. The suite drives both from recorded output and asserts that one volume
  press is the same call either way.

## Tests

```bash
tests/run.sh              # everything
tests/run.sh install      # just the suites whose name matches
```

No CEC adapter, no Raspberry Pi, no ESP32 and no network. The engines are
driven from recorded captures in `tests/fixtures/`, `curl` is a stub on `PATH`
that records the URL and the method instead of fetching, and the installer runs
into a temporary directory with `apt-get` and `systemctl` stubbed. It is safe to
run on a development machine.

When a bug turns out to be a frame the bridge misread, add the offending lines
to the fixture rather than writing a new one. The fixtures are meant to look
like real captures, because that is the thing being parsed.

## Adding to it

- **No dependencies.** Not for the bridge, not for the tests, not for the
  tooling. ShellCheck is used because the runner already has it.
- **Prose the program emits is documentation.** The `--help` text, the log
  lines and the installer's closing summary age exactly as the README does, and
  a claim usually appears in more than one of them.
- **A setting added to the example config needs a default in the script, a row
  in the README table and, if it changes behaviour anyone would notice, a
  changelog entry.**
