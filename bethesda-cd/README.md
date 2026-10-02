# Bethesda CD

A small Windows program for a clinic that runs the **Bethesda EMR**: it copies a patient's
imaging exams to a CD - or to a disc image, or to a folder on a USB stick - for the patient
to take to another hospital. Every disc it makes carries a small viewer, **VIEWER.EXE**, so
that the images can be looked at on a PC that has no imaging software.

It also works the other way: a CD or a USB stick **another hospital gave the patient** is
read, and its images are sent into the patient's chart in the EMR.

Free, non-profit, made for Bethesda Hospital (Madagascar). French first; Korean and English
for the people who install and support it.

```
Bethesda-CD.exe    sign in with an EMR account -> chart number -> tick the exams ->
                   "Graver ce CD…" / "Enregistrer en fichier ISO…" / "Enregistrer dans un dossier…"
                   or: "Importer un CD / une clé USB" -> choose the disc -> tick its exams ->
                   "is this the same patient?" -> the images go into the chart

the disc           DICOMDIR      the standard index            \  made by the clinic's image
                   IMAGES\       the original DICOM files      /  server, handed on untouched
                   README.TXT    whose images, which exams, how to read the disc (French, English)
                   VIEWER.EXE    the viewer - double-click
                   AUTORUN.INF   on a CD: Windows offers to start the viewer (it never starts by itself)
```

## What it needs

- **Windows 10 (1903 or later) or Windows 11.** Nothing is installed: the program runs on the
  .NET Framework 4.8 that ships with Windows, draws its window with Windows' own toolkit and
  burns with Windows' own burning component (IMAPI2). It changes no system setting.
- **A Bethesda EMR it can reach over the network** - version **1.5.0 or later** to copy out;
  bringing in needs an EMR that has the import calls (an older one is told apart, and the
  program says so). The program talks to the EMR only, over these calls:

  | call | what for |
  |---|---|
  | `POST /api/auth/login` | sign in (Consultation or Payment to copy out; those, or Registration, to bring in) |
  | `GET /api/pacs/export/patient?chart_no=` | the patient and the imaging exams, each with its size or the reason it cannot be copied |
  | `GET /api/pacs/export/bundle?order_item_ids=&medium=` | the chosen exams as one ZIP: `DICOMDIR` + `IMAGES/` |
  | `GET /api/pacs/import/patient?chart_no=` | bringing in: the patient, the limits (largest file, free room), what was brought in before |
  | `POST /api/pacs/import/check` | what the EMR knows of the disc's exams: can be brought in, here already, another patient's… |
  | `POST /api/pacs/import/begin` · `PUT …/{id}/instance` · `POST …/{id}/finish` · `POST …/{id}/cancel` | one exam: announced, sent file by file (each DICOM file as it is), put in the chart - or taken back |

  It never talks to the image server (Orthanc) and does not have its password. The EMR checks
  the account, refuses exams that must not leave (cancelled, identity warning, no images) and
  writes one line in its change log for every copy - no line, no copy.
- A disc burner is optional: without one, "save as ISO file" and "save to a folder" still work.

## Putting it on a PC

On the server PC the PACS setup makes a "Bethesda CD" shortcut on the desktop by itself. On
any other PC (a reception desk - no Docker needed there) copy the folder with
`Bethesda-CD.exe`, `install.bat` and `install.ps1` to it, on a USB stick for instance, and
double-click **`install.bat`**: it copies the program to this user's programs folder, asks for
the address of the EMR once, and puts **Bethesda CD** on the desktop.

```powershell
.\install.ps1 -EmrUrl http://192.168.1.10:9080     # the same, without the question
.\install.ps1 -Here                                # no copy: a shortcut to the program where it is
```

It copies one file, writes `Bethesda-CD.ini` when there is none, and makes or corrects one
shortcut - no registry key, no scheduled task. To remove it: delete the shortcut and the folder.

## Using it

Double-click `Bethesda-CD.exe`. The first time, type the address of the EMR
(`http://<server>:9080`); it is remembered in `Bethesda-CD.ini` beside the program, together
with the last folder used and the language - never a password (see
`Bethesda-CD.example.ini`).

- Only a **blank** disc is ever written; a disc that holds something is never erased.
- The disc is burnt at the slowest speed the drive offers, closed, read back and compared file
  by file with what was meant to be written.
- What is fetched is kept under `%TEMP%\BethesdaCD` while the copy is made and removed
  afterwards - also after a failure, and at the next start if the PC lost power.
- A folder or an ISO saved by the program holds a patient's images, unencrypted: delete it
  when it is no longer needed.
- `Bethesda-CD.exe -Lang ko` (or `en`) for one run; `lang=ko` in the `.ini` to keep it.

### Bringing in a CD or a USB stick from another hospital

"Importer un CD / une clé USB" at the top of the window. An account of the registration desk
sees only this way; an account that may also copy out sees both.

1. Type the chart number of the patient who will receive the images.
2. "Choisir le disque ou le dossier…": the CD, or the folder of the USB stick. The program
   lists the exams it finds - date, type, name, number of images, size, the hospital, and
   whose the disc says they are. An exam the EMR already has, or that cannot be taken (a
   file over the limit…), is grey and says why.
3. Tick the exams, then "Importer…". A window shows **what the disc says of the patient
   beside what the chart says**; a day of birth or a sex that differs is red, and the person
   must tick "all the same, these images are this patient's" to go on. The name is shown,
   never judged.
4. The files are sent one by one, with a count; "Annuler" gives the exam up, and the EMR
   takes back what it had received. At the end the exams are in the EMR (Imagerie → Imagerie
   externe).

- **Only DICOM files are read**, and only their headers until they are sent. With a
  `DICOMDIR` on the disc, the files it lists are the only ones touched. Without one the folder
  is walked, and a program, a library or a document (the other maker's viewer, its DLLs,
  `AUTORUN.INF`, pictures, notes) is **not opened at all**. Nothing on the disc is ever run.
- **The files are sent as they are** - the program changes nothing in them and writes nothing
  to the disc or to this PC. It is the EMR that files them under the patient's own number.
- The limits come from the EMR (the largest file it takes, the room left on the image
  server, the size above which it warns). The program asks them; it has none of its own.
- One patient of the disc at a time: a disc that holds two patients says so.
- A cut connection is tried again (sending the same file twice is safe); a file the disc no
  longer gives (a scratch, the stick pulled out) stops the exam, which is taken back.

## The viewer, VIEWER.EXE

About 80 KB, started by a double-click on the disc; it installs nothing and leaves nothing on
the PC that runs it. The exams and series of the disc on the left, the image on the right.

| | |
|---|---|
| left button + drag | brightness (up / down) and contrast (left / right) - grey and colour images; also the two small sliders |
| wheel | previous / next image (in a file of several frames: frame by frame) |
| Ctrl + wheel | zoom |
| right button + drag | move the image |
| double-click | fit to the window |
| ← → · ↑ ↓ · I · R | image · series · invert · reset |

It always shows: **"Visionneuse de consultation — non destinée au diagnostic"** (for
reference - not for diagnosis).

### AUTORUN.INF

A disc that carries the viewer also carries a four-line `AUTORUN.INF` (`open=VIEWER.EXE`, the
viewer's icon, and one line of words: "Voir les images / View the images").

- **On a CD or DVD** Windows shows the disc with the viewer's icon, and "Voir les images /
  View the images" becomes what a double-click on the disc does - it starts `VIEWER.EXE`.
  "Open" in the right-click menu still shows the files. When the disc is put in, Windows'
  AutoPlay notice can offer the same.
- **Nothing starts by itself.** Windows asks first. Where AutoPlay is switched off, or the
  rules of a hospital's PCs forbid it, nothing is offered: the viewer is then started by a
  double-click on `VIEWER.EXE`, as `README.TXT` says.
- **On a USB stick, or in a folder, Windows ignores the file** (it has since Windows 7).
  There too: double-click `VIEWER.EXE`.
- A disc on which the viewer could not be put gets no `AUTORUN.INF`.

Checked on Windows 11 with a disc image in a virtual drive: the drive took the viewer's icon;
its menu began with the line of words; nothing was started when the disc appeared; the disc's
default action (what a double-click does) started `VIEWER.EXE` from the disc, which showed
the disc's images; Microsoft Defender found nothing in the disc or in the image. Not checked:
a burnt disc in a real drive, the AutoPlay notice itself, other antivirus programs.

What it reads: uncompressed images, **lossless JPEG** (decoded by the viewer itself, exactly -
this is what the clinic's ultrasound machine sends), baseline JPEG of 8 bits (by the decoder
that is part of Windows) and RLE. Anything else (JPEG 2000, JPEG-LS, 12-bit lossy JPEG) does
not reach the disc compressed: when a chosen exam holds such an image the EMR has the image
server unpack that copy, losslessly, and the program says so. There is no playback of clips.

## Building it

```powershell
.\build.ps1          # -> build\Bethesda-CD.exe  (VIEWER.EXE is inside it)
```

Only what Windows already has is used: the C# compiler of the .NET Framework (`csc.exe`, C# 5).
Nothing is installed or downloaded. The icon is `icon/Bethesda-CD.ico` - the project's own mark for
this program (a disc with a cross; drawn for the Bethesda EMR, PACS and CD together - the SVG
sources and how the .ico files are made are in the EMR's wiki). `-IconFile x.ico` builds with
another; without any icon file one is drawn on the spot by `icon/make-icon.ps1`. The viewer is
built first and carried inside `Bethesda-CD.exe` as a resource, so every disc gets the very
same `VIEWER.EXE`; the viewer's reading of a disc (`src\viewer\Dicom.cs`, `Disc.cs`) is also
compiled into the program, which reads another hospital's disc with it. The version is written in one place, `src\shared\Version.cs`.

```
src\app\        the program:  Program · MainForm · Texts · Emr · DiscFolder · Burner · ImportDisc · ImportConfirm
src\viewer\     the viewer:   Program · MainForm · ImagePanel · Disc · Dicom · Picture · Jpeg · Rle · Texts
src\shared\     Version.cs
icon\           make-icon.ps1
install.ps1     install.bat - the program and a desktop shortcut on a PC
tests\          viewer_test.ps1 · disc_test.ps1 · import_test.ps1 · app_test.ps1 · import_real_test.ps1
                (fake_dicom.ps1: the made-up DICOM files the two import tests write;
                 quiet_window.ps1: the tests' windows are shown off the screen)
```

The program is not signed. Built on the PC that runs it, or brought on a USB stick, Windows
starts it without a question; a copy downloaded from the internet carries Windows' "from the
internet" mark and SmartScreen asks once ("More info" -> "Run anyway").

## Tests

```powershell
.\tests\viewer_test.ps1      # needs nothing: draws its own pictures, encodes them, checks the viewer
.\tests\disc_test.ps1 -Mount  # needs nothing: the viewer, AUTORUN.INF and README.TXT on a disc folder, a folder copy, a disc image
.\tests\import_test.ps1       # needs nothing: a made-up disc and a stand-in for the EMR on this PC - bringing in, start to end
.\tests\app_test.ps1 -Emr http://127.0.0.1:9188 -Login someone -Chart 26-00001 -ExamIds 55,56 -Base D:\empty\folder
.\tests\import_real_test.ps1 -Emr http://127.0.0.1:9188 -Login someone -Chart 26-00001
```

`viewer_test.ps1` writes made-up pictures as DICOM in every form the viewer reads (RLE and
lossless JPEG with each of the seven predictors, by encoders that exist only in the test) and
checks that every value comes back as it went in; then it drives the viewer's window.
`disc_test.ps1` puts the viewer, `AUTORUN.INF` and `README.TXT` into a disc folder without
the EMR, saves it to a folder and to a disc image and - with `-Mount` - puts the image in a
Windows virtual drive, reads every file back and takes it out again.
`import_test.ps1` writes a made-up "other hospital's disc" (DICOM files, and a viewer, a
library and other files that must not be opened), starts a stand-in for the EMR on
127.0.0.1 that answers the import calls as the EMR's document says, and drives the window:
who may do what, the list, the patient question, the files sent byte for byte, a refusal, a
cut connection, a cancel, the limits, a disc of two patients, a file that can no longer be
read. What the real EMR does with the files is not its business - that is checked against a
test EMR.
`app_test.ps1` drives the built program against a **test** installation of the EMR (never the
one the clinic works on): sign-in, the list, a copy to a folder, a disc image, the refusals.
It burns nothing. The test account's password is taken from the environment variable
`BETHESDA_CD_TEST_PASSWORD`.
`import_real_test.ps1` brings a made-up exam of three small images into a chart of a **test**
EMR that has its image server (same password variable): the exam really goes in and the EMR
lists it, the same exam is refused a second time, a second exam is stopped half-way and the
EMR is seen to have taken it back. It leaves that one made-up exam in the test EMR and says
which; on the PC it leaves nothing. `-RealDisc D:\a\disc` also brings in the exams of a disc
folder the test did not make (they stay in the test EMR too); `-OverLimit` sends one file
larger than the EMR allows, to see the refusal.

The tests that drive a window show it far off the screen, out of the taskbar and without
taking the keyboard: someone may be working at the PC.

## License

See `LICENSE` - non-profit, source-available, no redistribution, no warranty.
