# one-off: create a real US DICOM with a fixed StudyInstanceUID and upload to Orthanc
# (simulates a device acquiring an image for an MWL order)
import io, requests
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian, SecondaryCaptureImageStorage

STUDY_UID = "1.2.826.0.1.3680043.20260625.13.4696"   # = worklist study_instance_uid for order 13
ACCESSION = "260627-13"
ORTHANC = "http://orthanc:8042/instances"
AUTH = ("admin", "medconnectpacs")

ROWS, COLS = 256, 256
# simple grayscale pattern with a brighter disc (no numpy)
px = bytearray(ROWS * COLS)
cy, cx, r2 = 128, 128, 70 * 70
for y in range(ROWS):
    for x in range(COLS):
        d = (x - cx) ** 2 + (y - cy) ** 2
        px[y * COLS + x] = 200 if d < r2 else (40 + ((x + y) % 40))

fm = Dataset()
fm.MediaStorageSOPClassUID = SecondaryCaptureImageStorage
fm.MediaStorageSOPInstanceUID = generate_uid()
fm.TransferSyntaxUID = ExplicitVRLittleEndian

ds = FileDataset("img.dcm", {}, file_meta=fm, preamble=b"\0" * 128)
ds.SpecificCharacterSet = "ISO_IR 192"
ds.PatientName = "Haneul^Na"
ds.PatientID = "26-00001"
ds.PatientBirthDate = "19960910"
ds.PatientSex = "M"
ds.AccessionNumber = ACCESSION
ds.Modality = "US"
ds.StudyDescription = "Renal Ultrasound"
ds.SeriesDescription = "US"
ds.StudyInstanceUID = STUDY_UID
ds.SeriesInstanceUID = generate_uid()
ds.SOPClassUID = SecondaryCaptureImageStorage
ds.SOPInstanceUID = fm.MediaStorageSOPInstanceUID
ds.SamplesPerPixel = 1
ds.PhotometricInterpretation = "MONOCHROME2"
ds.Rows = ROWS
ds.Columns = COLS
ds.BitsAllocated = 8
ds.BitsStored = 8
ds.HighBit = 7
ds.PixelRepresentation = 0
ds.PixelData = bytes(px)
ds.is_little_endian = True
ds.is_implicit_VR = False

buf = io.BytesIO()
ds.save_as(buf, write_like_original=False)
resp = requests.post(ORTHANC, data=buf.getvalue(), auth=AUTH,
                     headers={"Content-Type": "application/dicom"}, timeout=15)
print("upload status:", resp.status_code, resp.text[:200])
