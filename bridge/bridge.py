#!/usr/bin/env python3
"""
Bethesda worklist bridge.
Polls the EMR order-feed (Settings -> Order Feed: /api/pacs/worklist-feed) and
writes Orthanc worklist (.wl) files so imaging devices can pull patient/order
info via DICOM Modality Worklist.

EMR (orders) --HTTP--> this bridge --.wl files--> Orthanc worklists --MWL--> device
"""
import os, time
import requests
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian

FEED_URL = os.environ.get("EMR_FEED_URL", "http://host.docker.internal:8080/api/pacs/worklist-feed")
TOKEN    = os.environ.get("BRIDGE_TOKEN", "change-me-bridge-token")
WL_DIR   = os.environ.get("WL_DIR", "/worklists")
POLL     = int(os.environ.get("POLL_SECONDS", "15"))

MWL_SOP_CLASS = "1.2.840.10008.5.1.4.31"  # Modality Worklist Information Model - FIND

# Where we say "still here" after every cycle.
#  - the file is read by the container healthcheck and keeps working when the
#    EMR is unreachable, which is precisely when we most want to know whether
#    this process is alive or wedged;
#  - the POST puts the same news on the EMR's own screen, because a clinic in
#    Madagascar is not going to be reading container logs.
# Neither is allowed to interrupt the sync loop.
HEARTBEAT_URL  = FEED_URL.replace("/worklist-feed", "/bridge-heartbeat")
HEARTBEAT_FILE = os.path.join(WL_DIR, ".heartbeat")


def report(ok, synced=0, failed=0, error=""):
    try:
        with open(HEARTBEAT_FILE, "w") as f:
            f.write(str(int(time.time())))
    except Exception as ex:
        print("bridge: could not write heartbeat file:", ex, flush=True)
    try:
        requests.post(HEARTBEAT_URL, timeout=5, json={
            "token": TOKEN,
            "ok": bool(ok),
            "synced": synced,
            "failed": failed,
            "error": str(error)[:500],
            "poll_seconds": POLL,
        })
    except Exception:
        # The EMR being down is already its own alarm; do not add noise here.
        pass


def safe(name):
    return "".join(c for c in str(name) if c.isalnum() or c in "-_.")


def write_wl(row, path):
    fm = Dataset()
    fm.MediaStorageSOPClassUID = MWL_SOP_CLASS
    fm.MediaStorageSOPInstanceUID = generate_uid()
    fm.TransferSyntaxUID = ExplicitVRLittleEndian

    ds = FileDataset(path, {}, file_meta=fm, preamble=b"\0" * 128)
    ds.SpecificCharacterSet = "ISO_IR 192"  # UTF-8
    ds.PatientName = row.get("dicom_patient_name", "") or ""
    ds.PatientID = row.get("patient_id", "") or ""           # = chart number
    ds.PatientBirthDate = row.get("birth_date", "") or ""
    ds.PatientSex = row.get("sex", "") or ""
    ds.AccessionNumber = row.get("accession_no", "") or ""
    ds.StudyInstanceUID = row.get("study_instance_uid") or generate_uid()
    ds.RequestedProcedureDescription = row.get("procedure_name", "") or ""
    ds.RequestedProcedureID = row.get("accession_no", "") or ""

    sps = Dataset()
    sps.Modality = row.get("modality", "") or ""
    sps.ScheduledStationAETitle = row.get("station_ae") or "ANY"
    sps.ScheduledProcedureStepStartDate = row.get("scheduled_date", "") or ""
    sps.ScheduledProcedureStepStartTime = (row.get("scheduled_time", "") or "")[:6]
    sps.ScheduledProcedureStepDescription = row.get("procedure_name", "") or ""
    sps.ScheduledProcedureStepID = row.get("accession_no", "") or ""
    ds.ScheduledProcedureStepSequence = [sps]

    ds.is_little_endian = True
    ds.is_implicit_VR = False
    # Write beside the target and rename into place. Orthanc scans this directory
    # on its own schedule, so saving straight to `path` lets it pick up a file
    # that is still half written; os.replace is atomic on the same filesystem.
    tmp = path + ".tmp"
    ds.save_as(tmp, write_like_original=False)
    os.replace(tmp, path)


def sync():
    r = requests.get(FEED_URL, params={"token": TOKEN, "format": "json"}, timeout=10)
    r.raise_for_status()
    data = r.json()
    rows = data.get("rows", []) if isinstance(data, dict) else (data or [])

    current = set()
    failed = 0
    for row in rows:
        key = safe(row.get("accession_no") or row.get("study_instance_uid") or "")
        if not key:
            continue
        # Claim the name before attempting the write, so that a row we cannot
        # convert does not also get its last good worklist file swept below.
        current.add(key)
        try:
            write_wl(row, os.path.join(WL_DIR, key + ".wl"))
        except Exception as ex:
            # One unconvertible order used to abort the whole cycle, which meant
            # every patient after it in the list silently lost their worklist
            # entry -- and the next cycle failed in the same place, forever.
            failed += 1
            print("bridge: skipped order %s: %s" % (key, ex), flush=True)

    # drop worklist files no longer scheduled (completed / cancelled / past day)
    for f in os.listdir(WL_DIR):
        if f.endswith(".wl") and f[:-3] not in current:
            os.remove(os.path.join(WL_DIR, f))
    return len(current) - failed, failed


def main():
    os.makedirs(WL_DIR, exist_ok=True)
    print("worklist-bridge: feed=%s poll=%ss dir=%s" % (FEED_URL, POLL, WL_DIR), flush=True)
    while True:
        try:
            n, failed = sync()
            msg = "synced %d worklist entr%s" % (n, "y" if n == 1 else "ies")
            if failed:
                msg += " (%d skipped -- see errors above)" % failed
            print(msg, flush=True)
            report(True, synced=n, failed=failed)
        except Exception as ex:
            print("bridge error:", ex, flush=True)
            report(False, error=ex)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
