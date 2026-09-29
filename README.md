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
may reserve) port 9090 or 4242 — see *PACS won't start, or the viewer never loads* below.

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
accept queries and images from any sender. The image is matched to the EMR order by its
**Study Instance UID**, which the worklist hands the device — not by the AE Title. The device must
keep that UID: a device that makes up its own, or an image typed in by hand without picking the
patient from the worklist, will not appear under the order in the EMR.

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

The EMR's own backup holds the database only - **not the images**. These scripts copy
Orthanc's images to an external USB disk every night:

```
.\prepare-backup-disk.ps1 -Target E:\     # once per disk: marks it (drive letters change)
.\install-image-backup.ps1               # once: nightly task at 02:30 (-WhatIf to preview)
.\image-backup.ps1                       # what the task runs; safe to run by hand
.
estore-image-backup.ps1 -Verify       # monthly check (reads only)
.
estore-image-backup.ps1               # put the images back (disk failure, new PC)
```

Only images new since the last run are copied, as the original DICOM files, and nothing
is ever deleted from the disk. The EMR status screen warns when the disk is missing, full,
or the backup has not succeeded recently. Details: the EMR wiki, `modules/pacs.md` 6.2.

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
  and does not distribute it.

Companion to **[Bethesda EMR](https://github.com/BethesdaHaneulNa/Bethesda-EMR)**.
Built with Claude (vibe coding).
