#!/usr/bin/env python3
"""
Bethesda worklist bridge.
Polls the EMR order-feed (Settings -> Order Feed: /api/pacs/worklist-feed) and
writes Orthanc worklist (.wl) files so imaging devices can pull patient/order
info via DICOM Modality Worklist.

EMR (orders) --HTTP--> this bridge --.wl files--> Orthanc worklists --MWL--> device
"""
import os, re, time
import requests
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian

FEED_URL = os.environ.get("EMR_FEED_URL", "http://host.docker.internal:9080/api/pacs/worklist-feed")
TOKEN    = os.environ.get("BRIDGE_TOKEN", "")
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

# The token travels in a header, never the URL: the EMR logs every request line,
# and a token in the query string was being written there every 15 seconds.
# Every EMR release has accepted X-Bridge-Token on both endpoints.
AUTH = {"X-Bridge-Token": TOKEN}

# The EMR refuses a short token or the old placeholder, whatever the two sides
# agree on, because the placeholder is published in this repository.
PLACEHOLDER_TOKENS = ("change-me-bridge-token",)
MIN_TOKEN_LENGTH = 16

# Orthanc, to see whether a scheduled study has actually been taken. Without
# this an entry stayed on the device all day after the patient had gone, next to
# the ones still waiting -- more rows to pick the wrong patient from -- and the
# EMR could not tell "no images yet" from "images are here". Same compose
# network, so the service name resolves; no password means the check is off.
ORTHANC_URL      = os.environ.get("ORTHANC_URL", "http://orthanc:8042").rstrip("/")
ORTHANC_USER     = os.environ.get("ORTHANC_USER", "admin")
ORTHANC_PASSWORD = os.environ.get("ORTHANC_PASSWORD", "")
ARRIVED_URL      = FEED_URL.replace("/worklist-feed", "/study-arrived")

# An EMR from before /study-arrived answers 404. Stop asking until restart
# rather than log the same line every cycle.
arrival_unsupported = False

# Why the last arrival check could not be done, or "" when it could. Sent with
# every heartbeat as `arrivals_error`: the worklist keeps syncing when Orthanc
# cannot be asked, so without this the EMR's status screen stays green while
# finished patients quietly stop leaving the device worklist.
arrivals_error = ""


def scrub(text):
    """Error text is sent to the EMR and shown on a status screen, so no secret
    may ride along: credentials written into a URL, or the token and password
    themselves should an exception ever quote them."""
    text = re.sub(r"//[^/@\s]+@", "//***@", str(text))
    for secret in (TOKEN, ORTHANC_PASSWORD):
        if secret:
            text = text.replace(secret, "***")
    return text


def report(ok, synced=0, failed=0, error=""):
    try:
        with open(HEARTBEAT_FILE, "w") as f:
            f.write(str(int(time.time())))
    except Exception as ex:
        print("bridge: could not write heartbeat file:", ex, flush=True)
    try:
        requests.post(HEARTBEAT_URL, timeout=5, headers=AUTH, json={
            "ok": bool(ok),
            "synced": synced,
            "failed": failed,
            "error": scrub(error)[:500],
            "poll_seconds": POLL,
            "arrivals_error": scrub(arrivals_error)[:300],
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


def find_stable_study(uid):
    """The Orthanc study with this StudyInstanceUID once it has stopped growing,
    else None. "Stable" is Orthanc's own call (no new instance for StableAge,
    60 s by default): reporting on the first image would take the entry off the
    worklist while a multi-image exam is still being sent."""
    auth = (ORTHANC_USER, ORTHANC_PASSWORD)
    r = requests.post(ORTHANC_URL + "/tools/find", auth=auth, timeout=10,
                      json={"Level": "Study", "Query": {"StudyInstanceUID": uid}, "Expand": True})
    r.raise_for_status()
    found = r.json()
    if not found or not found[0].get("IsStable"):
        return None
    study = found[0]
    stats = requests.get(ORTHANC_URL + "/studies/%s/statistics" % study["ID"], auth=auth, timeout=10)
    stats.raise_for_status()
    study["_instances"] = int(stats.json().get("CountInstances", 0))
    return study


def report_arrivals(rows):
    """Tell the EMR about every scheduled study that is now in Orthanc. The EMR
    marks the entry completed, so the next feed leaves it out and its .wl file is
    swept. Failures here never stop the worklist itself from syncing."""
    global arrival_unsupported, arrivals_error
    if not ORTHANC_PASSWORD:
        arrivals_error = "ORTHANC_PASSWORD not set; finished studies stay on the worklist"
        return 0
    if arrival_unsupported:
        return 0
    arrivals_error = ""
    reported = 0
    for row in rows:
        uid = row.get("study_instance_uid")
        if not uid or not row.get("worklist_id"):
            continue
        try:
            study = find_stable_study(uid)
        except Exception as ex:
            # Orthanc down or the password wrong: every other row would fail
            # the same way, so say it once and try again next cycle.
            print("bridge: could not ask Orthanc about studies:", scrub(ex), flush=True)
            arrivals_error = "could not ask Orthanc: %s" % ex
            return reported
        if not study:
            continue
        tags = study.get("PatientMainDicomTags") or {}
        try:
            r = requests.post(ARRIVED_URL, headers=AUTH, timeout=10, json={
                "worklist_id": row["worklist_id"],
                "study_instance_uid": uid,
                "orthanc_study_id": study.get("ID", ""),
                "patient_id": tags.get("PatientID", ""),
                "patient_name": tags.get("PatientName", ""),
                "instances": study.get("_instances", 0),
            })
        except Exception as ex:
            print("bridge: could not report study %s: %s" % (row.get("accession_no"), scrub(ex)), flush=True)
            arrivals_error = "could not report a study to the EMR: %s" % ex
            return reported
        # The EMR's own catch-all answer for a route it does not have, as opposed
        # to the 404 /study-arrived gives for an entry that has since been deleted.
        if r.status_code == 404 and "API route not found" in r.text:
            arrival_unsupported = True
            arrivals_error = "EMR has no /study-arrived; update the EMR"
            print("bridge: this EMR has no /study-arrived yet -- update the EMR; "
                  "finished studies will stay on the worklist until then.", flush=True)
            return reported
        if r.ok:
            reported += 1
            check = (r.json() or {}).get("patient_check", "")
            print("bridge: study arrived for %s (%s instances, patient %s)"
                  % (row.get("accession_no"), study.get("_instances"), check), flush=True)
        else:
            print("bridge: EMR refused study report for %s: %s %s"
                  % (row.get("accession_no"), r.status_code, r.text[:200]), flush=True)
    return reported


def sync():
    r = requests.get(FEED_URL, params={"format": "json"}, headers=AUTH, timeout=10)
    if r.status_code == 401:
        # Say which side to fix: a bare "401 Unauthorized" is what someone on site
        # would otherwise be reading down the phone.
        try:
            why = r.json().get("error", "")
        except Exception:
            why = ""
        raise RuntimeError("EMR refused the bridge token (%s). BRIDGE_TOKEN in this PACS's .env "
                           "must equal EMR Settings -> Order Feed -> Bridge Token." % (why or "401"))
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

    report_arrivals(rows)
    return len(current) - failed, failed


def main():
    os.makedirs(WL_DIR, exist_ok=True)
    print("worklist-bridge: feed=%s poll=%ss dir=%s" % (scrub(FEED_URL), POLL, WL_DIR), flush=True)
    if len(TOKEN) < MIN_TOKEN_LENGTH or TOKEN in PLACEHOLDER_TOKENS:
        # Keep running rather than exit: a restart loop would hide this line, and
        # the heartbeat file still tells the healthcheck the process is alive.
        print("worklist-bridge: BRIDGE_TOKEN is missing or a placeholder -- the EMR will refuse it. "
              "Run setup (it writes a random one into .env) and paste it into the EMR.", flush=True)
    if not ORTHANC_PASSWORD:
        print("worklist-bridge: ORTHANC_PASSWORD not set -- finished studies will not be "
              "taken off the worklist.", flush=True)
    while True:
        try:
            n, failed = sync()
            msg = "synced %d worklist entr%s" % (n, "y" if n == 1 else "ies")
            if failed:
                msg += " (%d skipped -- see errors above)" % failed
            print(msg, flush=True)
            report(True, synced=n, failed=failed)
        except Exception as ex:
            print("bridge error:", scrub(ex), flush=True)
            report(False, error=ex)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
