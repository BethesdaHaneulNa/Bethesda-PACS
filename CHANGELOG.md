# Changelog

## v1.1.0 — 2026-09-30

Goes with **[Bethesda EMR v1.5.0](https://github.com/BethesdaHaneulNa/Bethesda-EMR/releases/tag/v1.5.0)**:
the two change together, and an EMR at 1.5.0 expects this PACS. The EMR's changelog
(section *Imaging (PACS)*) tells the whole story from the doctor's side; this is the PACS
folder's part of it.

**The images can live on a drive of their own.** `ORTHANC_STORAGE_PATH` in `.env` names the
folder (setup asks at the first installation; not set = `storage\` here, as before), and
`move-image-storage.ps1` moves an existing store there: stop, copy, compare, start, check
that the image server holds what it held, keep the old folder under another name. The
store carries a marker file and the image server does not start on a folder that has
neither the marker nor an image index - when the store's disk is missing, Docker Desktop
makes an empty folder of that name, and an image server started on it would look healthy
and hold nothing. The bridge reports the free room of the store's own disk, and the backup
scripts refuse (or report) a backup disk that is the same physical disk as the images.

**The worklist feed no longer answers to the published token.** The bridge token had a
default, `change-me-bridge-token`, published in this repository and accepted by the EMR:
any EMR never paired with a PACS handed today's imaging patients to anyone who knew that
string. The bridge now sends the token in a header instead of the URL, and `setup`
generates a random token and a random Orthanc password on first run. **`pair-with-emr.ps1`**
(and `.sh`) pairs the PACS with the EMR on the same machine through standard input and
compares by hash — the values never appear on screen, on a command line or in a log.
`setup` runs it by itself when the EMR is already up. Run it again after every restore of
an EMR backup.

**The EMR knows when the images have arrived.** Every cycle the bridge asks Orthanc whether
each scheduled study has arrived and settled, and tells the EMR, which marks the order done
and drops it from the device worklist — a patient no longer stays on the device list all
day after being imaged. When a device ignores the study number it was given, the bridge
finds the study by the order's accession number and reports the device's real one. A bridge
that cannot ask Orthanc says so in its heartbeat, and the EMR's status turns yellow instead
of staying green.

**Doctors see images without an Orthanc login.** The EMR relays the Stone viewer itself, so
Orthanc's web port now listens only on the server PC (`127.0.0.1:9090`); devices keep
sending to 4242 on the network. Stone's "Intended use" box is turned off (after closing it
the image area stayed black until the window was resized).

**Images and the EMR's backups go to an external disk every night.** `prepare-backup-disk.ps1`
marks a USB disk; `install-image-backup.ps1` registers a 02:30 task (run it on the clinic's
server PC, not on the PC the kit was prepared on); `image-backup.ps1` copies the images new
since the last run as plain DICOM files, then the EMR's own database backups, each checked
by hash and as a complete gzip and kept by the EMR's rule (30 days, never fewer than the
newest seven). A disk carried to another server, or an Orthanc refilled from the backup, is
recognised and nothing is skipped. A disk pulled during a run is reported as such and the
next run continues. `restore-image-backup.ps1` puts the images back and checks every EMR
imaging order against Orthanc; `-Verify` checks the disk without writing. Each run reports
counts and free space to the EMR (no patient data); the disk is not encrypted and holds the
whole EMR database, so it must be kept locked away.

**Smaller.** `check-windows-ports.ps1` warns when Windows has reserved 9090 or 4242, which
made a healthy-looking PACS unreachable. An isolated PACS stack (`docker-compose.session.yml`,
9198 / 11298) for testing beside a running one. Test tools no longer contain an old Orthanc
password or real-looking patient details.

**After updating:** recreate the PACS from this folder after the EMR has been updated; run
`pair-with-emr.ps1`; remove any firewall rule that opened 9090 to other PCs; set up the
image backup disk; and if the Windows dynamic port range starts near 1024, set it back to
49152 (`check-windows-ports.ps1` says how).

## v1.0.2 — 2026-07-24

**Can be installed with no internet.** The worklist bridge image now has a name
of its own (`bethesda-pacs-worklist-bridge`) instead of relying on the one
Compose invents, which is what lets `docker save` pick it up — and `setup`
learned an `-Offline` / `--offline` flag that starts from pre-loaded images
without building. Orthanc is a 2 GB pull, so a clinic on a slow link had little
chance of installing imaging at all.

Pack it alongside the EMR with that project's `offline/pack.ps1`; see
**[Bethesda EMR v1.3.0](https://github.com/BethesdaHaneulNa/Bethesda-EMR/releases/tag/v1.3.0)**
and its `OFFLINE-INSTALL.md`.

## v1.0.1 — 2026-07-23

**The bridge now says it is still there.** It could stop or wedge and the only
trace was a line in a container log; on the device it simply looks like the
patients were never scheduled, and there is nobody on site to connect the two.

After every cycle it writes a timestamp the container healthcheck reads — which
keeps working when the EMR is unreachable, exactly when we want to know whether
this process is alive — and posts the same news to the EMR, which puts it on a
screen the clinic already looks at. Neither can interrupt the sync loop; a failed
report is swallowed, because the EMR being down is already its own alarm.

Orthanc gained a healthcheck too. It asks the REST API rather than trusting the
process to be running; `/system` needs a login, so a 401 is a good answer here —
it proves the server is listening and serving.

Pair with **[Bethesda EMR v1.2.0](https://github.com/BethesdaHaneulNa/Bethesda-EMR/releases/tag/v1.2.0)**
or newer, which shows all of this in a status window on the clinic's machine.

## v1.0.0 — 2026-07-23

First tagged release. Modality worklist bridge + Orthanc for Bethesda EMR.

One unconvertible order no longer empties the whole worklist: the sync loop had
no per-row guard, so an order that could not be turned into a worklist file
aborted the entire cycle and every patient after it in the list silently lost
their entry.
