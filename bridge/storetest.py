# prove: an UNREGISTERED device (calling AE 'XRAY01') can C-STORE images to Orthanc
import io
from pynetdicom import AE
from pynetdicom.sop_class import SecondaryCaptureImageStorage
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian

R = C = 256
px = bytearray(R * C)
for y in range(R):
    for x in range(C):
        d = (x - 128) ** 2 + (y - 128) ** 2
        px[y * C + x] = 230 if d < 60 * 60 else 50 + ((x * y) % 40)

fm = Dataset()
fm.MediaStorageSOPClassUID = SecondaryCaptureImageStorage
fm.MediaStorageSOPInstanceUID = generate_uid()
fm.TransferSyntaxUID = ExplicitVRLittleEndian
ds = FileDataset("s.dcm", {}, file_meta=fm, preamble=b"\0" * 128)
ds.SpecificCharacterSet = "ISO_IR 192"
ds.PatientName = "Test^Device"
ds.PatientID = "DEVTEST01"
ds.Modality = "CR"
ds.StudyDescription = "C-STORE from unregistered AE"
ds.StudyInstanceUID = generate_uid()
ds.SeriesInstanceUID = generate_uid()
ds.SOPClassUID = SecondaryCaptureImageStorage
ds.SOPInstanceUID = fm.MediaStorageSOPInstanceUID
ds.SeriesNumber = 1
ds.InstanceNumber = 1
ds.SamplesPerPixel = 1
ds.PhotometricInterpretation = "MONOCHROME2"
ds.Rows = R; ds.Columns = C
ds.BitsAllocated = 8; ds.BitsStored = 8; ds.HighBit = 7; ds.PixelRepresentation = 0
ds.PixelData = bytes(px)
ds.is_little_endian = True
ds.is_implicit_VR = False

ae = AE(ae_title="XRAY01")  # <-- this AE was never registered in Orthanc
ae.add_requested_context(SecondaryCaptureImageStorage)
assoc = ae.associate("orthanc", 4242, ae_title="MEDCONNECT")
if assoc.is_established:
    st = assoc.send_c_store(ds)
    print("C-STORE status: 0x%04X (%s)" % (st.Status, "SUCCESS" if st.Status == 0 else "FAIL"))
    assoc.release()
else:
    print("ASSOCIATION REJECTED")
