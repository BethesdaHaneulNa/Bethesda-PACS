# Bethesda CD

A small Windows program for a clinic that runs the **Bethesda EMR**: it copies a patient's
imaging exams to a CD - or to a disc image, or to a folder on a USB stick - for the patient
to take to another hospital. Every disc it makes carries a small viewer, **VOIR.EXE**, so
that the images can be looked at on a PC that has no imaging software.

Free, non-profit, made for Bethesda Hospital (Madagascar). French first; Korean and English
for the people who install and support it.

```
Bethesda-CD.exe    sign in with an EMR account -> chart number -> tick the exams ->
                   "Graver ce CD…" / "Enregistrer en fichier ISO…" / "Enregistrer dans un dossier…"

the disc           DICOMDIR      the standard index            \  made by the clinic's image
                   IMAGES\       the original DICOM files      /  server, handed on untouched
                   README.TXT    whose images, which exams, how to read the disc (French, English)
                   VOIR.EXE      the viewer - double-click
```

## What it needs

- **Windows 10 (1903 or later) or Windows 11.** Nothing is installed: the program runs on the
  .NET Framework 4.8 that ships with Windows, draws its window with Windows' own toolkit and
  burns with Windows' own burning component (IMAPI2). It changes no system setting.
- **A Bethesda EMR it can reach over the network** - version **1.5.0 or later**. The program
  talks to the EMR only, over these calls:

  | call | what for |
  |---|---|
  | `POST /api/auth/login` | sign in (an account with the Consultation or the Payment permission) |
  | `GET /api/pacs/export/patient?chart_no=` | the patient and the imaging exams, each with its size or the reason it cannot be copied |
  | `GET /api/pacs/export/bundle?order_item_ids=&medium=` | the chosen exams as one ZIP: `DICOMDIR` + `IMAGES/` |

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

## The viewer, VOIR.EXE

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

What it reads: uncompressed images, **lossless JPEG** (decoded by the viewer itself, exactly -
this is what the clinic's ultrasound machine sends), baseline JPEG of 8 bits (by the decoder
that is part of Windows) and RLE. Anything else (JPEG 2000, JPEG-LS, 12-bit lossy JPEG) does
not reach the disc compressed: when a chosen exam holds such an image the EMR has the image
server unpack that copy, losslessly, and the program says so. There is no playback of clips.

## Building it

```powershell
.\build.ps1          # -> build\Bethesda-CD.exe  (VOIR.EXE is inside it)
```

Only what Windows already has is used: the C# compiler of the .NET Framework (`csc.exe`, C# 5).
Nothing is installed or downloaded. The icon is `icon\Bethesda-CD.ico` when that file is there (or
`-IconFile x.ico`); without one it is drawn on the spot by `icon\make-icon.ps1`. The viewer is
built first and carried inside `Bethesda-CD.exe` as a resource, so every disc gets the very
same `VOIR.EXE`. The version is written in one place, `src\shared\Version.cs`.

```
src\app\        the program:  Program · MainForm · Texts · Emr · DiscFolder · Burner
src\viewer\     the viewer:   Program · MainForm · ImagePanel · Disc · Dicom · Picture · Jpeg · Rle · Texts
src\shared\     Version.cs
icon\           make-icon.ps1
install.ps1     install.bat - the program and a desktop shortcut on a PC
tests\          viewer_test.ps1 · app_test.ps1
```

The program is not signed. Built on the PC that runs it, or brought on a USB stick, Windows
starts it without a question; a copy downloaded from the internet carries Windows' "from the
internet" mark and SmartScreen asks once ("More info" -> "Run anyway").

## Tests

```powershell
.\tests\viewer_test.ps1      # needs nothing: draws its own pictures, encodes them, checks the viewer
.\tests\app_test.ps1 -Emr http://127.0.0.1:9188 -Login someone -Chart 26-00001 -ExamIds 55,56 -Base D:\empty\folder
```

`viewer_test.ps1` writes made-up pictures as DICOM in every form the viewer reads (RLE and
lossless JPEG with each of the seven predictors, by encoders that exist only in the test) and
checks that every value comes back as it went in; then it drives the viewer's window.
`app_test.ps1` drives the built program against a **test** installation of the EMR (never the
one the clinic works on): sign-in, the list, a copy to a folder, a disc image, the refusals.
It burns nothing. The test account's password is taken from the environment variable
`BETHESDA_CD_TEST_PASSWORD`.

## License

See `LICENSE` - non-profit, source-available, no redistribution, no warranty.
