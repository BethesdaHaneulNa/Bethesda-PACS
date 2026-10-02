# Copy a patient's exams to a CD (or a folder, or a disc image) - Windows.
#
# A separate program, as hospitals have beside their PACS (director, 2026-10-01): sign
# in with an EMR account, type the patient's chart number, tick the exams, see how large
# they are; with a blank disc in the drive, "burn this CD?" - burn, check, eject.
#
#   cd-export.bat                 double-click (French)
#   .\cd-export.ps1 -Lang ko      Korean (-Lang en: English)
#
# What is written:  DICOMDIR + IMAGES\ (a standard DICOM disc, made by the image server)
#                   + README.TXT (whose images, how to read the disc).
# Where:            the disc in the drive / an .iso file / a new folder (a USB stick).
#
# It talks to the EMR only - the EMR decides who may copy what (Consultation or Payment),
# refuses exams that must not leave (cancelled, identity warning) and writes one line in
# the change log per copy. The image server's password is not in this program.
# It can run on any PC that reaches the EMR; the EMR's address is asked once and kept in
# cd-export.ini beside the program (no secret is ever written there).
#
# Nothing is installed, no system setting is changed. Burning uses Windows' own burning
# component (IMAPI2). The images fetched are kept under %TEMP%\BethesdaCD while the copy
# is made and removed afterwards.
param(
  [ValidateSet('fr', 'ko', 'en')][string]$Lang = 'fr',
  [string]$ConfigPath = (Join-Path $PSScriptRoot 'cd-export.ini'),
  [string]$ViewerDir = (Join-Path $PSScriptRoot 'cd-viewer')   # kept for the clinic's own viewer; nothing is offered until it exists
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cd-export-common.ps1')
. (Join-Path $PSScriptRoot 'cd-export-ui.ps1')

try {
  [void](Remove-ExportTemp)                              # what an interrupted run left behind
  $form = New-CdxForm $Lang $ConfigPath $ViewerDir
  [void][Windows.Forms.Application]::Run($form)
} catch {
  # started without a console (cd-export.bat): a failure must still be seen
  [void][Windows.Forms.MessageBox]::Show(('cd-export: ' + $_.Exception.Message), 'Bethesda', 'OK', 'Error')
  exit 1
}
