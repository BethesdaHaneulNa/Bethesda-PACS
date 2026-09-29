# one-off: upload 5 CR images into the Chest PA study (order 35) to test multi-image display
import io, os, requests
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian, SecondaryCaptureImageStorage

# Run inside the bridge container, which has ORTHANC_PASSWORD in its environment:
#   docker exec -i -e STUDY_UID=... -e ACCESSION=... -e PATIENT_ID=... bethesda-worklist-bridge python - < make_chest5.py
# Take STUDY_UID / ACCESSION / PATIENT_ID (chart number) from a test order in the
# EMR feed, or the image lands on no order (or shows the patient-number warning).
STUDY_UID = os.environ.get("STUDY_UID", "1.2.826.0.1.3680043.20260627.35.7807")
ACCESSION = os.environ.get("ACCESSION", "260627-35")
PATIENT_ID = os.environ.get("PATIENT_ID", "PX-TEST-0001")
ORTHANC = os.environ.get("ORTHANC_URL", "http://orthanc:8042") + "/instances"
AUTH = ("admin", os.environ["ORTHANC_PASSWORD"])
R = C = 256


def pixels(i):
    base = 25 + i * 15
    cx = 45 + (i - 1) * 42
    px = bytearray(R * C)
    for y in range(R):
        for x in range(C):
            d = (x - cx) ** 2 + (y - 128) ** 2
            px[y * C + x] = 235 if d < 32 * 32 else (base + ((x + y) % 30)) & 0xFF
    return bytes(px)


for i in range(1, 6):
    fm = Dataset()
    fm.MediaStorageSOPClassUID = SecondaryCaptureImageStorage
    fm.MediaStorageSOPInstanceUID = generate_uid()
    fm.TransferSyntaxUID = ExplicitVRLittleEndian

    ds = FileDataset("c.dcm", {}, file_meta=fm, preamble=b"\0" * 128)
    ds.SpecificCharacterSet = "ISO_IR 192"
    ds.PatientName = "TEST^Patient"
    ds.PatientID = PATIENT_ID
    ds.PatientBirthDate = "19800101"
    ds.PatientSex = "O"
    ds.AccessionNumber = ACCESSION
    ds.Modality = "CR"
    ds.StudyDescription = "Chest PA"
    ds.SeriesDescription = "Chest PA view %d" % i
    ds.StudyInstanceUID = STUDY_UID
    ds.SeriesInstanceUID = generate_uid()
    ds.SeriesNumber = i
    ds.InstanceNumber = 1
    ds.SOPClassUID = SecondaryCaptureImageStorage
    ds.SOPInstanceUID = fm.MediaStorageSOPInstanceUID
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = R
    ds.Columns = C
    ds.BitsAllocated = 8
    ds.BitsStored = 8
    ds.HighBit = 7
    ds.PixelRepresentation = 0
    ds.PixelData = pixels(i)
    ds.is_little_endian = True
    ds.is_implicit_VR = False

    buf = io.BytesIO()
    ds.save_as(buf, write_like_original=False)
    resp = requests.post(ORTHANC, data=buf.getvalue(), auth=AUTH,
                         headers={"Content-Type": "application/dicom"}, timeout=15)
    print("image %d -> %s" % (i, resp.status_code))
