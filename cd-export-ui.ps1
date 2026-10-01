# The window of cd-export.ps1: sign in, look a patient up by chart number, tick exams,
# see their size, then save them to a folder, to a disc image, or burn them to the disc
# in the drive. What each step does is in cd-export-common.ps1; this file only shows and asks.
#
# Everything the window says is in $CdxText, French first (the staff's language); -Lang ko
# and -Lang en are for the people who install and support it.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$CdxText = @{
  fr = @{
    title = 'Bethesda — Copie des images sur CD'
    emrUrl = 'Adresse de l''EMR'; login = 'Identifiant'; password = 'Mot de passe'; signIn = 'Se connecter'; signOut = 'Se déconnecter'
    loginHint = 'Connectez-vous avec votre compte de l''EMR (Consultation ou Paiement).'
    connected = 'Connecté : {0}'
    chart = 'N° dossier'; search = 'Chercher'; patient = '{0} — né(e) le {1} — {2}'; noPatientYet = 'Tapez le N° dossier du patient, puis Entrée.'
    colDate = 'Date'; colType = 'Type'; colExam = 'Examen'; colImages = 'Images'; colSize = 'Taille'; colState = 'État'
    selNone = 'Cochez les examens à copier.'; sel = 'Sélection : {0} examen(s) · {1} image(s) · {2}'
    selMax = 'Au plus {0} examens à la fois.'
    noBurner = 'Aucun graveur sur ce PC — « Enregistrer en fichier ISO » et « Enregistrer dans un dossier » restent possibles.'
    noDisc = 'Graveur {0} — insérez un disque vierge.'
    discBlank = 'Graveur {0} — {1} vierge, {2} libres'; fits = '  ✔ tient sur ce disque'; tooBig = '  ✘ {0} de trop : décochez un examen ou utilisez un DVD'
    discUsed = 'Graveur {0} — ce disque n''est pas vierge : il ne sera pas utilisé.'; discOther = 'Graveur {0} — ce disque ne peut pas être gravé ici.'
    viewer = 'Ajouter la visionneuse d''images au disque (+ {0})'; stViewer = 'Ajout de la visionneuse… {0} / {1}'
    burn = 'Graver ce CD…'; iso = 'Enregistrer en fichier ISO…'; folder = 'Enregistrer dans un dossier…'
    askBurn = 'Graver {0} examen(s) ({1}) de {2} sur le disque du lecteur {3} ?'
    askFolder = 'Choisissez le dossier (ou la clé USB) où créer la copie'
    stFetch = 'Récupération des images… {0}'; stReadme = 'Préparation du disque…'; stCopy = 'Copie… {0} / {1}'; stImage = 'Préparation de l''image du disque…'
    stIso = 'Écriture du fichier ISO… {0} %'; stBurn = 'Gravure en cours… {0} %   {1}'; stCheck = 'Vérification du disque…'
    doneFolder = "Terminé. La copie est dans :`n{0}`n`n{1} fichiers, {2}. Chaque fichier a été relu et comparé.`n`nCe dossier contient les images d'un patient : supprimez-le quand il n'est plus utile."
    doneIso = "Terminé. Fichier ISO :`n{0}`n({1})`n`nCe fichier contient les images d'un patient : supprimez-le quand il n'est plus utile."
    doneBurn = "Terminé : le disque est gravé et vérifié.`n`nÉcrivez le nom du patient et la date sur le disque."
    doneBurnDrive = "Terminé : le disque est gravé (vérifié par le graveur).`n`nÉcrivez le nom du patient et la date sur le disque."
    doneBurnUnread = "Le disque est gravé, mais il n'a pas pu être relu pour la vérification.`nRemettez-le dans le lecteur et vérifiez qu'il s'ouvre avant de le remettre."
    badBurn = "La gravure a échoué : ce disque est à jeter.`n{0}`n`nMettez un autre disque vierge et recommencez."
    badVerify = "La vérification a échoué — ne remettez pas ce disque.`n{0} fichier(s) différent(s). Mettez un autre disque vierge et recommencez."
    busyClose = 'Une copie est en cours. Attendez qu''elle se termine.'
    expired = 'La session a expiré. Reconnectez-vous.'
    e_BAD_URL = 'L''adresse de l''EMR doit commencer par http:// (exemple : http://192.168.1.10:9080).'
    e_NO_ANSWER = 'L''EMR ne répond pas à cette adresse. Vérifiez l''adresse et le réseau.'
    e_NOT_EMR = 'Cette adresse répond, mais ce n''est pas l''EMR.'
    e_WRONG_LOGIN = 'Identifiant ou mot de passe incorrect.'
    e_FORBIDDEN = 'Ce compte n''a pas le droit de copier des images (il faut Consultation ou Paiement).'
    e_NO_PATIENT = 'Aucun patient avec ce N° dossier.'
    e_CANCELLED = 'examen annulé'; e_NO_IMAGES = 'pas d''images'; e_IDENTITY = 'avertissement d''identité : à régler d''abord dans l''EMR'
    e_BUSY = 'correction en cours : réessayez dans quelques minutes'; e_NOT_ON_SERVER = 'images absentes du serveur d''images'
    e_UNREACHABLE = 'Le serveur d''images ne répond pas. Réessayez dans un instant.'
    e_NOT_PAIRED = 'Le serveur d''images n''est pas relié à l''EMR. Prévenez l''administrateur.'
    e_NOT_LOGGED = 'Le journal des modifications n''a pas pu être écrit : rien n''a été copié.'
    e_OTHER_PATIENT = 'Les examens ne sont pas du même patient.'; e_TOO_MANY_EXAMS = 'Trop d''examens à la fois.'
    e_BROKEN = 'La connexion a été coupée pendant la récupération. Rien n''a été copié ; recommencez.'
    e_BAD_BUNDLE = 'Les images reçues sont incomplètes. Rien n''a été copié ; recommencez.'
    e_NO_ROOM = 'Pas assez de place à cet endroit : il faut {0}, il reste {1}.'
    e_NO_FOLDER = 'Ce dossier n''existe pas.'; e_WRITE_FAILED = 'La copie a échoué : {0}'
    e_NOT_VERIFIED = "La copie a été relue et elle est différente de l'original ({0} fichier(s)).`nSupprimez le dossier {1} et recommencez."
    e_EXISTS = 'Ce fichier existe déjà. Choisissez un autre nom.'
    e_ISO = 'Le fichier ISO n''a pas pu être écrit : {0}'
    e_other = 'Erreur : {0}'
    male = 'M'; female = 'F'
  }
  ko = @{
    title = 'Bethesda — 영상 CD 반출'
    emrUrl = 'EMR 주소'; login = '아이디'; password = '비밀번호'; signIn = '로그인'; signOut = '로그아웃'
    loginHint = 'EMR 계정으로 로그인하세요(진료 또는 수납 권한).'
    connected = '로그인: {0}'
    chart = '차트번호'; search = '조회'; patient = '{0} — 생년월일 {1} — {2}'; noPatientYet = '환자의 차트번호를 치고 Enter를 누르세요.'
    colDate = '날짜'; colType = '종류'; colExam = '검사'; colImages = '영상'; colSize = '크기'; colState = '상태'
    selNone = '반출할 검사를 체크하세요.'; sel = '선택: 검사 {0}건 · 영상 {1}장 · {2}'
    selMax = '한 번에 {0}건까지입니다.'
    noBurner = '이 PC에는 굽는 드라이브가 없습니다 — 「ISO 파일로 저장」과 「폴더에 저장」은 됩니다.'
    noDisc = '드라이브 {0} — 빈 디스크를 넣으세요.'
    discBlank = '드라이브 {0} — 빈 {1}, {2} 남음'; fits = '  ✔ 이 디스크에 들어갑니다'; tooBig = '  ✘ {0} 넘침: 검사를 줄이거나 DVD를 쓰세요'
    discUsed = '드라이브 {0} — 빈 디스크가 아닙니다. 이 디스크에는 굽지 않습니다.'; discOther = '드라이브 {0} — 이 드라이브로는 구울 수 없는 디스크입니다.'
    viewer = '디스크에 영상 뷰어도 넣기 (+ {0})'; stViewer = '뷰어를 넣는 중… {0} / {1}'
    burn = '이 CD에 굽기…'; iso = 'ISO 파일로 저장…'; folder = '폴더에 저장…'
    askBurn = '{2} 님의 검사 {0}건({1})을 {3} 드라이브의 디스크에 구울까요?'
    askFolder = '사본을 만들 폴더(또는 USB)를 고르세요'
    stFetch = '영상을 받는 중… {0}'; stReadme = '디스크 내용을 준비하는 중…'; stCopy = '복사 중… {0} / {1}'; stImage = '디스크 이미지를 만드는 중…'
    stIso = 'ISO 파일을 쓰는 중… {0} %'; stBurn = '굽는 중… {0} %   {1}'; stCheck = '구운 디스크를 확인하는 중…'
    doneFolder = "끝났습니다. 사본의 자리:`n{0}`n`n파일 {1}개, {2}. 파일마다 다시 읽어 원본과 비교했습니다.`n`n이 폴더에는 환자의 영상이 들어 있습니다. 쓸 일이 끝나면 지우세요."
    doneIso = "끝났습니다. ISO 파일:`n{0}`n({1})`n`n이 파일에는 환자의 영상이 들어 있습니다. 쓸 일이 끝나면 지우세요."
    doneBurn = "끝났습니다. 디스크를 굽고 확인했습니다.`n`n디스크에 환자 이름과 날짜를 적으세요."
    doneBurnDrive = "끝났습니다. 디스크를 구웠습니다(드라이브가 확인함).`n`n디스크에 환자 이름과 날짜를 적으세요."
    doneBurnUnread = "디스크는 구웠지만, 확인하려고 다시 읽지 못했습니다.`n디스크를 다시 넣어 열리는지 본 뒤에 건네세요."
    badBurn = "굽기에 실패했습니다. 이 디스크는 버리세요.`n{0}`n`n다른 빈 디스크를 넣고 다시 하세요."
    badVerify = "확인에서 어긋났습니다 — 이 디스크를 건네지 마세요.`n다른 파일 {0}개. 다른 빈 디스크를 넣고 다시 하세요."
    busyClose = '반출하는 중입니다. 끝날 때까지 기다리세요.'
    expired = '로그인이 만료되었습니다. 다시 로그인하세요.'
    e_BAD_URL = 'EMR 주소는 http:// 로 시작해야 합니다(예: http://192.168.1.10:9080).'
    e_NO_ANSWER = '이 주소에서 EMR이 응답하지 않습니다. 주소와 네트워크를 확인하세요.'
    e_NOT_EMR = '이 주소는 응답하지만 EMR이 아닙니다.'
    e_WRONG_LOGIN = '아이디 또는 비밀번호가 틀렸습니다.'
    e_FORBIDDEN = '이 계정은 영상을 반출할 권한이 없습니다(진료 또는 수납 권한이 필요).'
    e_NO_PATIENT = '이 차트번호의 환자가 없습니다.'
    e_CANCELLED = '취소된 검사'; e_NO_IMAGES = '영상 없음'; e_IDENTITY = '환자 번호 경고 — EMR에서 먼저 바로잡으세요'
    e_BUSY = '영상을 바로잡는 중 — 몇 분 뒤에 다시'; e_NOT_ON_SERVER = '영상 서버에 영상이 없음'
    e_UNREACHABLE = '영상 서버가 응답하지 않습니다. 잠시 뒤에 다시 하세요.'
    e_NOT_PAIRED = '영상 서버가 EMR과 연결되어 있지 않습니다. 관리자에게 알리세요.'
    e_NOT_LOGGED = '변경 기록을 남기지 못했습니다. 아무것도 반출하지 않았습니다.'
    e_OTHER_PATIENT = '같은 환자의 검사가 아닙니다.'; e_TOO_MANY_EXAMS = '한 번에 반출하기에는 검사가 너무 많습니다.'
    e_BROKEN = '받는 도중에 연결이 끊겼습니다. 아무것도 반출하지 않았습니다. 다시 하세요.'
    e_BAD_BUNDLE = '받은 영상이 온전하지 않습니다. 아무것도 반출하지 않았습니다. 다시 하세요.'
    e_NO_ROOM = '그 자리에 공간이 모자랍니다: {0} 필요, {1} 남음.'
    e_NO_FOLDER = '그 폴더가 없습니다.'; e_WRITE_FAILED = '복사에 실패했습니다: {0}'
    e_NOT_VERIFIED = "사본을 다시 읽었더니 원본과 다릅니다(파일 {0}개).`n{1} 폴더를 지우고 다시 하세요."
    e_EXISTS = '같은 이름의 파일이 이미 있습니다. 다른 이름을 고르세요.'
    e_ISO = 'ISO 파일을 쓰지 못했습니다: {0}'
    e_other = '오류: {0}'
    male = '남'; female = '여'
  }
  en = @{
    title = 'Bethesda — Copy images to CD'
    emrUrl = 'EMR address'; login = 'Login'; password = 'Password'; signIn = 'Sign in'; signOut = 'Sign out'
    loginHint = 'Sign in with your EMR account (Consultation or Payment).'
    connected = 'Signed in: {0}'
    chart = 'Chart no.'; search = 'Find'; patient = '{0} — born {1} — {2}'; noPatientYet = 'Type the patient''s chart number, then Enter.'
    colDate = 'Date'; colType = 'Type'; colExam = 'Exam'; colImages = 'Images'; colSize = 'Size'; colState = 'State'
    selNone = 'Tick the exams to copy.'; sel = 'Chosen: {0} exam(s) · {1} image(s) · {2}'
    selMax = 'At most {0} exams at a time.'
    noBurner = 'No disc burner on this PC — "Save as ISO file" and "Save to a folder" still work.'
    noDisc = 'Burner {0} — insert a blank disc.'
    discBlank = 'Burner {0} — blank {1}, {2} free'; fits = '  ✔ fits on this disc'; tooBig = '  ✘ {0} too much: untick an exam or use a DVD'
    discUsed = 'Burner {0} — this disc is not blank: it will not be used.'; discOther = 'Burner {0} — this disc cannot be written here.'
    viewer = 'Add the image viewer to the disc (+ {0})'; stViewer = 'Adding the viewer… {0} / {1}'
    burn = 'Burn this CD…'; iso = 'Save as ISO file…'; folder = 'Save to a folder…'
    askBurn = 'Burn {0} exam(s) ({1}) of {2} to the disc in drive {3}?'
    askFolder = 'Choose the folder (or USB stick) where the copy is made'
    stFetch = 'Fetching the images… {0}'; stReadme = 'Preparing the disc…'; stCopy = 'Copying… {0} / {1}'; stImage = 'Preparing the disc image…'
    stIso = 'Writing the ISO file… {0} %'; stBurn = 'Burning… {0} %   {1}'; stCheck = 'Checking the disc…'
    doneFolder = "Done. The copy is in:`n{0}`n`n{1} files, {2}. Every file was read back and compared.`n`nThis folder holds a patient's images: delete it when it is no longer needed."
    doneIso = "Done. ISO file:`n{0}`n({1})`n`nThis file holds a patient's images: delete it when it is no longer needed."
    doneBurn = "Done: the disc is burnt and checked.`n`nWrite the patient's name and the date on the disc."
    doneBurnDrive = "Done: the disc is burnt (checked by the burner).`n`nWrite the patient's name and the date on the disc."
    doneBurnUnread = "The disc is burnt, but it could not be read back for the check.`nPut it back in the drive and see that it opens before handing it over."
    badBurn = "Burning failed: throw this disc away.`n{0}`n`nInsert another blank disc and start again."
    badVerify = "The check failed — do not hand this disc over.`n{0} file(s) differ. Insert another blank disc and start again."
    busyClose = 'A copy is being made. Wait until it is finished.'
    expired = 'The session has expired. Sign in again.'
    e_BAD_URL = 'The EMR address must start with http:// (example: http://192.168.1.10:9080).'
    e_NO_ANSWER = 'The EMR does not answer at this address. Check the address and the network.'
    e_NOT_EMR = 'This address answers, but it is not the EMR.'
    e_WRONG_LOGIN = 'Wrong login or password.'
    e_FORBIDDEN = 'This account may not copy images (Consultation or Payment is needed).'
    e_NO_PATIENT = 'No patient with this chart number.'
    e_CANCELLED = 'cancelled exam'; e_NO_IMAGES = 'no images'; e_IDENTITY = 'identity warning: settle it in the EMR first'
    e_BUSY = 'being corrected: try again in a few minutes'; e_NOT_ON_SERVER = 'images missing on the image server'
    e_UNREACHABLE = 'The image server does not answer. Try again in a moment.'
    e_NOT_PAIRED = 'The image server is not linked to the EMR. Tell the administrator.'
    e_NOT_LOGGED = 'The change log could not be written: nothing was copied.'
    e_OTHER_PATIENT = 'The exams are not of the same patient.'; e_TOO_MANY_EXAMS = 'Too many exams at a time.'
    e_BROKEN = 'The connection was cut while fetching. Nothing was copied; start again.'
    e_BAD_BUNDLE = 'The images received are incomplete. Nothing was copied; start again.'
    e_NO_ROOM = 'Not enough room there: {0} needed, {1} left.'
    e_NO_FOLDER = 'This folder does not exist.'; e_WRITE_FAILED = 'The copy failed: {0}'
    e_NOT_VERIFIED = "The copy was read back and differs from the original ({0} file(s)).`nDelete the folder {1} and start again."
    e_EXISTS = 'This file already exists. Choose another name.'
    e_ISO = 'The ISO file could not be written: {0}'
    e_other = 'Error: {0}'
    male = 'M'; female = 'F'
  }
}

$script:Cdx = @{ Lang = 'fr'; T = $CdxText.fr; ConfigPath = ''; Config = $null; Patient = $null; Exams = @(); Busy = $false; Burner = $null; Form = $null; Viewer = $null }
$script:Ui = @{}

function CdxT([string]$Key) { $v = $script:Cdx.T[$Key]; if ($null -eq $v) { return $Key }; return $v }
# The words for a refusal: by its code, and the reason as it came when the code is unknown.
function Get-CdxError($Code, $Detail = '', $A = '', $B = '') {
  $v = $script:Cdx.T['e_' + $Code]
  if ($null -eq $v) { return ((CdxT 'e_other') -f ("$Code $Detail").Trim()) }
  return ($v -f $A, $B)
}
function Get-CdxUnit { if ($script:Cdx.Lang -eq 'fr') { return 'Mo' } else { return 'MB' } }

# What is asked of the person at the window - one place, so that a test can answer for them.
function Show-CdxMessage([string]$Text, [string]$Kind = 'info') {
  $icon = switch ($Kind) { 'error' { [Windows.Forms.MessageBoxIcon]::Error } 'warn' { [Windows.Forms.MessageBoxIcon]::Warning } default { [Windows.Forms.MessageBoxIcon]::Information } }
  [void][Windows.Forms.MessageBox]::Show($script:Cdx.Form, $Text, (CdxT 'title'), [Windows.Forms.MessageBoxButtons]::OK, $icon)
}
function Confirm-Cdx([string]$Text) {
  return ([Windows.Forms.MessageBox]::Show($script:Cdx.Form, $Text, (CdxT 'title'), [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question, [Windows.Forms.MessageBoxDefaultButton]::Button2) -eq [Windows.Forms.DialogResult]::Yes)
}
function Select-CdxFolder([string]$Start) {
  $d = New-Object Windows.Forms.FolderBrowserDialog
  $d.Description = CdxT 'askFolder'; $d.ShowNewFolderButton = $true
  if ($Start -and (Test-Path -LiteralPath $Start)) { $d.SelectedPath = $Start }
  if ($d.ShowDialog($script:Cdx.Form) -eq [Windows.Forms.DialogResult]::OK) { return $d.SelectedPath }
  return ''
}
function Select-CdxIsoFile([string]$Name) {
  $d = New-Object Windows.Forms.SaveFileDialog
  $d.Filter = 'ISO (*.iso)|*.iso'; $d.FileName = $Name; $d.OverwritePrompt = $false
  if ($script:Cdx.Config.last_folder -and (Test-Path -LiteralPath $script:Cdx.Config.last_folder)) { $d.InitialDirectory = $script:Cdx.Config.last_folder }
  if ($d.ShowDialog($script:Cdx.Form) -eq [Windows.Forms.DialogResult]::OK) { return $d.FileName }
  return ''
}

function Set-CdxStatus([string]$Text, [int]$Percent = -1) {
  $script:Ui.Status.Text = $Text
  if ($Percent -lt 0) { $script:Ui.Progress.Style = 'Marquee' } else { $script:Ui.Progress.Style = 'Continuous'; $script:Ui.Progress.Value = [Math]::Max(0, [Math]::Min(100, $Percent)) }
  [Windows.Forms.Application]::DoEvents()
}
function Set-CdxBusy([bool]$On) {
  $script:Cdx.Busy = $On
  foreach ($c in 'Chart', 'Search', 'Grid', 'Burn', 'Iso', 'Folder', 'SignOut', 'Viewer') { $script:Ui[$c].Enabled = -not $On }
  $script:Ui.Progress.Visible = $On
  if (-not $On) { $script:Ui.Status.Text = ''; $script:Ui.Progress.Style = 'Continuous'; $script:Ui.Progress.Value = 0; Update-CdxSelection }
  [Windows.Forms.Application]::DoEvents()
}

# ── signing in and out ───────────────────────────────────────────────────────
function Invoke-CdxLogin {
  $url = $script:Ui.Url.Text.Trim()
  $script:Ui.LoginMsg.Text = ''; $script:Ui.SignIn.Enabled = $false
  [Windows.Forms.Application]::DoEvents()
  $r = Connect-Emr $url $script:Ui.Login.Text.Trim() $script:Ui.Password.Text
  $script:Ui.Password.Text = ''                          # the password is not kept, even in its box
  $script:Ui.SignIn.Enabled = $true
  if (-not $r.ok) { $script:Ui.LoginMsg.Text = Get-CdxError $r.code $r.error; return $false }
  if ($script:Cdx.Config.emr_url -ne $url) { $script:Cdx.Config.emr_url = $url; Save-ExportConfig $script:Cdx.ConfigPath $script:Cdx.Config }
  $script:Ui.Who.Text = (CdxT 'connected') -f [string]$r.user.name
  $script:Ui.LoginPanel.Visible = $false; $script:Ui.MainPanel.Visible = $true
  Clear-CdxPatient
  $script:Ui.Chart.Focus() | Out-Null
  Update-CdxDrive
  return $true
}
function Invoke-CdxLogout([string]$Message = '') {
  Disconnect-Emr
  Clear-CdxPatient
  $script:Ui.MainPanel.Visible = $false; $script:Ui.LoginPanel.Visible = $true
  $script:Ui.LoginMsg.Text = $Message
  $script:Ui.Login.Focus() | Out-Null
}

# ── the patient and the exams ────────────────────────────────────────────────
function Clear-CdxPatient {
  $script:Cdx.Patient = $null; $script:Cdx.Exams = @()
  $script:Ui.Chart.Text = ''; $script:Ui.PatientLine.Text = CdxT 'noPatientYet'; $script:Ui.PatientLine.ForeColor = [Drawing.Color]::DimGray
  $script:Ui.Grid.Rows.Clear()
  Update-CdxSelection
}
function Invoke-CdxSearch {
  $chart = $script:Ui.Chart.Text.Trim()
  if (-not $chart) { return $false }
  $script:Ui.Search.Enabled = $false; [Windows.Forms.Application]::DoEvents()
  $r = Get-ExportPatient $chart
  $script:Ui.Search.Enabled = $true
  if (-not $r.ok) {
    if ($r.code -eq 'LOGIN') { Invoke-CdxLogout (CdxT 'expired'); return $false }
    $script:Cdx.Patient = $null; $script:Cdx.Exams = @(); $script:Ui.Grid.Rows.Clear()
    $script:Ui.PatientLine.Text = Get-CdxError $r.code $r.error; $script:Ui.PatientLine.ForeColor = [Drawing.Color]::Firebrick
    Update-CdxSelection
    return $false
  }
  $p = $r.data.patient
  $script:Cdx.Patient = $r.data; $script:Cdx.Exams = @($r.data.exams)
  $sex = switch ([string]$p.gender) { 'M' { CdxT 'male' } 'F' { CdxT 'female' } default { '' } }
  $script:Ui.PatientLine.Text = ((CdxT 'patient') -f ((([string]$p.last_name) + ' ' + ([string]$p.first_name)).Trim() + '  ·  ' + [string]$p.chart_no), [string]$p.date_of_birth, $sex).TrimEnd(' ', '—')
  $script:Ui.PatientLine.ForeColor = [Drawing.Color]::Black
  $grid = $script:Ui.Grid
  $grid.Rows.Clear()
  foreach ($e in $script:Cdx.Exams) {
    $blocked = [string]$e.block
    $state = ''
    if ($blocked) { $state = Get-CdxError $blocked }
    $size = ''; $items = ''
    if (-not $blocked) { $size = Format-Size ([long]$e.bytes) (Get-CdxUnit); $items = [string]$e.items }
    $i = $grid.Rows.Add($false, [string]$e.exam_date, [string]$e.modality, [string]$e.order_name, $items, $size, $state)
    $row = $grid.Rows[$i]; $row.Tag = $e
    if ($blocked) { $row.Cells[0].ReadOnly = $true; $row.DefaultCellStyle.ForeColor = [Drawing.Color]::Gray; $row.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::Gray }
  }
  if ($r.data.server) { $script:Ui.PatientLine.Text += '   —   ' + (Get-CdxError $r.data.server); $script:Ui.PatientLine.ForeColor = [Drawing.Color]::Firebrick }
  Update-CdxSelection
  return $true
}
# The viewer goes on the disc: there is one beside the program and its box is ticked.
function Test-CdxViewer { return ($null -ne $script:Cdx.Viewer -and $script:Ui.Viewer.Checked) }
function Get-CdxChosen {
  $out = New-Object Collections.Generic.List[object]
  foreach ($row in $script:Ui.Grid.Rows) { if ($row.Cells[0].Value -eq $true -and $row.Tag -and -not [string]$row.Tag.block) { $out.Add($row.Tag) } }
  return , $out.ToArray()
}
# The line under the list, the line about the drive, and which buttons can be pressed.
function Update-CdxSelection {
  $sel = Get-CdxChosen
  $bytes = [long]0; $items = 0
  foreach ($e in $sel) { $bytes += [long]$e.bytes; $items += [int]$e.items }
  $script:Cdx.Need = Get-DiscEstimate $bytes ($items + 2)
  if (Test-CdxViewer) { $script:Cdx.Need += $script:Cdx.Viewer.bytes + ($script:Cdx.Viewer.files + 200) * 2048 }
  if ($sel.Count) { $script:Ui.Selection.Text = (CdxT 'sel') -f $sel.Count, $items, (Format-Size $bytes (Get-CdxUnit)) } else { $script:Ui.Selection.Text = CdxT 'selNone' }
  $b = $script:Cdx.Burner
  $line = CdxT 'noBurner'; $canBurn = $false
  if ($b) {
    switch ($b.state) {
      'none'  { $line = (CdxT 'noDisc') -f $b.letter }
      'used'  { $line = (CdxT 'discUsed') -f $b.letter }
      'other' { $line = (CdxT 'discOther') -f $b.letter }
      'blank' {
        $line = (CdxT 'discBlank') -f $b.letter, $b.media, (Format-Size $b.freeBytes (Get-CdxUnit))
        if ($sel.Count) {
          if ($script:Cdx.Need -le $b.freeBytes) { $line += CdxT 'fits'; $canBurn = $true }
          else { $line += (CdxT 'tooBig') -f (Format-Size ($script:Cdx.Need - $b.freeBytes) (Get-CdxUnit)) }
        }
      }
    }
  }
  $script:Ui.Drive.Text = $line
  if (-not $script:Cdx.Busy) {
    $script:Ui.Burn.Enabled = $canBurn
    $script:Ui.Iso.Enabled = $sel.Count -gt 0
    $script:Ui.Folder.Enabled = $sel.Count -gt 0
  }
}
# Looked at every two seconds while nothing is being copied: a disc put in is seen by itself.
function Update-CdxDrive {
  if ($script:Cdx.Busy) { return }
  $all = Get-Burners
  $pick = $null
  foreach ($b in $all) { if ($b.state -eq 'blank') { $pick = $b; break } }
  if (-not $pick -and $all.Count) { $pick = $all[0] }
  $script:Cdx.Burner = $pick
  Update-CdxSelection
}

# ── the copy ─────────────────────────────────────────────────────────────────
function Wait-CdxJob($Job, [string]$Key) {
  $t0 = Get-Date
  while ($Job.State -eq 1) {
    if ($Job.Step -eq 'image' -or $Job.TotalBytes -le 0) { Set-CdxStatus (CdxT 'stImage') -1 }
    else {
      $pct = [int](100 * $Job.DoneBytes / $Job.TotalBytes)
      $el = (Get-Date) - $t0
      Set-CdxStatus ((CdxT $Key) -f $pct, ('{0:00}:{1:00}' -f [int][Math]::Floor($el.TotalMinutes), $el.Seconds)) $pct
    }
    Start-Sleep -Milliseconds 150
  }
}
# -Medium folder | iso | disc. -Target: the base folder or the .iso path (asked when empty).
# Returns @{ ok; code; path }.
function Invoke-CdxExport {
  param([string]$Medium, [string]$Target = '')
  $sel = Get-CdxChosen
  if (-not $sel.Count -or $script:Cdx.Busy) { return @{ ok = $false; code = 'NOTHING' } }
  $max = [int]$script:Cdx.Patient.max_exams
  if ($max -gt 0 -and $sel.Count -gt $max) { Show-CdxMessage ((CdxT 'selMax') -f $max) 'warn'; return @{ ok = $false; code = 'TOO_MANY_EXAMS' } }
  $p = $script:Cdx.Patient.patient
  $name = (([string]$p.last_name) + ' ' + ([string]$p.first_name)).Trim()
  $stamp = '{0}_{1}' -f (Get-SafeName ([string]$p.chart_no)), (Get-Date -Format 'yyyyMMdd_HHmm')
  $bytes = [long]0; foreach ($e in $sel) { $bytes += [long]$e.bytes }
  $burner = $script:Cdx.Burner

  switch ($Medium) {
    'folder' { if (-not $Target) { $Target = Select-CdxFolder $script:Cdx.Config.last_folder }; if (-not $Target) { return @{ ok = $false; code = 'CANCELLED_BY_USER' } } }
    'iso' {
      if (-not $Target) { $Target = Select-CdxIsoFile ($stamp + '.iso') }
      if (-not $Target) { return @{ ok = $false; code = 'CANCELLED_BY_USER' } }
      if (Test-Path -LiteralPath $Target) { Show-CdxMessage (Get-CdxError 'EXISTS') 'warn'; return @{ ok = $false; code = 'EXISTS' } }
    }
    'disc' {
      if (-not $burner -or $burner.state -ne 'blank' -or $script:Cdx.Need -gt $burner.freeBytes) { Update-CdxSelection; return @{ ok = $false; code = 'NO_DISC' } }
      if (-not (Confirm-Cdx ((CdxT 'askBurn') -f $sel.Count, (Format-Size $bytes (Get-CdxUnit)), $name, $burner.letter))) { return @{ ok = $false; code = 'CANCELLED_BY_USER' } }
    }
    default { return @{ ok = $false; code = 'BAD_MEDIUM' } }
  }

  $unit = Get-CdxUnit
  Set-CdxBusy $true
  $work = New-ExportTemp
  try {
    Set-CdxStatus ((CdxT 'stFetch') -f '') -1
    $b = Get-ExportBundle -OrderItemIds @($sel | ForEach-Object { [int]$_.id }) -Medium $Medium -Work $work -OnBytes { param($n) Set-CdxStatus ((CdxT 'stFetch') -f (Format-Size $n $unit)) -1 }
    if (-not $b.ok) {
      if ($b.code -eq 'LOGIN') { Set-CdxBusy $false; Invoke-CdxLogout (CdxT 'expired'); return @{ ok = $false; code = 'LOGIN' } }
      Show-CdxMessage (Get-CdxError $b.code $b.error) 'error'
      return @{ ok = $false; code = $b.code }
    }
    Set-CdxStatus (CdxT 'stReadme') -1
    $withViewer = Test-CdxViewer
    Write-DiscReadme -Dir $b.dir -Patient $p -Clinic $script:Cdx.Patient.clinic -Exams $sel -WithViewer $withViewer
    if ($withViewer) { [void](Add-DiscViewer -Dir $b.dir -ViewerDir $script:Cdx.Viewer.dir -OnFile { param($n, $of) Set-CdxStatus ((CdxT 'stViewer') -f $n, $of) ([int](100 * $n / $of)) }) }
    $fs = Get-DiscFileSystems $withViewer
    $label = Get-DiscLabel ([string]$p.chart_no)

    if ($Medium -eq 'folder') {
      $r = Save-DiscToFolder -Dir $b.dir -Base $Target -Name $stamp -OnFile { param($n, $of) Set-CdxStatus ((CdxT 'stCopy') -f $n, $of) ([int](100 * $n / $of)) }
      if (-not $r.ok) {
        $msg = switch ($r.code) {
          'NO_ROOM' { Get-CdxError 'NO_ROOM' '' (Format-Size $r.need $unit) (Format-Size $r.free $unit) }
          'NOT_VERIFIED' { Get-CdxError 'NOT_VERIFIED' '' $r.bad.Count $r.path }
          'WRITE_FAILED' { Get-CdxError 'WRITE_FAILED' '' $r.error }
          default { Get-CdxError $r.code }
        }
        Show-CdxMessage $msg 'error'
        return @{ ok = $false; code = $r.code; path = $r.path }
      }
      $script:Cdx.Config.last_folder = $Target; Save-ExportConfig $script:Cdx.ConfigPath $script:Cdx.Config
      Set-CdxBusy $false
      Show-CdxMessage ((CdxT 'doneFolder') -f $r.path, $r.files, (Format-Size $r.bytes $unit))
      return @{ ok = $true; path = $r.path }
    }

    if ($Medium -eq 'iso') {
      $job = New-Object Bethesda.DiscJob
      $job.StartIso($b.dir, $label, $fs, $Target)
      Wait-CdxJob $job 'stIso'
      if ($job.State -ne 2) {
        if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue }   # a half-written image is not left behind
        Show-CdxMessage (Get-CdxError 'ISO' '' $job.Error) 'error'
        return @{ ok = $false; code = 'ISO' }
      }
      $script:Cdx.Config.last_folder = Split-Path -Parent $Target; Save-ExportConfig $script:Cdx.ConfigPath $script:Cdx.Config
      Set-CdxBusy $false
      Show-CdxMessage ((CdxT 'doneIso') -f $Target, (Format-Size (Get-Item -LiteralPath $Target).Length $unit))
      return @{ ok = $true; path = $Target }
    }

    # the disc in the drive
    $files = Get-DiscFiles $b.dir
    $job = New-Object Bethesda.DiscJob
    $job.StartBurn($b.dir, $label, $fs, $burner.id, 'BethesdaCdExport', $false)
    Wait-CdxJob $job 'stBurn'
    if ($job.State -ne 2) {
      Open-DiscTray $burner.id
      Show-CdxMessage ((CdxT 'badBurn') -f $job.Error) 'error'
      return @{ ok = $false; code = 'BURN'; error = $job.Error }
    }
    Set-CdxStatus (CdxT 'stCheck') -1
    $v = Test-BurnedDisc $burner.letter $files 45 { [Windows.Forms.Application]::DoEvents() }
    Open-DiscTray $burner.id
    Set-CdxBusy $false
    if ($v.result -eq 'different') { Show-CdxMessage ((CdxT 'badVerify') -f $v.bad.Count) 'error'; return @{ ok = $false; code = 'VERIFY' } }
    if ($v.result -eq 'same') { Show-CdxMessage (CdxT 'doneBurn'); return @{ ok = $true; verified = 'read' } }
    if ($job.CheckedByBurner) { Show-CdxMessage (CdxT 'doneBurnDrive'); return @{ ok = $true; verified = 'burner' } }
    Show-CdxMessage (CdxT 'doneBurnUnread') 'warn'
    return @{ ok = $true; verified = 'no' }
  }
  catch { Show-CdxMessage ((CdxT 'e_other') -f $_.Exception.Message) 'error'; return @{ ok = $false; code = 'ERROR'; error = $_.Exception.Message } }
  finally {
    [void](Remove-ExportTemp $work)                      # what was fetched does not stay on this PC
    if ($script:Cdx.Busy) { Set-CdxBusy $false }
    Update-CdxDrive
  }
}

# ── the window ───────────────────────────────────────────────────────────────
function New-CdxForm([string]$Lang, [string]$ConfigPath, [string]$ViewerDir = '') {
  if (-not $CdxText.ContainsKey($Lang)) { $Lang = 'fr' }
  $script:Cdx.Lang = $Lang; $script:Cdx.T = $CdxText[$Lang]
  $script:Cdx.ConfigPath = $ConfigPath; $script:Cdx.Config = Read-ExportConfig $ConfigPath
  $script:Cdx.Viewer = Get-ViewerInfo $ViewerDir          # $null when no viewer is beside the program
  [Windows.Forms.Application]::EnableVisualStyles()
  $font = New-Object Drawing.Font('Segoe UI', 10)
  $bold = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)

  $form = New-Object Windows.Forms.Form
  $form.Text = CdxT 'title'; $form.Font = $font; $form.StartPosition = 'CenterScreen'
  $form.ClientSize = New-Object Drawing.Size(900, 620); $form.MinimumSize = New-Object Drawing.Size(760, 520)
  $script:Cdx.Form = $form

  # sign-in
  $lp = New-Object Windows.Forms.Panel; $lp.Dock = 'Fill'
  $mk = {
    param($text, $y)
    $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object Drawing.Point(250, ($y + 3)); $l.Size = New-Object Drawing.Size(140, 24)
    $t = New-Object Windows.Forms.TextBox; $t.Location = New-Object Drawing.Point(395, $y); $t.Size = New-Object Drawing.Size(260, 26)
    $lp.Controls.Add($l); $lp.Controls.Add($t); $t
  }
  $hint = New-Object Windows.Forms.Label; $hint.Text = CdxT 'loginHint'; $hint.Location = New-Object Drawing.Point(250, 150); $hint.Size = New-Object Drawing.Size(520, 24); $hint.Font = $bold
  $lp.Controls.Add($hint)
  $url = & $mk (CdxT 'emrUrl') 190; $url.Text = $script:Cdx.Config.emr_url
  $login = & $mk (CdxT 'login') 226
  $pw = & $mk (CdxT 'password') 262; $pw.UseSystemPasswordChar = $true
  $signIn = New-Object Windows.Forms.Button; $signIn.Text = CdxT 'signIn'; $signIn.Location = New-Object Drawing.Point(395, 302); $signIn.Size = New-Object Drawing.Size(160, 32)
  $lmsg = New-Object Windows.Forms.Label; $lmsg.Location = New-Object Drawing.Point(250, 346); $lmsg.Size = New-Object Drawing.Size(560, 60); $lmsg.ForeColor = [Drawing.Color]::Firebrick
  $lp.Controls.Add($signIn); $lp.Controls.Add($lmsg)
  $signIn.Add_Click({ [void](Invoke-CdxLogin) })
  $pw.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; [void](Invoke-CdxLogin) } })

  # the main panel
  # The panel has the window's size before anything is put on it: what is anchored to its
  # right and bottom edges keeps its place from there.
  $mp = New-Object Windows.Forms.Panel; $mp.Size = $form.ClientSize; $mp.Dock = 'Fill'; $mp.Visible = $false
  $who = New-Object Windows.Forms.Label; $who.Location = New-Object Drawing.Point(14, 14); $who.Size = New-Object Drawing.Size(600, 24)
  $signOut = New-Object Windows.Forms.Button; $signOut.Text = CdxT 'signOut'; $signOut.Size = New-Object Drawing.Size(150, 28); $signOut.Location = New-Object Drawing.Point(736, 10); $signOut.Anchor = 'Top, Right'
  $cl = New-Object Windows.Forms.Label; $cl.Text = CdxT 'chart'; $cl.Location = New-Object Drawing.Point(14, 52); $cl.Size = New-Object Drawing.Size(96, 24)
  $chart = New-Object Windows.Forms.TextBox; $chart.Location = New-Object Drawing.Point(112, 49); $chart.Size = New-Object Drawing.Size(150, 26)
  $search = New-Object Windows.Forms.Button; $search.Text = CdxT 'search'; $search.Location = New-Object Drawing.Point(270, 47); $search.Size = New-Object Drawing.Size(110, 29)
  $pl = New-Object Windows.Forms.Label; $pl.Location = New-Object Drawing.Point(14, 86); $pl.Size = New-Object Drawing.Size(872, 24); $pl.Font = $bold; $pl.Anchor = 'Top, Left, Right'; $pl.AutoEllipsis = $true

  $grid = New-Object Windows.Forms.DataGridView
  $grid.Location = New-Object Drawing.Point(14, 116); $grid.Size = New-Object Drawing.Size(872, 306); $grid.Anchor = 'Top, Bottom, Left, Right'
  $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.AllowUserToResizeRows = $false; $grid.RowHeadersVisible = $false
  $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $false; $grid.BackgroundColor = [Drawing.Color]::White; $grid.AutoSizeColumnsMode = 'Fill'
  # the line the cursor is on is tinted, not painted over: what counts is the tick
  $grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(226, 236, 250); $grid.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::Black
  $c0 = New-Object Windows.Forms.DataGridViewCheckBoxColumn; $c0.HeaderText = ''; $c0.FillWeight = 6
  [void]$grid.Columns.Add($c0)
  foreach ($col in @(@('colDate', 16), @('colType', 9), @('colExam', 40), @('colImages', 11), @('colSize', 13), @('colState', 34))) {
    $c = New-Object Windows.Forms.DataGridViewTextBoxColumn; $c.HeaderText = CdxT $col[0]; $c.FillWeight = $col[1]; $c.ReadOnly = $true; $c.SortMode = 'NotSortable'
    [void]$grid.Columns.Add($c)
  }
  # a tick counts at once, not when the row is left; a click anywhere on the line ticks it
  $grid.Add_CurrentCellDirtyStateChanged({ if ($script:Ui.Grid.IsCurrentCellDirty) { $script:Ui.Grid.CommitEdit('CurrentCellChange') } })
  $grid.Add_CellValueChanged({ Update-CdxSelection })
  $grid.Add_CellClick({ param($s, $e)
    if ($e.RowIndex -ge 0 -and $e.ColumnIndex -gt 0) { $cell = $script:Ui.Grid.Rows[$e.RowIndex].Cells[0]; if (-not $cell.ReadOnly) { $cell.Value = -not ($cell.Value -eq $true) } } })

  $selLine = New-Object Windows.Forms.Label; $selLine.Location = New-Object Drawing.Point(14, 430); $selLine.Size = New-Object Drawing.Size(872, 24); $selLine.Anchor = 'Bottom, Left, Right'; $selLine.Font = $bold
  $drive = New-Object Windows.Forms.Label; $drive.Location = New-Object Drawing.Point(14, 456); $drive.Size = New-Object Drawing.Size(872, 24); $drive.Anchor = 'Bottom, Left, Right'; $drive.AutoEllipsis = $true
  # offered only when the viewer's folder is beside the program; unticked each time the program starts
  $viewer = New-Object Windows.Forms.CheckBox; $viewer.Location = New-Object Drawing.Point(16, 482); $viewer.Size = New-Object Drawing.Size(860, 24); $viewer.Anchor = 'Bottom, Left'
  $viewer.Visible = ($null -ne $script:Cdx.Viewer)
  if ($script:Cdx.Viewer) { $viewer.Text = (CdxT 'viewer') -f (Format-Size $script:Cdx.Viewer.bytes (Get-CdxUnit)) }
  $viewer.Add_CheckedChanged({ Update-CdxSelection })
  $mkb = { param($text, $x, $w) $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object Drawing.Point($x, 512); $b.Size = New-Object Drawing.Size($w, 36); $b.Anchor = 'Bottom, Left'; $b }
  $burn = & $mkb (CdxT 'burn') 14 190; $burn.Font = $bold
  $iso = & $mkb (CdxT 'iso') 214 250
  $folder = & $mkb (CdxT 'folder') 474 270
  $prog = New-Object Windows.Forms.ProgressBar; $prog.Location = New-Object Drawing.Point(14, 562); $prog.Size = New-Object Drawing.Size(300, 20); $prog.Anchor = 'Bottom, Left'; $prog.Visible = $false; $prog.MarqueeAnimationSpeed = 30
  $status = New-Object Windows.Forms.Label; $status.Location = New-Object Drawing.Point(324, 561); $status.Size = New-Object Drawing.Size(562, 24); $status.Anchor = 'Bottom, Left, Right'
  $mp.Controls.AddRange(@($who, $signOut, $cl, $chart, $search, $pl, $grid, $selLine, $drive, $viewer, $burn, $iso, $folder, $prog, $status))

  $signOut.Add_Click({ Invoke-CdxLogout })
  $search.Add_Click({ [void](Invoke-CdxSearch) })
  $chart.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; [void](Invoke-CdxSearch) } })
  $burn.Add_Click({ [void](Invoke-CdxExport -Medium disc) })
  $iso.Add_Click({ [void](Invoke-CdxExport -Medium iso) })
  $folder.Add_Click({ [void](Invoke-CdxExport -Medium folder) })

  $form.Controls.Add($mp); $form.Controls.Add($lp)
  $script:Ui = @{ LoginPanel = $lp; MainPanel = $mp; Url = $url; Login = $login; Password = $pw; SignIn = $signIn; LoginMsg = $lmsg
    Who = $who; SignOut = $signOut; Chart = $chart; Search = $search; PatientLine = $pl; Grid = $grid; Selection = $selLine; Drive = $drive
    Burn = $burn; Iso = $iso; Folder = $folder; Progress = $prog; Status = $status; Viewer = $viewer }

  $timer = New-Object Windows.Forms.Timer; $timer.Interval = 2000
  $timer.Add_Tick({ if ($script:Ui.MainPanel.Visible) { Update-CdxDrive } })
  $script:Ui.Timer = $timer
  $form.Add_Shown({ $script:Ui.Timer.Start(); if ($script:Ui.Url.Text) { $script:Ui.Login.Focus() | Out-Null } })
  $form.Add_FormClosing({ param($s, $e)
    if ($script:Cdx.Busy) { $e.Cancel = $true; Show-CdxMessage (CdxT 'busyClose') 'warn'; return }
    $script:Ui.Timer.Stop(); Disconnect-Emr; [void](Remove-ExportTemp) })
  Clear-CdxPatient
  return $form
}
