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
    ds.save_as(path, write_like_original=False)


def sync():
    r = requests.get(FEED_URL, params={"token": TOKEN, "format": "json"}, timeout=10)
    r.raise_for_status()
    data = r.json()
    rows = data.get("rows", []) if isinstance(data, dict) else (data or [])

    current = set()
    for row in rows:
        key = safe(row.get("accession_no") or row.get("study_instance_uid") or "")
        if not key:
            continue
        current.add(key)
        write_wl(row, os.path.join(WL_DIR, key + ".wl"))

    # drop worklist files no longer scheduled (completed / cancelled / past day)
    for f in os.listdir(WL_DIR):
        if f.endswith(".wl") and f[:-3] not in current:
            os.remove(os.path.join(WL_DIR, f))
    return len(current)


def main():
    os.makedirs(WL_DIR, exist_ok=True)
    print("worklist-bridge: feed=%s poll=%ss dir=%s" % (FEED_URL, POLL, WL_DIR), flush=True)
    while True:
        try:
            n = sync()
            print("synced %d worklist entr%s" % (n, "y" if n == 1 else "ies"), flush=True)
        except Exception as ex:
            print("bridge error:", ex, flush=True)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
