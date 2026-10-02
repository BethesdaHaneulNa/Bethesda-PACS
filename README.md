# Bethesda PACS

The optional **medical imaging (PACS) companion** for [Bethesda EMR](https://github.com/BethesdaHaneulNa/Bethesda-EMR).
It adds DICOM imaging to the clinic: a **modality worklist** (imaging devices automatically see
the patient + order the doctor placed), **image storage**, and **viewing the images inside the EMR**.

> **Non-profit project.** Part of the Bethesda EMR project, sponsored by the church
> **행복한 섬김의 열매 (Fruit of Joyful Devotion)** for **Bethesda Hospital, Madagascar**, and shared
> freely for other hospitals beginning to computerize.

---

## Important: this project does NOT include or modify Orthanc

The imaging server itself is **[Orthanc](https://www.orthanc-server.com/)** — a well-known
open-source DICOM server. **We do not ship, bundle, or modify Orthanc.** This repository only
contains:

- a `docker-compose.yml` that **pulls the official `orthancteam/orthanc` image** from Docker Hub and configures it,
- a small **worklist bridge** (our own code) that hands the EMR's orders to Orthanc,
- setup scripts and docs.

When you run it, Docker downloads Orthanc automatically. Orthanc remains the property of its
authors under its own (AGPLv3) license — see **License** below.

The Orthanc image is **pinned to a specific version** (currently `26.6.1`) rather than `:latest`.
With `:latest`, a clinic that reboots months from now can silently land on a newer Orthanc whose
configuration keys or database layout have changed — the PACS stops working, nobody touched
anything, and there may be no one on site who can diagnose it. Pinning means the version you
tested is the version that runs. To upgrade, bump the tag in `docker-compose.yml` deliberately,
test it, and keep the old number handy so you can roll back.

---

## How it works

```
   ┌─────────────┐   imaging orders (JSON feed)   ┌──────────────────┐
   │  Bethesda   │ ─────────────────────────────► │ worklist-bridge  │  (our code)
   │  EMR :9080  │   /api/pacs/worklist-feed       │  polls every 15s │
   └─────┬───────┘                                 └────────┬─────────┘
         │  viewer (iframe)                                  │ writes .wl files
         │                                                   ▼
         │                                          ┌──────────────────┐
         └────────────────── view images ──────────►│  Orthanc :9090   │  (official image)
                                                     │  DICOM    :4242  │
                                                     └────────┬─────────┘
                                          worklist query ▲    │ store images (C-STORE)
                                                          │    ▼
                                                   ┌─────────────────────┐
                                                   │  imaging devices     │
                                                   │  (X-ray, US, CR, …)  │
                                                   └─────────────────────┘
```

1. A doctor orders an X-ray/ultrasound/etc. in the EMR.
2. The bridge reads that order from the EMR's feed and writes a DICOM **worklist** file.
3. The imaging device queries the worklist and **sees the patient + order** automatically
   (no manual re-typing of the patient's name).
4. The device sends the captured image back to Orthanc (**C-STORE**).
5. Once the study has stopped growing (Orthanc's "stable", about a minute), the bridge tells the
   EMR. The order is marked done, the patient **leaves the device worklist**, and the EMR records
   whether the patient number inside the images matches the chart.
6. In the EMR, clicking the imaging order opens the image in the **viewer**, and the doctor can
   write the **radiology reading**.

---

## Quick start

Requires **Docker**. Set up the EMR first, then:

**Easy way (Windows):** download this repo as a ZIP (**`Code ▾` → Download ZIP**), unzip, and
double-click **`start.bat`**.

**Command line (Linux / macOS / NAS, or if you prefer):**
```bash
./setup.sh      # Linux / macOS / NAS
.\setup.ps1     # Windows PowerShell
```

The setup script generates a `.env` with a **random Orthanc password** and a **random bridge
token**, then starts Orthanc + the bridge. It prints the bridge token at the end.

### Pair it with the EMR (one-time)

**When the EMR runs on the same machine** (the usual case), setup pairs the two for you: it
writes one new bridge token into this folder's `.env` and into the EMR's settings, without
ever printing it. To do it again later — and **always after restoring an EMR backup**, which
brings the old machine's token with it — run:

```
.\pair-with-emr.ps1        # Windows
./pair-with-emr.sh         # Linux / NAS
```

When the EMR is on another machine, setup prints the token instead:

1. In the EMR, open **Settings → Order Feed**.
2. Set **Bridge Token** to the value the setup script printed (so the two trust each other).

The EMR shows the images itself: it relays the viewer and adds Orthanc's login on the server,
so staff never type the Orthanc password and port 9090 is published on `127.0.0.1` only (Orthanc's
admin pages: `http://localhost:9090` on the server). `pair-with-emr` also gives the EMR that
password. Only the imaging devices need to reach this machine, on port 4242.

On Windows, setup also runs `check-windows-ports.ps1`, which warns if Windows has reserved (or
may reserve) port 9090 or 4242 — see *PACS won't start, or the viewer never loads* below — and
if **another program is already listening** on 9080, 9090 or 4242 (it names the program). At the
end, setup waits up to a minute for the worklist bridge to really reach the EMR and says so, or
warns with the bridge's last error. (Windows `setup.ps1` only: `setup.sh` for Linux/NAS does not
have these two checks — the clinic's server is a Windows PC.)

That's it — orders placed in the EMR now appear on your imaging devices, and images come back
into the EMR.

---

## Connecting an imaging device

Point the device (or its workstation) at this host:

| Setting on the device | Value |
|---|---|
| Destination / PACS host | `<this-host-ip>` |
| DICOM port | `4242` |
| Called AE Title (Orthanc) | `MEDCONNECT` (the `ORTHANC__DICOM_AET` value) |
| Worklist (MWL) host/port | same host, `4242` |

The device's *own* AE Title can be anything — for an internal LAN, Orthanc is configured to
accept queries and images from any sender, and also **image types it does not know**
(`ORTHANC__UNKNOWN_SOP_CLASS_ACCEPTED: "true"`): old devices may send vendor-private types, and
refusing them is silent on the PACS side. They take disk space and the viewer may show nothing
for them (a crossed-out eye). To go back, set it to `"false"` and run `docker compose up -d`. The image is matched to the EMR order by its
**Study Instance UID**, which the worklist hands the device — not by the AE Title. A device that
makes up its own UID is still matched by the **accession number**; an image typed in by hand
without picking the patient from the worklist will not appear under the order in the EMR.

Turn **off** any "my AE only / Station AE" filter on the device's worklist query: EMR orders
carry no device name (every entry says `ANY`), so such a filter always returns 0.

### Watching a device while you set it up: `device-watch.bat`

Double-click **`device-watch.bat`** on this PC and leave it open while you try the settings on the
device. It says, one line at a time, what the PACS sees: a device connecting (AE and IP), a
connection test (C-ECHO), a worklist query and how many patients it got — and *why* when it got
0 (the device filters on its own AE, on another modality, on another date, or there is nothing
for today) — images received (patient ID, accession, compression) and whether they match an EMR
order (same patient ID, different ID, no ID, linked by accession, no order), then when the EMR
records them. Images the EMR put under another order are told apart ("put under another order
from the EMR (not sent by a device)"). A device that connects and leaves without asking or sending anything is reported
too: that is what the PACS shows when it did not accept the image type or transfer mode. Images
of a vendor-private type, or objects without a picture, are flagged ("stored, but the image window
may show nothing"). Of Orthanc's own warnings it shows only those from its DICOM threads (a
device connection), in plain words with the original below; warnings from the web side (admin
pages, the EMR's viewer, the bridge), the worklist housekeeper and Orthanc's coded notes
(`W001: …`) are left out.

```
.\device-watch.ps1                 # images only, changes nothing (Korean; -Lang fr / en)
.\device-watch.ps1 -Detail         # also connections and worklist queries (what the .bat runs)
.\device-watch.ps1 -Ping 192.168.1.50 -DevicePort 104 -DeviceAet XRAY01   # can this PC reach it?
.\device-watch.ps1 -Reset          # log level back, if a -Detail window was closed with its X
```

Orthanc writes connections and worklist queries to its log only at the *verbose* level. `-Detail`
raises the `generic`, `dicom` and `plugins` categories through the REST API (not `http`), says so,
and puts them back on Ctrl+C; an Orthanc restart also resets them. Nothing is written to Orthanc's
configuration. The tool reads the EMR's worklist table (`docker exec … psql`, read only) to match
images to orders. The step-by-step guide for the day: the EMR wiki,
`reference/device-connection-onsite.md`.

> The Called AE Title default is `MEDCONNECT` (an internal identifier kept in sync with the EMR).
> You can change `ORTHANC__DICOM_AET` in `docker-compose.yml`, but then set the device's Called AE
> to match.

## Ports

| Port | Purpose | Who needs it |
|------|---------|--------------|
| 9090 | Orthanc web UI / REST / DICOMweb | **this machine only** (`127.0.0.1`) — the EMR relays the viewer to staff |
| 4242 | DICOM (worklist query + image store) | imaging devices |

Keep these on the clinic LAN — **do not expose them to the internet.** Orthanc holds patient
images (PII).

### Windows: PACS won't start, or the viewer never loads
Windows (Hyper-V/WSL) reserves blocks of TCP ports for itself, and the blocks change on every
reboot. If a port you publish lands inside one of them, Docker can't bind it. You'll either get

```
bind: An attempt was made to access a socket in a way forbidden by its access permissions
```

or — worse — the container reports `Up` while nothing is actually listening on the host, so the
viewer just times out with no visible error anywhere.

This PACS used to publish **8090**, which sits inside a range Windows frequently reserves (we hit
`8013–8112` in practice). It now uses **9090**, outside those ranges. To inspect the reserved
ranges on a Windows host:

```
netsh interface ipv4 show excludedportrange protocol=tcp
```

If a port you need is listed, change it in `docker-compose.yml` rather than fighting Windows for
it. Linux hosts don't have this problem.

> 한국어 — Windows에서 PACS가 안 뜨거나 뷰어가 안 열리면 포트 충돌일 수 있어요. Windows가
> 재부팅할 때마다 임의의 포트 대역을 예약해버리는데, 거기 걸리면 Docker가 포트를 못 잡습니다.
> 컨테이너는 `Up`으로 보이는데 접속만 안 되는 경우가 있어 원인 찾기가 어려워요. 위 `netsh`
> 명령으로 예약된 대역을 확인하고, 겹치면 `docker-compose.yml`에서 포트를 바꾸세요.

## Image backup (Windows)

The EMR's own backup holds the database only - **not the images**, and it stays on the
same disk as the EMR. These scripts copy Orthanc's images **and the EMR's database
backups** to one external USB disk every night:

```
.\prepare-backup-disk.ps1 -Target E:\     # once per disk: marks it (drive letters change)
.\install-image-backup.ps1               # once: nightly task at 02:30 (-WhatIf to preview)
.\image-backup.ps1                       # what the task runs; safe to run by hand
.\restore-image-backup.ps1 -Verify       # monthly check (reads only)
.\restore-image-backup.ps1               # put the images back (disk failure, new PC)
```

Only images new since the last run are copied, as the original DICOM files, and no image
is ever deleted from the disk. The EMR's `backups\*.sql.gz` go to `BethesdaPACS\emr-backups`
on the same disk (checked by hash and as a complete gzip; the disk keeps the EMR's rule -
30 days, never fewer than the newest 7). The EMR folder is found beside this one
(`Bethesda-EMR*`), or pass `-EmrPath`. To restore one, copy it into the EMR's `backups`
folder and follow the EMR's `DEPLOYMENT.md` section 5b.

**Images put under another order in the EMR.** When an exam was done with the wrong line
of the same patient picked on the device, a doctor corrects it in the EMR (*Corriger la
demande…*): the image server gets a corrected study and the original is deleted there.
The files of the original would bring the wrong study back at a restore, so the nightly
backup asks the EMR which images those are and **sets their files aside** in
`BethesdaPACS\replaced\<date>\` - moved, not deleted, and only once the corrected images
are on the disk too. `restore-image-backup.ps1` never uploads that folder. If the disk is
restored before a backup has run since the correction, the restore asks the EMR itself
(restore and start the EMR first, as usual); pictures the disk holds only under their old
study number are uploaded as they are and the script says so, rather than lose them. Nothing
has to be done by hand then: the next time that patient's images are opened in the EMR, the
EMR sees that the image server is back in the state before the correction and makes the
correction again there (and writes a line in its change log, "Re-applied after a restore").
It does so only when everything matches what it recorded; if an exam keeps saying that the
image server does not have its images, the pictures are still on the server under the old
study number - call whoever supports the installation. The `replaced` folder can be cleared
by hand once the corrected studies have been checked in the viewer.

**The disk holds patient images and the whole EMR database, unencrypted.** Keep it
locked away, and never lend it or use it for anything else.

The EMR status screen warns when the disk is missing, full, or the backup has not
succeeded recently. Details: the EMR wiki, `modules/pacs.md` 6.2.

## Copying a patient's images to a CD: `cd-export.bat` (Windows)

Hospitals still ask for images on a CD. `cd-export.bat` is a small separate program for
that - double-click it on any PC that reaches the EMR (French; `-Lang ko`, `-Lang en`):

1. **Sign in** with an EMR account (Consultation or Payment). The first time it asks for
   the EMR's address (`http://<server>:9080`) and keeps it in `cd-export.ini` beside the
   program. No password and no token is ever written to disk.
2. Type the patient's **chart number**. The patient's name and date of birth are shown,
   to be checked, and the list of imaging exams with the number of images and the size.
3. **Tick** the exams. The window says how much they take and, when a blank disc is in
   the drive, whether they fit (it sees a disc put in by itself).
4. **Graver ce CD…** asks "burn N exams of this patient to the disc in drive X?", burns,
   checks the disc and opens the tray. **Enregistrer en fichier ISO…** and **Enregistrer
   dans un dossier…** do the same to a disc image or to a new folder (a USB stick) - they
   work on a PC without a burner. Every file written is read back and compared.

What is written is a standard DICOM disc - `DICOMDIR` and the original files under
`IMAGES\`, made by Orthanc itself (`/tools/create-media-extended`) - plus `README.TXT`
(whose images, which exams, how to read the disc; French then English) and `VOIR.EXE` (below).
No JPEG copies.

- The program talks to **the EMR only**, never to Orthanc: the Orthanc password is not in
  it, and it runs from a reception PC as well as from the server. The EMR checks the
  account's rights, refuses exams that must not leave (cancelled, or carrying an identity
  warning) and writes **one line in its change log per copy** - no line, no copy.
- Only a **blank** disc is written. A disc that already holds something is never used and
  never erased. The disc is closed: nothing can be added to it later. It is written at the
  slowest speed the drive offers and checked twice - by the drive, then file by file. A small
  exam takes about three minutes, most of it the check.
- Nothing is installed and no system setting is changed: burning is Windows' own (IMAPI2).
  The images fetched stay under `%TEMP%\BethesdaCD` while the copy is made and are removed
  afterwards (and at the next start, if the program was killed).
- A folder or an ISO saved by the program holds a patient's images, unencrypted: delete it
  when it is no longer needed.

**A small viewer on every disc: `VOIR.EXE`.** A hospital reads the disc with its own imaging
software; a patient or a small practice has none. So the disc carries the clinic's own viewer -
about 50 KB, started by a double-click, nothing installed and nothing left on the PC that runs
it: the exams and series of the disc on the left, the image on the right, window (left drag),
zoom (Ctrl + wheel), pan (right drag), invert, previous / next. Always in sight: "for
reference - not for diagnosis". Its source is `viewer\*.cs`; the program builds it into the
disc with the C# compiler that ships with Windows - no program file is kept in this repository.
It shows uncompressed images and JPEG: lossless JPEG - what the clinic's ultrasound machine
sends (GE LOGIQ P10: lossless, 8-bit RGB) - is decoded by the viewer itself, exactly; lossy
8-bit JPEG by the decoder that is part of Windows. RLE is decoded by the viewer too. A file of
several frames is stepped through with the wheel; there is no playback (no echocardiography at
the clinic). What the viewer does not open (JPEG 2000, JPEG-LS, 12-bit lossy JPEG, ...) does not
reach the disc compressed: when a chosen exam holds such an image, the EMR asks the image server
to unpack the whole bundle (lossless; the copy is larger - about three times for the clinic's
ultrasound images if they are in the same copy) and the closing message says so.
(Weasis on the disc was tried and dropped: 139 MB on every disc, about 95 MB left on the PC
that runs it.)

Files: `cd-export.bat` (start), `cd-export.ps1`, `cd-export-ui.ps1` (the window),
`cd-export-common.ps1` (the work), `viewer\*.cs` (the viewer's source). Needs an EMR that has `GET /api/pacs/export/patient`
and `/bundle` (EMR after 1.5.0). Details: the EMR wiki, `modules/pacs.md` 2.4.4.

## Test tools (optional)

`bridge/` includes small scripts to test your setup **without a real device**:
`make_demo.py` / `make_chest5.py` (generate fake DICOM images), `storetest.py` (send a test
image, C-STORE), `q_test.py` (query the worklist, C-FIND). Handy for verifying everything works
before connecting real equipment.

Run them inside the bridge container, which is on Orthanc's network. `make_demo.py` and
`make_chest5.py` read `ORTHANC_PASSWORD` from the environment (the container has it) and take
`STUDY_UID`, `ACCESSION` and `PATIENT_ID` of a test order from the environment too.
`storetest.py` and `q_test.py` need `pynetdicom`, which the bridge image does not include
(`pip install pynetdicom` first).

---

## Troubleshooting

**Setup says the worklist bridge does NOT reach the EMR, or the bridge container is `unhealthy`.**

The bridge logs why: `docker logs --tail 5 bethesda-worklist-bridge`. If it says *Something other
than the EMR answered …*, another program on this PC is using the EMR's port — in 2026 a download
manager (PikPak's `DownloadServer.exe`) sat on `127.0.0.1:9080`. The EMR still opened in a browser,
but the bridge reached that program and no worklist went to the devices. Run
`.\check-windows-ports.ps1` to see which program, close it (and stop it starting with Windows).
The bridge recovers by itself within a cycle. The container turns `unhealthy` when the EMR's feed
has not answered for two minutes, not only when the bridge process is stuck.

**The EMR's image window stays empty, or Settings → Order Feed warns under "image server address".**

That field is where the EMR, **inside this PC**, calls the image server — not an address for other
PCs. Leave it at `http://host.docker.internal:9090` (the **Default** button puts it back): port 9090
listens on this PC only, so this PC's LAN address there cannot work. The **Test image server**
button next to the DICOM test checks exactly that path, with the stored password.

**The EMR's "PACS connection test (DICOM)" shows a red ✗ when Host is `localhost`.**

This is expected — not a bug. That test runs from *inside the EMR's container*, and inside a
container `localhost` means the container itself, **not your PC**. So it can't reach Orthanc's
port `4242` on its own loopback.

Fix — in the EMR, open **Settings → Order Feed → PACS server → Host / IP** and change
`localhost` to:

```
host.docker.internal
```

That means "the host machine, as seen from inside a container" (works on Docker Desktop). Click
**Save** and test again — it should turn green. On a NAS / Linux host, or to reach it from other
PCs and imaging devices, use the host's **LAN IP** instead (e.g. `192.168.0.55`), which works
from both the container and a browser.

Also: this DICOM test is only a convenience check. The imaging integration actually works through
the **bridge token** (worklist feed) and the EMR's built-in viewer relay, so a red ✗ here does
**not** stop the worklist or image viewing from working.

> 한국어 — 연결 테스트가 빨간 ✗ 뜨면: Host/IP를 `localhost` 대신 **`host.docker.internal`**
> (또는 이 PC의 **LAN IP**)로 바꾸세요. 컨테이너 안에서 `localhost`는 PC가 아니라 컨테이너
> 자기 자신을 가리켜서 그래요. 이 테스트는 확인용이라 ✗여도 워크리스트·영상 보기 자체는 동작해요
> (영상은 EMR이 대신 보여 줍니다).

---

## Security

- The Orthanc admin password is **randomly generated** by setup (in `.env`, git-ignored). Login: user `admin`.
- The bridge token is random and must match the EMR's setting. The EMR refuses a token under 16
  characters or the old `change-me-…` placeholder, and the bridge sends it in a request header,
  never in a URL.
- Staff never need the Orthanc password: the EMR shows the viewer and adds the login on the server
  (`pair-with-emr` gives it the password on stdin). Port 9090 is published on `127.0.0.1` only.
- Keep port `4242` on the LAN only (imaging devices). Use a VPN for any remote access.

## Questions & feature requests

Please open an **Issue** on this repository (or on the main
[Bethesda EMR](https://github.com/BethesdaHaneulNa/Bethesda-EMR) repo).

문의·기능 요청은 이 저장소에 **Issue**를 남겨주세요.

## License

- **Our code** (the worklist bridge, compose, scripts, docs) is **source-available**: use and
  modify freely, **no redistribution** — same terms as Bethesda EMR. See [LICENSE](LICENSE).
- **Orthanc** is **not** part of this repository. It is pulled as an official Docker image and is
  licensed by its authors under the **GNU AGPLv3**. This project uses Orthanc as-is (unmodified)
  and does not distribute it. The clinic's own images may be corrected through Orthanc's REST API
  (the EMR renames a study that was taken under the wrong order, `POST /studies/{id}/modify`, and
  deletes the original); that is using Orthanc, not changing it.
- **The Stone Web Viewer** (it comes inside the Orthanc image, AGPLv3 as well) is not modified
  either. Bethesda EMR shows it to staff through its own address and passes on, byte for byte, what
  Orthanc serves; it uses Stone's own URL parameters only (`?study=…`), changes none of Stone's
  files and adds no code to its pages. If a change to Orthanc or Stone ever became necessary, it
  would be raised first — it would bring the AGPL's source-offer duty with it.

Companion to **[Bethesda EMR](https://github.com/BethesdaHaneulNa/Bethesda-EMR)**.
Built with Claude (vibe coding).
