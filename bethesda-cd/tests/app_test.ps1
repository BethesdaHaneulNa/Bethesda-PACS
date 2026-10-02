# Bethesda CD - the program driven without a person: this script loads the built
# Bethesda-CD.exe, fills its boxes, calls what its buttons call, answers its questions,
# and checks what comes out. It needs a TEST installation of the EMR (never the one the
# clinic works on) that has a patient with at least two imaging exams holding images.
#
#   .\app_test.ps1 -Emr http://127.0.0.1:9188 -Login someone -Chart 26-00001 -ExamIds 55,56 -Base D:\some\empty\folder
#
# The password comes from the environment variable BETHESDA_CD_TEST_PASSWORD (it is never
# written to a file by this script, and not printed).
# Nothing is burnt: the disc question is answered "no". Folders and disc images the test
# makes are made under -Base (and -IsoDir) and deleted again.
param(
  [Parameter(Mandatory = $true)][string]$Emr, [Parameter(Mandatory = $true)][string]$Login, [Parameter(Mandatory = $true)][string]$Chart,
  [Parameter(Mandatory = $true)][string]$ExamIds, [Parameter(Mandatory = $true)][string]$Base,
  [string]$IsoDir = $env:TEMP, [string]$Exe = '', [ValidateSet('fr', 'ko', 'en')][string]$Lang = 'fr', [string]$Shots = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Exe) { $Exe = Join-Path $PSScriptRoot '..\build\Bethesda-CD.exe' }
[int[]]$ExamIds = @($ExamIds -split '[ ,]+' | Where-Object { $_ } | ForEach-Object { [int]$_ })      # "55,56"
$pw = $env:BETHESDA_CD_TEST_PASSWORD
if (-not $pw) { throw 'Set BETHESDA_CD_TEST_PASSWORD to the test account''s password first.' }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$Exe = (Resolve-Path -LiteralPath $Exe).Path
[void][Reflection.Assembly]::LoadFrom($Exe)
$script:res = @(); $script:said = New-Object Collections.Generic.List[string]; $script:answer = $true; $script:folder = $Base; $script:isoPath = ''; $script:isoName = ''
function Check([string]$label, $good, [string]$extra = '') { $script:res += [bool]$good; '{0} {1} {2}' -f $(if ($good) { 'PASS' } else { 'FAIL' }), $label, $extra }
# the person at the window, played by the test
[Bethesda.Cd.Ask]::Message = [Action[string, string]] { param($text, $kind) $script:said.Add("[$kind] $text") }
[Bethesda.Cd.Ask]::Confirm = [Func[string, bool]] { param($text) $script:said.Add("[ask] $text"); [bool]$script:answer }
[Bethesda.Cd.Ask]::Folder = [Func[string, string]] { param($start) [string]$script:folder }
[Bethesda.Cd.Ask]::IsoFile = [Func[string, string, string]] { param($name, $start) $script:isoName = $name; [string]$script:isoPath }
[Bethesda.Cd.Texts]::Lang = $Lang
$ini = Join-Path $env:TEMP ('bethesda-cd-test-' + [Guid]::NewGuid().ToString('N') + '.ini')
[void][Bethesda.Cd.DiscFolder]::RemoveTemp('')
$form = New-Object Bethesda.Cd.MainForm([Bethesda.Cd.Config]::Read($ini)); $form.Show(); [Windows.Forms.Application]::DoEvents()
function Shot([string]$name) {
  if (-not $Shots) { return }
  [Windows.Forms.Application]::DoEvents()
  $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height); $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
  $bmp.Save((Join-Path $Shots ("bethesda-cd-$Lang-$name.png")), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function TempEmpty { $t = [Bethesda.Cd.DiscFolder]::TempRoot; return (-not (Test-Path $t) -or @(Get-ChildItem $t).Count -eq 0) }
$v = [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe)
"$($v.ProductName) $($v.ProductVersion)  ($Exe)"

'1. signing in'
Check '  the window opens on the sign-in panel, with the default EMR address, and says its version' ($form.LoginPanel.Visible -and -not $form.MainPanel.Visible -and $form.Url.Text -eq 'http://localhost:9080' -and $form.Text -match 'Bethesda CD' -and $v.ProductVersion -match '^\d+\.\d+\.\d+$')
Shot 'login'
$form.Url.Text = $Emr; $form.LoginBox.Text = $Login; $form.Password.Text = 'wrong-one'
$ok = $form.Login()
Check '  wrong password: stays on the panel, says so, the password box is emptied' (-not $ok -and $form.LoginPanel.Visible -and $form.LoginMsg.Text.Length -gt 5 -and $form.Password.Text -eq '') $form.LoginMsg.Text
$form.Password.Text = $pw
$ok = $form.Login()
Check '  right password: the main panel, the name, the address kept for next time - and no password in the settings file' ($ok -and $form.MainPanel.Visible -and $form.Who.Text.Length -gt 3 -and ([Bethesda.Cd.Config]::Read($ini)).EmrUrl -eq $Emr -and -not ((Get-Content $ini -Raw) -match [regex]::Escape($pw)))
Check '  nothing can be copied yet' (-not $form.Burn.Enabled -and -not $form.Iso.Enabled -and -not $form.FolderButton.Enabled)
"  drive line: $($form.Drive.Text)"

'2. the patient'
$form.Chart.Text = 'no-such-chart-000'; $ok = $form.Search()
Check '  unknown chart number: said in the patient line, empty list' (-not $ok -and $form.Grid.Rows.Count -eq 0 -and $form.PatientLine.Text.Length -gt 5) $form.PatientLine.Text
$form.Chart.Text = $Chart; $ok = $form.Search()
Check '  found: the patient line names the chart, the exams are listed' ($ok -and $form.Grid.Rows.Count -ge $ExamIds.Count -and $form.PatientLine.Text -match [regex]::Escape($Chart)) "$($form.Grid.Rows.Count) exams"
$rows = @{}; foreach ($r in $form.Grid.Rows) { $rows[[int]$r.Tag['id']] = $r }
$blocked = @($form.Grid.Rows | Where-Object { [string]$_.Tag['block'] })
if ($blocked.Count) {
  Check '  an exam that must not leave cannot be ticked, and says why' ($blocked[0].Cells[0].ReadOnly -and [string]$blocked[0].Cells[6].Value -ne '') "$($blocked.Count) such exam(s): $($blocked[0].Cells[6].Value)"
  $blocked[0].Cells[0].Value = $true
}
$items = 0; foreach ($id in $ExamIds) { if (-not $rows[$id]) { throw "exam $id is not in the list" }; $rows[$id].Cells[0].Value = $true; $items += [int]$rows[$id].Tag['items'] }
[Windows.Forms.Application]::DoEvents(); $form.UpdateSelection()
Check "  $($ExamIds.Count) ticked (a tick forced on a refused exam does not count): the line says so, with $items images" ($form.Chosen().Count -eq $ExamIds.Count -and $form.Selection.Text -match "\b$($ExamIds.Count)\b" -and $form.Selection.Text -match "\b$items\b") $form.Selection.Text
Check '  saving is offered' ($form.Iso.Enabled -and $form.FolderButton.Enabled)
Shot 'chosen'

'3. saved to a folder'
$script:said.Clear(); $shown = New-Object Collections.Generic.List[string]
$form.add_StatusShown([Action[string, int]] { param($text, $percent) $shown.Add($text) })
$r = $form.Export('folder', '')
$top = ''; if ($r.Ok) { $top = (Get-ChildItem $r.Path -Name | Sort-Object) -join ',' }
Check '  saved, said where, nothing left busy' ($r.Ok -and @(Get-ChildItem (Join-Path $r.Path 'IMAGES')).Count -eq $items -and -not $form.Busy -and $script:said.Count -eq 1 -and $script:said[0] -match [regex]::Escape($r.Path)) "$($r.Path) $($r.Code)"
Check '  the disc folder: DICOMDIR, IMAGES, README.TXT, the viewer VIEWER.EXE and AUTORUN.INF' ($top -eq 'AUTORUN.INF,DICOMDIR,IMAGES,README.TXT,VIEWER.EXE' -and ([IO.File]::ReadAllText((Join-Path $r.Path 'README.TXT')) -split 'VIEWER.EXE').Count -eq 3) $top
$built = Join-Path (Split-Path -Parent $Exe) 'VIEWER.EXE'
if (Test-Path $built) { Check '  the viewer on the disc is byte for byte the one that was built with the program' ((Get-FileHash (Join-Path $r.Path 'VIEWER.EXE')).Hash -eq (Get-FileHash $built).Hash) "$((Get-Item (Join-Path $r.Path 'VIEWER.EXE')).Length) bytes" }
Check '  while it worked the window said what it was doing' ($shown.Count -ge 3) "$($shown.Count) lines"
Check '  the working folder on this PC is empty again' (TempEmpty)
Check '  the folder is remembered for next time' (([Bethesda.Cd.Config]::Read($ini)).LastFolder -eq $Base)
$made = $r.Path
$script:folder = ''
$r = $form.Export('folder', '')
Check '  the folder question cancelled: nothing happens' (-not $r.Ok -and $r.Code -eq 'CANCELLED_BY_USER')
$script:folder = Join-Path $Base 'no-such-folder-here'
$script:said.Clear(); $r = $form.Export('folder', '')
Check '  a folder that is not there: said, nothing left behind' (-not $r.Ok -and $script:said.Count -eq 1 -and $script:said[0] -match '^\[error\]' -and (TempEmpty)) $script:said[0]
if ($made -and $made.StartsWith($Base, [StringComparison]::OrdinalIgnoreCase)) { [IO.Directory]::Delete($made, $true) }

'4. saved as a disc image'
$script:isoPath = Join-Path $IsoDir ('bethesda-cd-test-' + (Get-Date -Format 'HHmmss') + '.iso')
$script:said.Clear(); $r = $form.Export('iso', '')
Check '  the image is written and said' ($r.Ok -and (Test-Path $r.Path) -and (Get-Item $r.Path).Length -gt 300KB -and $script:said[0] -match '\.iso' -and $script:isoName -match '^[A-Za-z0-9_-]+_\d{8}_\d{4}\.iso$') "$((Get-Item $r.Path).Length) bytes, suggested name $($script:isoName)"
Check '  after the image: nothing of the patient left in the working folder' (TempEmpty)
$script:said.Clear(); $r = $form.Export('iso', '')
Check '  the same file name again: refused, the first image untouched' (-not $r.Ok -and $r.Code -eq 'EXISTS' -and (Test-Path $script:isoPath)) $script:said[0]
[IO.File]::Delete($script:isoPath)
$script:isoPath = 'C:\no-such-folder-bethesda-cd\x.iso'
$script:said.Clear(); $r = $form.Export('iso', '')
Check '  an image that cannot be written: said, no half file, nothing of the patient left' (-not $r.Ok -and $r.Code -eq 'ISO' -and $script:said[0] -match '^\[error\]' -and (TempEmpty)) $r.Code

'5. the disc in the drive - asked, answered no: nothing is written'
$script:answer = $false; $script:said.Clear()
$r = $form.Export('disc', '')
"  burn button enabled: $($form.Burn.Enabled) | answer: $($r.Code)"
Check '  no burn without a yes' (-not $r.Ok -and ($r.Code -eq 'CANCELLED_BY_USER' -or $r.Code -eq 'NO_DISC'))

'6. the session ends'
$form.Emr.Token = 'not-a-token'
$form.Chart.Text = $Chart; $ok = $form.Search()
Check '  a token the EMR no longer accepts: back to the sign-in panel, saying so' (-not $ok -and $form.LoginPanel.Visible -and $form.LoginMsg.Text.Length -gt 5 -and $form.Grid.Rows.Count -eq 0) $form.LoginMsg.Text
$form.Close(); [Windows.Forms.Application]::DoEvents()
Remove-Item $ini -ErrorAction SilentlyContinue
if ($script:res -contains $false) { "SOME FAILED $($script:res.Count)"; exit 1 } else { "ALL PASS $($script:res.Count)" }
