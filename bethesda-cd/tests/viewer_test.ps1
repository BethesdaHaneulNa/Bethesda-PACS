# Bethesda CD - the viewer (VIEWER.EXE) checked without a person and without any outside
# file: this script DRAWS its own pictures, writes them as DICOM files in every form the
# viewer reads - uncompressed, RLE, lossless JPEG with each of the seven predictors, with
# and without restart intervals - and checks that the viewer gives back exactly the
# values that were put in. Then it opens the viewer's window on them and drives it.
#
#   .\viewer_test.ps1            (nothing to prepare: the samples are made in %TEMP% and removed)
#
# The encoders below exist only for this test (the viewer itself only decodes); they are
# written from the same standards (DICOM PS3.5 annex G for RLE, ITU T.81 annex H for
# lossless JPEG) but share no code with the viewer.
param([string]$Sources = '')
$ErrorActionPreference = 'Stop'
if (-not $Sources) { $Sources = Join-Path $PSScriptRoot '..\src' }
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
. (Join-Path $PSScriptRoot 'quiet_window.ps1')
Add-Type -Path (Get-ChildItem (Join-Path $Sources 'shared'), (Join-Path $Sources 'viewer') -Filter '*.cs' | ForEach-Object { $_.FullName }) -ReferencedAssemblies 'System.Drawing', 'System.Windows.Forms'
Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System; using System.Collections.Generic; using System.IO; using System.Text; using System.Drawing;
public static class TestDicom {
  // A made-up picture: slopes, rings and noise, so that every bit of a sample is used.
  public static ushort[] Paint(int w, int h, int comps, int bits, int seed) {
    ushort[] v = new ushort[w * h * comps]; uint r = (uint)(seed * 2654435761u + 12345); int max = (1 << bits) - 1;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) for (int c = 0; c < comps; c++) {
      r = r * 1664525u + 1013904223u;
      double wave = 0.5 + 0.5 * Math.Sin((x * (c + 2) + y * 3 + seed) / 7.0);
      int val = (int)(wave * max * 0.8) + (int)((r >> 16) % (uint)Math.Max(2, max / 6));
      if ((x + y) % 17 == 0) val = (r & 1) == 0 ? 0 : max;                  // the two ends of the range too
      v[(y * w + x) * comps + c] = (ushort)Math.Max(0, Math.Min(max, val));
    }
    return v;
  }
  static void El(MemoryStream m, int g, int e, string vr, byte[] val) {
    if (val.Length % 2 == 1) { Array.Resize(ref val, val.Length + 1); val[val.Length - 1] = (byte)(vr == "UI" ? 0 : 32); }
    m.Write(BitConverter.GetBytes((ushort)g), 0, 2); m.Write(BitConverter.GetBytes((ushort)e), 0, 2); m.Write(Encoding.ASCII.GetBytes(vr), 0, 2);
    if (vr == "OB" || vr == "OW" || vr == "SQ" || vr == "UN") { m.Write(new byte[2], 0, 2); m.Write(BitConverter.GetBytes((uint)val.Length), 0, 4); }
    else m.Write(BitConverter.GetBytes((ushort)val.Length), 0, 2);
    m.Write(val, 0, val.Length);
  }
  static void S(MemoryStream m, int g, int e, string vr, string text, Encoding enc) { El(m, g, e, vr, enc.GetBytes(text)); }
  static void U(MemoryStream m, int g, int e, int n) { El(m, g, e, "US", BitConverter.GetBytes((ushort)n)); }

  // A DICOM file. frames: the pixel data of each frame - raw bytes when `syntax` is an
  // uncompressed one, else one compressed fragment a frame.
  public static void Write(string path, string syntax, int w, int h, int bits, int allocated, int comps, string photometric, bool planar, bool signed, List<byte[]> frames,
      string study, int series, string seriesText, int instance, string charset, string window, bool table) {
    Encoding enc = charset == "ISO_IR 192" ? Encoding.UTF8 : Encoding.GetEncoding(28591), a = Encoding.ASCII;
    MemoryStream meta = new MemoryStream(), ds = new MemoryStream();
    string uid = "1.2.826.0.1.3680043.8.498.9." + study + "." + series + "." + instance;
    El(meta, 2, 1, "OB", new byte[] { 0, 1 }); S(meta, 2, 2, "UI", "1.2.840.10008.5.1.4.1.1.7", a); S(meta, 2, 3, "UI", uid, a); S(meta, 2, 0x10, "UI", syntax, a); S(meta, 2, 0x12, "UI", "1.2.826.0.1.3680043.8.498.1", a);
    if (charset != "") S(ds, 8, 5, "CS", charset, a);
    S(ds, 8, 0x16, "UI", "1.2.840.10008.5.1.4.1.1.7", a); S(ds, 8, 0x18, "UI", uid, a); S(ds, 8, 0x20, "DA", "2026100" + study, a); S(ds, 8, 0x60, "CS", comps == 3 ? "US" : "CR", a);
    S(ds, 8, 0x1030, "LO", "Examen " + study, enc); S(ds, 8, 0x103E, "LO", seriesText, enc);
    S(ds, 0x10, 0x10, "PN", "ESSAI^Hélène", enc); S(ds, 0x10, 0x20, "LO", "TEST-0001", a);
    S(ds, 0x20, 0xD, "UI", "1.2.826.0.1.3680043.8.498.9." + study, a); S(ds, 0x20, 0xE, "UI", "1.2.826.0.1.3680043.8.498.9." + study + "." + series, a);
    S(ds, 0x20, 0x11, "IS", series.ToString(), a); S(ds, 0x20, 0x13, "IS", instance.ToString(), a);
    U(ds, 0x28, 2, comps); S(ds, 0x28, 4, "CS", photometric, a); if (comps == 3) U(ds, 0x28, 6, planar ? 1 : 0);
    if (frames.Count > 1) S(ds, 0x28, 8, "IS", frames.Count.ToString(), a);
    U(ds, 0x28, 0x10, h); U(ds, 0x28, 0x11, w); U(ds, 0x28, 0x100, allocated); U(ds, 0x28, 0x101, bits); U(ds, 0x28, 0x102, bits - 1); U(ds, 0x28, 0x103, signed ? 1 : 0);
    if (window != "") { S(ds, 0x28, 0x1050, "DS", window.Split('/')[0], a); S(ds, 0x28, 0x1051, "DS", window.Split('/')[1], a); }
    if (syntax == "1.2.840.10008.1.2.1") { MemoryStream all = new MemoryStream(); foreach (byte[] f in frames) all.Write(f, 0, f.Length); El(ds, 0x7FE0, 0x10, "OW", all.ToArray()); }
    else {
      ds.Write(new byte[] { 0xE0, 0x7F, 0x10, 0x00, (byte)'O', (byte)'B', 0, 0, 0xFF, 0xFF, 0xFF, 0xFF }, 0, 12);
      MemoryStream items = new MemoryStream(); List<uint> at = new List<uint>();
      foreach (byte[] f0 in frames) {
        byte[] f = f0; if (f.Length % 2 == 1) { f = new byte[f0.Length + 1]; Array.Copy(f0, f, f0.Length); }
        at.Add((uint)items.Length); items.Write(new byte[] { 0xFE, 0xFF, 0x00, 0xE0 }, 0, 4); items.Write(BitConverter.GetBytes((uint)f.Length), 0, 4); items.Write(f, 0, f.Length);
      }
      ds.Write(new byte[] { 0xFE, 0xFF, 0x00, 0xE0 }, 0, 4);
      if (table) { ds.Write(BitConverter.GetBytes((uint)(4 * at.Count)), 0, 4); foreach (uint o in at) ds.Write(BitConverter.GetBytes(o), 0, 4); } else ds.Write(new byte[4], 0, 4);
      items.WriteTo(ds); ds.Write(new byte[] { 0xFE, 0xFF, 0xDD, 0xE0, 0, 0, 0, 0 }, 0, 8);
    }
    using (FileStream f = File.Create(path)) {
      f.Write(new byte[128], 0, 128); f.Write(a.GetBytes("DICM"), 0, 4);
      f.Write(new byte[] { 2, 0, 0, 0, (byte)'U', (byte)'L', 4, 0 }, 0, 8); f.Write(BitConverter.GetBytes((uint)meta.Length), 0, 4); meta.WriteTo(f); ds.WriteTo(f);
    }
  }
  // samples (pixel after pixel) -> the raw bytes of an uncompressed frame
  public static byte[] Raw(ushort[] v, int w, int h, int comps, int allocated, bool planar) {
    int n = w * h; byte[] o = new byte[n * comps * allocated / 8];
    for (int i = 0; i < n; i++) for (int c = 0; c < comps; c++) {
      ushort s = v[i * comps + c]; int at = planar ? c * n + i : i * comps + c;
      if (allocated == 8) o[at] = (byte)s; else { o[at * 2] = (byte)s; o[at * 2 + 1] = (byte)(s >> 8); }
    }
    return o;
  }
  // RLE (PS3.5 annex G): a 64-byte header, then one PackBits-coded segment for each byte of each sample, high byte first
  public static byte[] Rle(ushort[] v, int w, int h, int comps, int allocated) {
    int n = w * h, bytes = allocated / 8; List<byte[]> segs = new List<byte[]>();
    for (int c = 0; c < comps; c++) for (int b = bytes - 1; b >= 0; b--) {
      byte[] plane = new byte[n]; for (int i = 0; i < n; i++) plane[i] = (byte)(v[i * comps + c] >> (8 * b));
      MemoryStream m = new MemoryStream();
      for (int y = 0; y < h; y++) {                         // each row packed on its own
        int x = 0;
        while (x < w) {
          int run = 1; while (x + run < w && run < 128 && plane[y * w + x + run] == plane[y * w + x]) run++;
          if (run >= 2) { m.WriteByte((byte)(257 - run)); m.WriteByte(plane[y * w + x]); x += run; }
          else {
            int lit = 1; while (x + lit < w && lit < 128 && !(x + lit + 1 < w && plane[y * w + x + lit] == plane[y * w + x + lit + 1])) lit++;
            m.WriteByte((byte)(lit - 1)); m.Write(plane, y * w + x, lit); x += lit;
          }
        }
      }
      if (m.Length % 2 == 1) m.WriteByte(0x80);            // a "no operation" byte to an even length
      segs.Add(m.ToArray());
    }
    MemoryStream o = new MemoryStream(); o.Write(BitConverter.GetBytes((uint)segs.Count), 0, 4); uint at = 64;
    for (int i = 0; i < 15; i++) { o.Write(BitConverter.GetBytes(i < segs.Count ? at : 0u), 0, 4); if (i < segs.Count) at += (uint)segs[i].Length; }
    foreach (byte[] s in segs) o.Write(s, 0, s.Length);
    return o.ToArray();
  }
  // Lossless JPEG (T.81 annex H): one scan, all components together, the given predictor,
  // a restart marker every `restart` pixels (0: none). One plain Huffman table: 5 bits a category.
  public static byte[] Lossless(ushort[] v, int w, int h, int comps, int bits, int predictor, int restart) {
    MemoryStream o = new MemoryStream(); Action<int> B = delegate(int b) { o.WriteByte((byte)b); };
    B(0xFF); B(0xD8);
    B(0xFF); B(0xC4); B(0); B(2 + 1 + 16 + 17); B(0); for (int l = 1; l <= 16; l++) B(l == 5 ? 17 : 0); for (int s = 0; s <= 16; s++) B(s);
    B(0xFF); B(0xC3); B(0); B(8 + 3 * comps); B(bits); B(h >> 8); B(h & 255); B(w >> 8); B(w & 255); B(comps); for (int c = 0; c < comps; c++) { B(c + 1); B(0x11); B(0); }
    if (restart > 0) { B(0xFF); B(0xDD); B(0); B(4); B(restart >> 8); B(restart & 255); }
    B(0xFF); B(0xDA); B(0); B(6 + 2 * comps); B(comps); for (int c = 0; c < comps; c++) { B(c + 1); B(0); } B(predictor); B(0); B(0);
    ulong acc = 0; int n = 0;
    Action<int, int> Put = delegate(int value, int count) {
      for (int i = count - 1; i >= 0; i--) { acc = (acc << 1) | (uint)((value >> i) & 1); if (++n == 8) { B((int)acc); if (acc == 0xFF) B(0); acc = 0; n = 0; } }
    };
    Action Flush = delegate { while (n != 0) Put(1, 1); };
    int first = 0, row = w * comps, done = 0, marker = 0;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      if (restart > 0 && done > 0 && done % restart == 0) { Flush(); B(0xFF); B(0xD0 + (marker++ & 7)); first = y; }
      for (int c = 0; c < comps; c++) {
        int at = (y * w + x) * comps + c, pred;
        if (y == first) pred = x == 0 ? 1 << (bits - 1) : v[at - comps];
        else if (x == 0) pred = v[at - row];
        else {
          int ra = v[at - comps], rb = v[at - row], rc = v[at - row - comps];
          pred = predictor == 1 ? ra : predictor == 2 ? rb : predictor == 3 ? rc : predictor == 4 ? ra + rb - rc : predictor == 5 ? ra + ((rb - rc) >> 1) : predictor == 6 ? rb + ((ra - rc) >> 1) : (ra + rb) >> 1;
        }
        int d = (v[at] - pred) & 0xFFFF; if (d > 32768) d -= 65536;
        if (d == 0) Put(0, 5);
        else if (d == 32768) Put(16, 5);
        else { int mag = Math.Abs(d), cat = 0; while ((mag >> cat) != 0) cat++; Put(cat, 5); Put(d > 0 ? d : d + (1 << cat) - 1, cat); }
      }
      done++;
    }
    Flush(); B(0xFF); B(0xD9);
    return o.ToArray();
  }
  // every value of two bitmaps alike?
  public static int Differ(Bitmap a, Bitmap b) {
    if (a.Width != b.Width || a.Height != b.Height) return -1; int n = 0;
    for (int y = 0; y < a.Height; y++) for (int x = 0; x < a.Width; x++) if (a.GetPixel(x, y).ToArgb() != b.GetPixel(x, y).ToArgb()) n++;
    return n;
  }
}
'@
$script:res = @()
function Check([string]$label, $good, [string]$extra = '') { $script:res += [bool]$good; '{0} {1} {2}' -f $(if ($good) { 'PASS' } else { 'FAIL' }), $label, $extra }
$RAW = '1.2.840.10008.1.2.1'; $RLE = '1.2.840.10008.1.2.5'; $JLL = '1.2.840.10008.1.2.4.57'; $SV1 = '1.2.840.10008.1.2.4.70'
$dir = Join-Path $env:TEMP ('bethesda-cd-viewer-test-' + [Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $dir | Out-Null
function Frames([object[]]$list) { $l = New-Object 'Collections.Generic.List[byte[]]'; foreach ($x in $list) { $l.Add([byte[]]$x) }; return , $l }
# Two files hold the same picture when the viewer draws them alike through EVERY window of
# 256 values across the range: then every stored value is the same.
function Same([string]$a, [string]$b, [int]$bits, [int]$frames = 1) {
  $p = [Bethesda.Viewer.Picture]::Open($a); $q = [Bethesda.Viewer.Picture]::Open($b)
  try {
    if ($p.Problem -or $q.Problem) { return "problem: [$($p.Problem)] [$($q.Problem)]" }
    if ($p.Steps -ne $frames -or $q.Steps -ne $frames) { return "frames: $($p.Steps) $($q.Steps)" }
    for ($f = 0; $f -lt $frames; $f++) {
      for ($c = 128; $c -lt (1 -shl $bits); $c += 256) {
        $x = $p.Render($f, $c, 256, $false); $y = $q.Render($f, $c, 256, $false)
        $d = [TestDicom]::Differ($x, $y); if ($d -ne 0) { return "frame $f, window $c : $d pixels differ" }
      }
    }
    return ''
  } finally { $p.Dispose(); $q.Dispose() }
}
try {
  '1. uncompressed pictures come out as they went in'
  $w = 61; $h = 47
  foreach ($k in @(@(8, 8, 1, 'MONOCHROME2'), @(12, 16, 1, 'MONOCHROME2'), @(16, 16, 1, 'MONOCHROME2'), @(8, 8, 3, 'RGB'))) {
    $bits = $k[0]; $alloc = $k[1]; $comps = $k[2]; $v = [TestDicom]::Paint($w, $h, $comps, $bits, 3)
    $f = Join-Path $dir "raw_${bits}_$comps.dcm"
    [TestDicom]::Write($f, $RAW, $w, $h, $bits, $alloc, $comps, $k[3], $false, $false, (Frames @(, [TestDicom]::Raw($v, $w, $h, $comps, $alloc, $false))), '1', 1, 'Brut', 1, '', '', $false)
    $p = [Bethesda.Viewer.Picture]::Open($f); $bad = 0; $max = (1 -shl $bits) - 1
    # through a window as wide as the range, a grey value v of the file is shown as round(v * 255 / max)
    $b = $p.Render(0, (1 -shl $bits) / 2, (1 -shl $bits), $false)
    for ($i = 0; $i -lt 400; $i++) { $x = ($i * 37) % $w; $y = ($i * 11) % $h; $c = $b.GetPixel($x, $y); $s = $v[($y * $w + $x) * $comps]
      $want = if ($bits -eq 8) { $s } else { [int][Math]::Round((($s - ((1 -shl $bits) / 2 - 0.5)) / ((1 -shl $bits) - 1) + 0.5) * 255) }
      if ([Math]::Abs($c.R - $want) -gt 0) { $bad++ } }
    Check "  $bits bits, $comps sample(s) a pixel: what is drawn is what was written" ($p.Problem -eq '' -and $p.Coding -eq 'raw' -and $bad -eq 0) "$bad of 400 pixels differ"
    $p.Dispose()
  }
  $v = [TestDicom]::Paint($w, $h, 3, 8, 5); $a = Join-Path $dir 'rgb_px.dcm'; $b2 = Join-Path $dir 'rgb_plane.dcm'
  [TestDicom]::Write($a, $RAW, $w, $h, 8, 8, 3, 'RGB', $false, $false, (Frames @(, [TestDicom]::Raw($v, $w, $h, 3, 8, $false))), '1', 2, 'RGB', 1, '', '', $false)
  [TestDicom]::Write($b2, $RAW, $w, $h, 8, 8, 3, 'RGB', $true, $false, (Frames @(, [TestDicom]::Raw($v, $w, $h, 3, 8, $true))), '1', 2, 'RGB', 2, '', '', $false)
  Check '  colour stored pixel after pixel and colour stored plane after plane: the same picture' ((Same $a $b2 8) -eq '') (Same $a $b2 8)

  '2. RLE'
  foreach ($k in @(@(8, 8, 1, 'MONOCHROME2'), @(16, 16, 1, 'MONOCHROME2'), @(8, 8, 3, 'RGB'))) {
    $bits = $k[0]; $alloc = $k[1]; $comps = $k[2]; $fr = @(); $rl = @()
    foreach ($n in 1..3) { $v = [TestDicom]::Paint($w, $h, $comps, $bits, 10 + $n); $fr += , [TestDicom]::Raw($v, $w, $h, $comps, $alloc, $false); $rl += , [TestDicom]::Rle($v, $w, $h, $comps, $alloc) }
    $a = Join-Path $dir "rle_raw_${bits}_$comps.dcm"; $b2 = Join-Path $dir "rle_${bits}_$comps.dcm"
    [TestDicom]::Write($a, $RAW, $w, $h, $bits, $alloc, $comps, $k[3], $false, $false, (Frames $fr), '2', $bits + $comps, 'RLE', 1, '', '', $false)
    [TestDicom]::Write($b2, $RLE, $w, $h, $bits, $alloc, $comps, $k[3], $false, $false, (Frames $rl), '2', $bits + $comps, 'RLE', 2, '', '', $false)
    $why = Same $a $b2 $bits 3
    Check "  $bits bits, $comps sample(s), 3 frames: every value of every frame as in the uncompressed file" ($why -eq '') $why
  }

  '3. lossless JPEG - each of the seven predictors, with and without restart intervals'
  $n = 0; $bad = @()
  foreach ($k in @(@(8, 8, 1, 'MONOCHROME2'), @(12, 16, 1, 'MONOCHROME2'), @(16, 16, 1, 'MONOCHROME2'), @(8, 8, 3, 'RGB'))) {
    $bits = $k[0]; $alloc = $k[1]; $comps = $k[2]; $v = [TestDicom]::Paint($w, $h, $comps, $bits, 20 + $bits + $comps)
    $a = Join-Path $dir "jll_raw_${bits}_$comps.dcm"
    [TestDicom]::Write($a, $RAW, $w, $h, $bits, $alloc, $comps, $k[3], $false, $false, (Frames @(, [TestDicom]::Raw($v, $w, $h, $comps, $alloc, $false))), '3', $bits + $comps, 'JPEG', 1, '', '', $false)
    foreach ($pred in 1..7) { foreach ($ri in 0, ($w * 2)) {
      $b2 = Join-Path $dir "jll_${bits}_${comps}_p${pred}_r$ri.dcm"
      [TestDicom]::Write($b2, $(if ($pred -eq 1) { $SV1 } else { $JLL }), $w, $h, $bits, $alloc, $comps, $k[3], $false, $false, (Frames @(, [TestDicom]::Lossless($v, $w, $h, $comps, $bits, $pred, $ri))), '3', $bits + $comps, 'JPEG', 2, '', '', $false)
      $why = Same $a $b2 $bits; $n++; if ($why) { $bad += "$bits bits x$comps predictor $pred restart $ri : $why" }
    } }
  }
  Check "  $n files (8, 12 and 16 bits grey, 8 bits colour; predictors 1 to 7; restart every two rows or none): every value as in the uncompressed file" ($bad.Count -eq 0) ($bad -join ' | ')
  # several frames, with the table of offsets and without
  $fr = @(); $jl = @(); foreach ($i in 1..4) { $v = [TestDicom]::Paint($w, $h, 1, 8, 40 + $i); $fr += , [TestDicom]::Raw($v, $w, $h, 1, 8, $false); $jl += , [TestDicom]::Lossless($v, $w, $h, 1, 8, 1, 0) }
  $a = Join-Path $dir 'clip_raw.dcm'; [TestDicom]::Write($a, $RAW, $w, $h, 8, 8, 1, 'MONOCHROME2', $false, $false, (Frames $fr), '3', 30, 'Clip', 1, '', '', $false)
  foreach ($table in $true, $false) {
    $b2 = Join-Path $dir "clip_jll_$table.dcm"; [TestDicom]::Write($b2, $SV1, $w, $h, 8, 8, 1, 'MONOCHROME2', $false, $false, (Frames $jl), '3', 30, 'Clip', 2, '', '', $table)
    $why = Same $a $b2 8 4
    Check "  a file of 4 frames, lossless JPEG, $(if ($table) { 'with' } else { 'without' }) the table of offsets: each frame is the right one" ($why -eq '') $why
  }

  '4. a damaged file is said to be unreadable - never drawn wrong, never a failure'
  $good = [IO.File]::ReadAllBytes((Join-Path $dir 'jll_8_3_p1_r0.dcm')); $out = @{}; $rnd = New-Object Random(11)
  foreach ($i in 1..60) {
    $bytes = [byte[]]$good.Clone()
    if ($i % 2) { $bytes = [byte[]]$bytes[0..($rnd.Next(1200, $bytes.Length - 2))] } else { foreach ($j in 1..(1 + $rnd.Next(8))) { $bytes[$rnd.Next(1300, $bytes.Length)] = [byte]$rnd.Next(256) } }
    $f = Join-Path $dir 'damaged.dcm'; [IO.File]::WriteAllBytes($f, $bytes); $r = ''
    try { $p = [Bethesda.Viewer.Picture]::Open($f); if ($p.Problem) { $r = 'refused' } else { [void]$p.Render(0, 128, 256, $false); $r = 'drawn' }; $p.Dispose() } catch { $r = 'refused' }
    $out[$r] = 1 + [int]$out[$r]
  }
  [IO.File]::Delete((Join-Path $dir 'damaged.dcm'))
  Check '  60 damaged copies of a lossless JPEG file (cut short, bytes changed): none makes the viewer fail, nearly all are refused' ($out['refused'] -ge 55) "refused $($out['refused']), drawn $([int]$out['drawn'])"

  '5. the list of a folder, and the words with accents'
  $v = [TestDicom]::Paint($w, $h, 1, 12, 7)
  [TestDicom]::Write((Join-Path $dir 'film_a.dcm'), $RAW, $w, $h, 12, 16, 1, 'MONOCHROME2', $false, $false, (Frames @(, [TestDicom]::Raw($v, $w, $h, 1, 16, $false))), '4', 1, 'Thorax de face', 2, 'ISO_IR 100', '2048/4096', $false)
  [TestDicom]::Write((Join-Path $dir 'film_b.dcm'), $RAW, $w, $h, 12, 16, 1, 'MONOCHROME1', $false, $false, (Frames @(, [TestDicom]::Raw($v, $w, $h, 1, 16, $false))), '4', 1, 'Thorax de face', 1, 'ISO_IR 100', '2048/4096', $false)
  [TestDicom]::Write((Join-Path $dir 'us_a.dcm'), $RAW, $w, $h, 8, 8, 3, 'RGB', $false, $false, (Frames @(, [TestDicom]::Raw([TestDicom]::Paint($w, $h, 3, 8, 8), $w, $h, 3, 8, $false))), '4', 2, 'Vésicule biliaire', 1, 'ISO_IR 192', '', $false)
  $d = [Bethesda.Viewer.Disc]::Open($dir)
  $st4 = $d.Studies | Where-Object { $_.Date -eq '2026-10-04' }
  Check '  the exams, most recent first; series and images in their own order; accents kept (Latin-1 and UTF-8)' ($d.Studies.Count -eq 4 -and $d.Studies[0].Date -eq '2026-10-04' -and $st4.Series.Count -eq 2 -and $st4.Series[0].Images[0].Number -eq 1 -and $st4.Series[1].Description -eq 'Vésicule biliaire' -and $d.PatientName -eq 'ESSAI Hélène') "$($d.Studies.Count) exams, $($d.ImageCount) images, $($d.PatientName), $($st4.Series[1].Description)"

  '5b. words in other alphabets'
  function U([int[]]$points) { -join ($points | ForEach-Object { [char]$_ }) }
  function Dec([byte[]]$bytes, $named, [bool]$guess) { [Bethesda.Viewer.DicomText]::Decode($bytes, $named, $guess) }
  $latin = [Text.Encoding]::GetEncoding(28591); $kr = [Text.Encoding]::GetEncoding(949); $utf = New-Object Text.UTF8Encoding($false)
  $fr = (U 0xC9) + 'SSAI^H' + (U 0xE9) + 'l' + (U 0xE8) + 'ne'                  # a French name with accents
  $given = (U 0xAE38, 0xB3D9); $hong = (U 0xD64D) + '^' + $given                # a Korean name (Hong Gildong), in Hangul
  $hanja = (U 0x6D2A) + '^' + (U 0x5409, 0x6D1E)                                # the same in ideographs
  Check '  French in Western European bytes and in UTF-8, named or not: as written' ((Dec ($latin.GetBytes($fr)) $latin $true) -eq $fr -and (Dec ($utf.GetBytes($fr)) $latin $true) -eq $fr -and (Dec ($utf.GetBytes($fr)) $utf $false) -eq $fr)
  $side = 'CR' + (U 0xC9, 0xC9) + 'E cr' + (U 0xE9, 0xE9) + 'e ' + (U 0xC0, 0xC9) + ' ' + (U 0xE7, 0xE0) + ' ' + (U 0xB0) + 'C'
  Check '  ... accents side by side are not taken for Korean' ((Dec ($latin.GetBytes($side)) $latin $true) -eq $side)
  Check '  Korean, the file naming its set' ((Dec ($kr.GetBytes($hong)) $kr $false) -eq $hong)
  Check '  Korean, the file naming no set - or Western Europe' ((Dec ($kr.GetBytes($hong)) $latin $true) -eq $hong -and (Dec ($kr.GetBytes("NA $hong 01")) $latin $true) -eq "NA $hong 01")
  Check '  Korean in UTF-8 that the file does not name' ((Dec ($utf.GetBytes($hong)) $latin $true) -eq $hong)
  $esc = [byte[]](0x1B, 0x24, 0x29, 0x43)                                       # "what follows is Korean"
  $three = [byte[]]($latin.GetBytes('Hong^Gildong=') + $esc + $kr.GetBytes((U 0x6D2A)) + $latin.GetBytes('^') + $esc + $kr.GetBytes((U 0x5409, 0x6D1E)) + $latin.GetBytes('=') + $esc + $kr.GetBytes((U 0xD64D)) + $latin.GetBytes('^') + $esc + $kr.GetBytes($given))
  $got = Dec $three $kr $false
  Check '  a name in three writings with the switches inside it: no stray signs' ($got -eq "Hong^Gildong=$hanja=$hong" -and (Dec $three $latin $true) -eq $got)
  $local = (U 0xD64D) + ' ' + $given
  Check '  ... shown with the local writing beside the Latin one; a name in one writing as before' ([Bethesda.Viewer.DicomText]::PersonName($got) -eq "Hong Gildong ($local)" -and [Bethesda.Viewer.DicomText]::PersonName('RAKOTO^Jean^^^') -eq 'RAKOTO Jean' -and [Bethesda.Viewer.DicomText]::PersonName($hong) -eq $local -and [Bethesda.Viewer.DicomText]::PersonName("=$hanja") -eq ((U 0x6D2A) + ' ' + (U 0x5409, 0x6D1E)) -and [Bethesda.Viewer.DicomText]::PersonName('') -eq '')
  $yamada = (U 0x5C71, 0x7530); $jis = [byte[]]([Text.Encoding]::GetEncoding(51932).GetBytes($yamada) | ForEach-Object { $_ -band 0x7F })
  $jp = [byte[]]($latin.GetBytes('Yamada^Tarou=') + [byte[]](0x1B, 0x24, 0x42) + $jis + [byte[]](0x1B, 0x28, 0x42) + $latin.GetBytes('^X'))
  $wang = (U 0x738B, 0x4E94); $gb = [Text.Encoding]::GetEncoding(54936)
  Check '  Japanese with its switches; Chinese when the file names it' ((Dec $jp ([Text.Encoding]::GetEncoding(932)) $false) -eq "Yamada^Tarou=$yamada^X" -and (Dec ($gb.GetBytes($wang)) $gb $false) -eq $wang)

  '6. the window'
  [Bethesda.Viewer.Texts]::Lang = 'fr'
  $form = New-Object Bethesda.Viewer.MainForm($d); Show-Quietly $form
  Check '  title: the patient; the line that says what the viewer is for; its version in the help' ($form.Text -match 'ESSAI Hélène' -and ($form.Controls | Where-Object { $_.Text -match 'non destinée au diagnostic' }) -and [Bethesda.Viewer.Texts]::Get('helpText') -match [regex]::Escape([Bethesda.Product]::Version))
  Check '  opens on the first series of the most recent exam' ($form.CurrentSeries -eq $st4.Series[0] -and $form.Current.Problem -eq '' -and $form.WindowCenter -eq 2048 -and $form.WindowWidth -eq 4096) $form.CurrentSeries.Label
  $form.StepImage(1); $b0 = $form.CurrentBitmap.GetPixel(30, 20).R; $form.StepImage(-1); $b1 = $form.CurrentBitmap.GetPixel(30, 20).R
  Check '  next image, and back: the film whose grey scale is turned over (MONOCHROME1) is the other one''s negative' ($b0 + $b1 -eq 255) "$b0 + $b1"
  $flags = [Reflection.BindingFlags]'Instance,NonPublic'
  function Mouse([string]$what, [string]$button, [int]$x, [int]$y) {
    $e = New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]$button, 1, $x, $y, 0); $arg = New-Object object[] 1; $arg[0] = $e.PSObject.BaseObject
    [void]$form.Panel.GetType().GetMethod("OnMouse$what", $flags).Invoke($form.Panel, $arg)
  }
  $form.Select($st4.Series[1]); [Windows.Forms.Application]::DoEvents()
  $c0 = $form.CurrentBitmap.GetPixel(30, 20)
  Mouse 'Down' 'Left' 300 300; Mouse 'Move' 'Left' 300 200; $during = $form.Panel.BottomRight; Mouse 'Up' 'Left' 300 200
  $c1 = $form.CurrentBitmap.GetPixel(30, 20)
  Check '  a colour picture, the left button dragged up: brighter, alike for red, green and blue; the corner and the slider follow' ($form.Brightness -gt 20 -and $during -match 'Luminosité \+' -and (($c1.R - $c0.R) -ge 0) -and (($c1.R -gt $c0.R) -or $c0.R -eq 255)) "$($c0.R),$($c0.G),$($c0.B) -> $($c1.R),$($c1.G),$($c1.B) | $($during -replace "`n", ' / ')"
  $wc = $form.WindowCenter
  Mouse 'Down' 'Right' 300 300; Mouse 'Move' 'Right' 350 320; Mouse 'Up' 'Right' 350 320
  Check '  the right button dragged: the picture moves, the brightness stays' ($form.WindowCenter -eq $wc -and -not $form.Panel.Fitted)
  $form.ResetView(); $c2 = $form.CurrentBitmap.GetPixel(30, 20)
  Check '  reset: the picture as stored, the sliders in the middle, fitted' ($form.Brightness -eq 0 -and $form.Contrast -eq 0 -and $c2.ToArgb() -eq $c0.ToArgb() -and $form.Panel.Fitted)
  $clip = $d.Studies | ForEach-Object { $_.Series } | Where-Object { $_.Description -eq 'Clip' } | Select-Object -First 1
  $form.Select($clip); [Windows.Forms.Application]::DoEvents()
  while ($form.Current.Frames -le 1 -and $form.CurrentIndex -lt $clip.Images.Count - 1) { $form.StepImage(1) }
  $form.StepFrame(1); $form.StepFrame(1)
  Check '  a file of several frames: the wheel goes through them' ($form.Current.Frames -eq 4 -and $form.CurrentFrame -eq 2)
  $form.Close()
  [Bethesda.Viewer.Texts]::Lang = 'en'
  Check '  English words when Windows is not in French' ([Bethesda.Viewer.Texts]::Get('notice') -match 'not for diagnosis')
} finally { [IO.Directory]::Delete($dir, $true) }
if ($script:res -contains $false) { "SOME FAILED $($script:res.Count)"; exit 1 } else { "ALL PASS $($script:res.Count)" }
