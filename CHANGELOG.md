# Changelog

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
