# one-off: act as an imaging device, query Orthanc Modality Worklist (C-FIND)
from pynetdicom import AE
from pynetdicom.sop_class import ModalityWorklistInformationFind
from pydicom.dataset import Dataset

ae = AE(ae_title="TESTSCU")
ae.add_requested_context(ModalityWorklistInformationFind)

ds = Dataset()
ds.PatientName = ""
ds.PatientID = ""
ds.AccessionNumber = ""
ds.StudyInstanceUID = ""
sps = Dataset()
sps.Modality = ""
sps.ScheduledStationAETitle = ""
sps.ScheduledProcedureStepStartDate = ""
sps.ScheduledProcedureStepDescription = ""
ds.ScheduledProcedureStepSequence = [sps]

assoc = ae.associate("orthanc", 4242, ae_title="MEDCONNECT")
if assoc.is_established:
    n = 0
    for (status, ident) in assoc.send_c_find(ds, ModalityWorklistInformationFind):
        if ident is not None:
            n += 1
            mod = ident.ScheduledProcedureStepSequence[0].Modality if "ScheduledProcedureStepSequence" in ident else "?"
            print("WORKLIST:", ident.get("PatientID", ""), "|", str(ident.get("PatientName", "")), "|", mod, "|", ident.get("AccessionNumber", ""))
    print("TOTAL MWL RESULTS:", n)
    assoc.release()
else:
    print("ASSOCIATION FAILED")
