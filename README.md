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

---

## How it works

```
   ┌─────────────┐   imaging orders (JSON feed)   ┌──────────────────┐
   │  Bethesda   │ ─────────────────────────────► │ worklist-bridge  │  (our code)
   │  EMR :8080  │   /api/pacs/worklist-feed       │  polls every 15s │
   └─────┬───────┘                                 └────────┬─────────┘
         │  viewer (iframe)                                  │ writes .wl files
         │                                                   ▼
         │                                          ┌──────────────────┐
         └────────────────── view images ──────────►│  Orthanc :8090   │  (official image)
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
5. In the EMR, clicking the imaging order opens the image in the **viewer**, and the doctor can
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

1. In the EMR, open **Settings → Order Feed**.
2. Set **Bridge Token** to the value the setup script printed (so the two trust each other).
3. Set **PACS web / viewer URL** to `http://<this-host-ip>:8090` so the EMR can show images.

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
**Accession Number / Study UID**, which the bridge sets — not by the AE Title.

> The Called AE Title default is `MEDCONNECT` (an internal identifier kept in sync with the EMR).
> You can change `ORTHANC__DICOM_AET` in `docker-compose.yml`, but then set the device's Called AE
> to match.

## Ports

| Port | Purpose | Who needs it |
|------|---------|--------------|
| 8090 | Orthanc web UI / viewer / REST / DICOMweb | clinic computers + the EMR host |
| 4242 | DICOM (worklist query + image store) | imaging devices |

Keep these on the clinic LAN — **do not expose them to the internet.** Orthanc holds patient
images (PII).

## Test tools (optional)

`bridge/` includes small scripts to test your setup **without a real device**:
`make_demo.py` / `make_chest5.py` (generate fake DICOM images), `storetest.py` (send a test
image, C-STORE), `q_test.py` (query the worklist, C-FIND). Handy for verifying everything works
before connecting real equipment.

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

Note: the **PACS web/viewer URL stays `http://localhost:8090`** — that one is opened by your
*browser* (where `localhost` = your PC), so it's correct as-is. The two fields legitimately take
different values.

Also: this DICOM test is only a convenience check. The imaging integration actually works through
the **bridge token** (worklist feed) and the **viewer URL**, so a red ✗ here does **not** stop the
worklist or image viewing from working.

> 한국어 — 연결 테스트가 빨간 ✗ 뜨면: Host/IP를 `localhost` 대신 **`host.docker.internal`**
> (또는 이 PC의 **LAN IP**)로 바꾸세요. 컨테이너 안에서 `localhost`는 PC가 아니라 컨테이너
> 자기 자신을 가리켜서 그래요. **뷰어 주소(`localhost:8090`)는 브라우저가 여는 거라 그대로** 두면
> 됩니다. 이 테스트는 확인용이라 ✗여도 워크리스트·뷰어 기능 자체는 동작해요.

---

## Security

- The Orthanc admin password is **randomly generated** by setup (in `.env`, git-ignored). Login: user `admin`.
- The bridge token is random and must match the EMR's setting.
- Keep ports `8090` / `4242` on the LAN only. Use a VPN for any remote access.

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
