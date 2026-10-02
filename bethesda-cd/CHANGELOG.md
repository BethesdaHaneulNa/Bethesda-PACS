# Changelog - Bethesda CD

## 1.0.0

The first version as a program of its own (before, it was a set of PowerShell scripts in the
Bethesda PACS repository, started by `cd-export.bat`).

- **Bethesda-CD.exe**: sign in with an EMR account, look a patient up by chart number, tick
  exams, see their size and whether they fit the blank disc in the drive; burn (slowest speed,
  closed disc, read back and compared), or save a disc image, or a folder. French, Korean,
  English. Talks to the EMR only; needs Bethesda EMR 1.5.0 or later.
- **VIEWER.EXE** on every disc: the exams and series of the disc, grey and colour images,
  brightness / contrast / zoom / pan / invert, frame by frame through a file of several
  frames. Reads uncompressed images, lossless JPEG (decoded by the viewer itself), baseline
  JPEG of 8 bits and RLE. "For reference - not for diagnosis."
- The viewer is built once and carried inside the program: every disc gets the same file.
- **AUTORUN.INF** on every disc that carries the viewer: on a CD, Windows shows the disc with
  the viewer's icon and offers to start the viewer. Nothing starts by itself; on a USB stick
  Windows ignores the file.
- Built with the C# compiler that ships with Windows; nothing is installed.
- Not yet: bringing another hospital's disc INTO the EMR (planned).
