# Watch the imaging devices talk to this PACS, in plain words (Windows, server PC).
#
# For the day the devices are connected on site: leave this running on the
# server PC while the settings are tried on the device, and it says what the
# PACS sees - a device connecting, asking for its worklist (and why the list is
# empty), sending images (and whether they match an EMR order), or connecting
# and leaving without sending anything.
#
#   .\device-watch.ps1                 watch (Korean)
#   .\device-watch.ps1 -Lang fr        in French (-Lang en: English)
#   .\device-watch.ps1 -Detail         also see connections and worklist queries (see below)
#   .\device-watch.ps1 -Ping 192.168.1.50 [-DevicePort 104] [-DeviceAet XRAY01]
#                                      can this PC reach that device? (ping, port, DICOM echo)
#   .\device-watch.ps1 -Reset         put Orthanc's log level back (if a -Detail window was
#                                      closed with its X instead of Ctrl+C)
#
# What it reads (it changes nothing unless -Detail is given):
#  - Orthanc's change log (REST /changes): every image received, with the
#    sending device's AE and IP and the compression, at any log level;
#  - Orthanc's own log (docker logs): connections, echo, worklist queries - but
#    Orthanc writes those only at the "verbose" log level;
#  - the worklist files (through the bridge container) and the EMR's worklist
#    table (docker exec psql, read only) to explain an empty list and to match
#    received images to orders.
#
# -Detail raises Orthanc's log level for the categories "generic", "dicom" and
# "plugins" (REST /tools/log-level-*, not "http"), says so, and puts the
# previous levels back when this window is closed with Ctrl+C. Orthanc also goes
# back to its configured level by itself when it restarts. Nothing is written to
# Orthanc's configuration.
param(
  [ValidateSet('ko', 'fr', 'en')][string]$Lang = 'ko',
  [switch]$Detail,
  [switch]$Reset,
  [string]$Ping = '',
  [int]$DevicePort = 0,
  [string]$DeviceAet = '',
  [string]$OrthancUrl = 'http://localhost:9090',
  [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
  [string]$OrthancContainer = 'bethesda-pacs',
  [string]$BridgeContainer = 'bethesda-worklist-bridge',
  [string]$EmrDbContainer = 'bethesda-emr-db',
  [string]$ServerAet = 'MEDCONNECT',
  [int]$Seconds = 0                    # tests: stop after this many seconds (0 = until Ctrl+C)
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# ── words ────────────────────────────────────────────────────────────────────
$T = @{
  ko = @{
    start        = '장비 연결 지켜보기 — 서버 {0} (AE {1}). 끝내려면 Ctrl+C.'
    noOrthanc    = '영상 서버(Orthanc)에 닿지 않습니다: {0}. PACS가 켜져 있는지 보세요.'
    noPassword   = '.env에 ORTHANC_PASSWORD가 없습니다 — PACS 폴더에서 실행하세요.'
    quiet        = '※ 지금은 영상 받음만 보입니다. 장비의 연결·목록 조회까지 보려면 이 창을 닫고 「device-watch.ps1 -Detail」로 다시 여세요.'
    detailOn     = '※ 자세히 보기: 영상 서버의 기록을 잠시 자세히 합니다(generic·dicom·plugins). 끝낼 때는 Ctrl+C로 — 그러면 원래대로 돌아갑니다. 창의 X로 닫았다면 「device-watch.ps1 -Reset」을 한 번 실행하세요.'
    resetDone    = '영상 서버 기록을 보통으로 되돌렸습니다 (generic·dicom·plugins = default).'
    detailOff    = '자세히 보기를 끄고 영상 서버 기록을 원래대로 되돌렸습니다.'
    detailStuck  = '자세히 보기를 되돌리지 못했습니다 — 영상 서버를 다시 시작하면 원래대로 돌아갑니다: docker restart {0}'
    waiting      = '기다리는 중 — 아직 아무 장비도 연결하지 않음'
    waitingSince = '기다리는 중 — 마지막 연결 {0}'
    connect      = '장비가 연결함 — AE: {0}, 주소 {1}'
    calledWrong  = '  ↳ 장비가 서버 이름(AE)을 「{0}」로 부름 — 맞는 이름은 {1}. 지금은 받아 주지만 장비 설정에서 고쳐 두세요.'
    echo         = '장비가 연결 시험(C-ECHO)을 함 — AE: {0} → 응답함 (연결은 됨)'
    wlAsk        = '장비가 목록을 물어봄(워크리스트) — AE: {0}{1}'
    wlFilter     = ' · 조건: {0}'
    wlAnswer     = '  → {0}명 보냄'
    wlZero       = '  → 0명 — {0}'
    whyNone      = '지금 서버에 오늘 목록이 하나도 없음. EMR에서 오늘 영상 검사를 냈는지, 브리지가 EMR에 닿는지 보세요.'
    whyStation   = '장비가 「{0}」 앞으로 온 검사만 물음. EMR 오더에는 장비 이름이 없어 0명 → 장비 설정에서 「내 AE만 / Station AE 거르기」를 끄세요.'
    whyModality  = '장비가 {0} 검사만 물음. 지금 목록: {1}'
    whyDate      = '장비가 날짜 {0}의 검사를 물음(오늘 {1}). 장비의 날짜·시계를 보세요.'
    whyOther     = '조건에 맞는 검사가 없음. 지금 목록: {0}'
    listEmpty    = '없음'
    store        = '장비가 영상을 보냄 — AE: {0}'
    received     = '영상 받음 — {0}장 · 보낸 곳 {1} ({2}) · 환자번호 {3} · 검사번호 {4}{5}'
    corrected    = '영상 {0}장 — EMR에서 다른 오더로 옮긴 영상(장비가 보낸 것이 아님) · 환자번호 {1} · 검사번호 {2}'
    compressed   = ' · 압축 전송({0})'
    privateType  = '  ↳ 제조사 전용 영상 종류({0}) — 서버에 저장했지만 영상 창에서는 안 보일 수 있습니다.'
    noPixels     = '  ↳ 그림이 없는 자료 {0}개(보고서·측정값·원자료 등) — 서버에 저장했지만 영상 창에는 그림이 없습니다.'
    noPid        = '(없음)'
    matched      = '  ↳ EMR 오더와 연결됨: {0} — {1} {2}'
    pidOk        = '  ↳ 환자번호 맞음'
    pidDiffers   = '  ↳ 환자번호가 다름 — 영상 {0}, 오더 {1}. EMR에 빨간 경고가 뜹니다. 누구를 찍었는지 확인하세요.'
    pidMissing   = '  ↳ 영상에 환자번호가 없음 — EMR에 노란 경고가 뜹니다. 장비에서 환자를 목록에서 골랐는지 보세요.'
    byAccession  = '  ↳ 장비가 제 검사 UID를 씀 — 검사번호 {0}로 오더와 연결될 예정(1~2분). 오더: {1} — {2} {3}'
    noOrder      = '  ↳ 연결할 EMR 오더가 없음 — 목록에서 고르지 않고 장비에 손으로 친 환자일 수 있음(환자번호 {0}). 영상은 서버에 있음.'
    noEmr        = '  ↳ (EMR 데이터베이스 {0}가 이 PC에 없어 오더와 맞춰 보지 못함)'
    recorded     = '  ↳ EMR에 기록됨 — {0}: 「Réalisé」, 영상 창에서 볼 수 있음'
    recordedNoView = '  ↳ EMR에 기록됨 — {0}: 「Réalisé」. 영상 창에 그림이 안 나올 수 있음(눈에 줄 그은 작은 그림) — 위 줄 참고'
    leftEmpty    = '장비가 연결했다가 아무것도 묻거나 보내지 않고 끊음 — AE: {0}. 영상을 보내려 했다면 서버가 그 영상 종류(SOP Class)나 전송 방식을 받지 않았을 수 있습니다 → 안내서 「④ 보냈는데 안 옴」.'
    srvRefused   = '영상 서버가 장비의 연결을 거절함 — 장비의 서버 이름(AE)·주소를 보세요.'
    srvAborted   = '장비와의 연결이 도중에 끊김 — 선·네트워크, 또는 장비가 보내다 멈춤. 장비의 전송 대기 목록을 보세요.'
    srvStorage   = '영상 서버가 받은 영상을 저장하지 못함 — 서버 PC의 디스크 공간을 보세요.'
    srvData      = '영상 서버가 받은 자료를 읽지 못함 — 장비의 전송 방식(압축)·영상 종류 설정을 보세요.'
    srvOther     = '영상 서버가 장비 연결 중에 알림을 남김 — 아래 원문을 사진으로 남겨 두세요.'
    bridgeErr    = '브리지: {0}'
    bridgeNoEmr  = '브리지가 EMR에 닿지 못함 — 장비 목록이 새로 가지 않습니다. EMR이 켜져 있는지 보세요.'
    bridgeNotEmr = '브리지: EMR이 아닌 프로그램이 답함 — 다른 프로그램이 EMR 포트(9080)를 쓰는지 check-windows-ports.ps1로 보세요.'
    pingHead     = '장비까지 닿는지 — {0}'
    pingOk       = '  ping: 응답함 ({0} ms)'
    pingNo       = '  ping: 응답 없음 (장비가 꺼졌거나, 주소가 틀렸거나, 장비가 ping에 답하지 않게 되어 있음)'
    portOk       = '  포트 {0}: 열려 있음'
    portNo       = '  포트 {0}: 닫혀 있음'
    echoOk       = '  DICOM 연결 시험(C-ECHO, AE {0}, 포트 {1}): 응답함'
    echoNo       = '  DICOM 연결 시험(C-ECHO, AE {0}, 포트 {1}): 실패 — {2}'
    echoSkip     = '  DICOM 연결 시험: 장비의 포트를 모름 — -DevicePort 로 알려 주세요(흔한 값 104, 4242, 11112)'
    echoNoAet    = '  (장비의 AE를 모르면 -DeviceAet 로 알려 주세요. 지금은 「{0}」로 시험)'
  }
  fr = @{
    start        = 'Surveillance des appareils — serveur {0} (AE {1}). Ctrl+C pour arrêter.'
    noOrthanc    = "Le serveur d'images (Orthanc) ne répond pas : {0}. Vérifiez que le PACS est démarré."
    noPassword   = "ORTHANC_PASSWORD manque dans .env — lancez ce script depuis le dossier du PACS."
    quiet        = "※ Seules les images reçues s'affichent. Pour voir aussi les connexions et les demandes de liste, fermez cette fenêtre et relancez « device-watch.ps1 -Detail »."
    detailOn     = "※ Mode détaillé : le journal du serveur d'images est rendu plus détaillé (generic, dicom, plugins). Arrêtez avec Ctrl+C pour remettre le réglage d'avant. Si la fenêtre a été fermée avec la croix, lancez une fois « device-watch.ps1 -Reset »."
    resetDone    = "Journal du serveur d'images remis au niveau normal (generic, dicom, plugins = default)."
    detailOff    = "Mode détaillé arrêté ; journal du serveur d'images remis comme avant."
    detailStuck  = "Impossible de remettre le journal comme avant — un redémarrage du serveur d'images le remet : docker restart {0}"
    waiting      = "En attente — aucun appareil ne s'est encore connecté"
    waitingSince = 'En attente — dernière connexion {0}'
    connect      = "Un appareil s'est connecté — AE : {0}, adresse {1}"
    calledWrong  = "  ↳ L'appareil appelle le serveur « {0} » — le bon nom est {1}. Accepté pour l'instant, mais corrigez-le dans l'appareil."
    echo         = "L'appareil fait un test de connexion (C-ECHO) — AE : {0} → réponse OK (la connexion fonctionne)"
    wlAsk        = "L'appareil demande la liste (worklist) — AE : {0}{1}"
    wlFilter     = ' · critères : {0}'
    wlAnswer     = '  → {0} patient(s) envoyé(s)'
    wlZero       = '  → 0 — {0}'
    whyNone      = "Aucune demande du jour sur le serveur. Vérifiez qu'un examen d'imagerie a été demandé aujourd'hui dans l'EMR et que le pont atteint l'EMR."
    whyStation   = "L'appareil ne demande que les examens adressés à « {0} ». Les demandes de l'EMR ne portent pas de nom d'appareil → désactivez le filtre « mon AE seulement / Station AE » dans l'appareil."
    whyModality  = "L'appareil ne demande que les examens {0}. Liste actuelle : {1}"
    whyDate      = "L'appareil demande la date {0} (aujourd'hui {1}). Vérifiez la date et l'heure de l'appareil."
    whyOther     = 'Aucun examen ne correspond. Liste actuelle : {0}'
    listEmpty    = 'vide'
    store        = "L'appareil envoie des images — AE : {0}"
    received     = 'Images reçues — {0} · de {1} ({2}) · N° patient {3} · N° accession {4}{5}'
    corrected    = "{0} image(s) — déplacée(s) sous une autre demande depuis l'EMR (pas envoyée(s) par un appareil) · N° patient {1} · N° accession {2}"
    compressed   = ' · envoi compressé ({0})'
    privateType  = "  ↳ Type d'image propre au fabricant ({0}) — enregistré, mais la Visionneuse peut ne rien afficher."
    noPixels     = "  ↳ {0} objet(s) sans image (rapport, mesures, données brutes…) — enregistré(s), mais rien à afficher dans la Visionneuse."
    noPid        = '(aucun)'
    matched      = "  ↳ Reliées à la demande de l'EMR : {0} — {1} {2}"
    pidOk        = '  ↳ N° patient correct'
    pidDiffers   = "  ↳ N° patient différent — image {0}, demande {1}. L'EMR affichera un cadre rouge. Vérifiez qui a été radiographié."
    pidMissing   = "  ↳ Pas de N° patient dans l'image — l'EMR affichera un cadre jaune. Vérifiez que le patient a été choisi dans la liste."
    byAccession  = "  ↳ L'appareil a donné son propre UID d'étude — liaison par le N° d'accession {0} dans 1 à 2 minutes. Demande : {1} — {2} {3}"
    noOrder      = "  ↳ Aucune demande de l'EMR à relier — patient peut-être tapé à la main sur l'appareil (N° {0}). Les images sont sur le serveur."
    noEmr        = "  ↳ (base de l'EMR {0} absente de ce PC : pas de comparaison avec les demandes)"
    recorded     = "  ↳ Enregistré dans l'EMR — {0} : « Réalisé », visible dans la Visionneuse"
    recordedNoView = "  ↳ Enregistré dans l'EMR — {0} : « Réalisé ». La Visionneuse peut ne rien afficher (petite image d'un œil barré) — voir la ligne plus haut"
    leftEmpty    = "Un appareil s'est connecté puis déconnecté sans rien demander ni envoyer — AE : {0}. S'il voulait envoyer des images, le serveur n'a peut-être pas accepté ce type d'image (SOP Class) ou ce mode d'envoi → guide « ④ envoyé mais rien reçu »."
    srvRefused   = "Le serveur d'images refuse la connexion de l'appareil — vérifiez le nom (AE) et l'adresse du serveur dans l'appareil."
    srvAborted   = "Connexion avec l'appareil coupée en cours — câble, réseau, ou envoi interrompu. Regardez la file d'envoi de l'appareil."
    srvStorage   = "Le serveur d'images n'a pas pu enregistrer les images reçues — vérifiez l'espace disque du PC serveur."
    srvData      = "Le serveur d'images ne peut pas lire les données reçues — vérifiez le mode d'envoi (compression) et le type d'image dans l'appareil."
    srvOther     = "Le serveur d'images a signalé quelque chose pendant la connexion — photographiez le texte ci-dessous."
    bridgeErr    = 'Pont : {0}'
    bridgeNoEmr  = "Le pont n'atteint pas l'EMR — la liste des appareils n'est plus mise à jour. Vérifiez que l'EMR est démarré."
    bridgeNotEmr = "Pont : un autre programme que l'EMR répond — vérifiez avec check-windows-ports.ps1 si un programme utilise le port de l'EMR (9080)."
    pingHead     = "L'appareil est-il joignable — {0}"
    pingOk       = '  ping : répond ({0} ms)'
    pingNo       = "  ping : pas de réponse (appareil éteint, adresse fausse, ou appareil réglé pour ne pas répondre au ping)"
    portOk       = '  port {0} : ouvert'
    portNo       = '  port {0} : fermé'
    echoOk       = '  Test DICOM (C-ECHO, AE {0}, port {1}) : répond'
    echoNo       = '  Test DICOM (C-ECHO, AE {0}, port {1}) : échec — {2}'
    echoSkip     = "  Test DICOM : port de l'appareil inconnu — indiquez-le avec -DevicePort (souvent 104, 4242, 11112)"
    echoNoAet    = "  (AE de l'appareil inconnu : indiquez-le avec -DeviceAet. Test fait avec « {0} »)"
  }
  en = @{
    start        = 'Watching the devices — server {0} (AE {1}). Ctrl+C to stop.'
    noOrthanc    = 'The image server (Orthanc) does not answer: {0}. Check that the PACS is running.'
    noPassword   = 'ORTHANC_PASSWORD is missing from .env — run this from the PACS folder.'
    quiet        = '※ Only received images are shown. To also see connections and worklist queries, close this window and run "device-watch.ps1 -Detail".'
    detailOn     = '※ Detail mode: the image server''s log is made more detailed for now (generic, dicom, plugins). Stop with Ctrl+C to put it back. If the window was closed with its X, run "device-watch.ps1 -Reset" once.'
    resetDone    = "The image server's log is back to normal (generic, dicom, plugins = default)."
    detailOff    = "Detail mode ended; the image server's log is back as it was."
    detailStuck  = 'Could not put the log level back — restarting the image server does: docker restart {0}'
    waiting      = 'Waiting — no device has connected yet'
    waitingSince = 'Waiting — last connection {0}'
    connect      = 'A device connected — AE: {0}, address {1}'
    calledWrong  = '  ↳ The device calls the server "{0}" — the right name is {1}. Accepted for now; correct it on the device.'
    echo         = 'The device ran a connection test (C-ECHO) — AE: {0} → answered (the connection works)'
    wlAsk        = 'The device asked for its worklist — AE: {0}{1}'
    wlFilter     = ' · filter: {0}'
    wlAnswer     = '  → {0} patient(s) sent'
    wlZero       = '  → 0 — {0}'
    whyNone      = "No worklist entry for today on the server. Check that an imaging order was placed today in the EMR, and that the bridge reaches the EMR."
    whyStation   = 'The device only asks for exams addressed to "{0}". EMR orders carry no device name → turn off "my AE only / Station AE filter" on the device.'
    whyModality  = 'The device only asks for {0} exams. Current list: {1}'
    whyDate      = "The device asks for date {0} (today {1}). Check the device's date and clock."
    whyOther     = 'No exam matches. Current list: {0}'
    listEmpty    = 'empty'
    store        = 'The device is sending images — AE: {0}'
    received     = 'Images received — {0} · from {1} ({2}) · patient ID {3} · accession {4}{5}'
    corrected    = '{0} image(s) — put under another order from the EMR (not sent by a device) · patient ID {1} · accession {2}'
    compressed   = ' · compressed ({0})'
    privateType  = '  ↳ Vendor-private image type ({0}) — stored, but the image window may show nothing.'
    noPixels     = '  ↳ {0} object(s) without a picture (report, measurements, raw data…) — stored, but nothing to show in the image window.'
    noPid        = '(none)'
    matched      = '  ↳ Linked to the EMR order: {0} — {1} {2}'
    pidOk        = '  ↳ Patient ID matches'
    pidDiffers   = '  ↳ Patient ID differs — image {0}, order {1}. The EMR will show a red warning. Check who was imaged.'
    pidMissing   = '  ↳ No patient ID in the images — the EMR will show a yellow warning. Check the patient was picked from the worklist.'
    byAccession  = '  ↳ The device made its own study UID — it will be linked by accession {0} in 1-2 minutes. Order: {1} — {2} {3}'
    noOrder      = '  ↳ No EMR order to link to — the patient may have been typed on the device (ID {0}). The images are on the server.'
    noEmr        = '  ↳ (EMR database {0} is not on this PC: no matching with orders)'
    recorded     = '  ↳ Recorded in the EMR — {0}: "Réalisé", visible in the image window'
    recordedNoView = '  ↳ Recorded in the EMR — {0}: "Réalisé". The image window may show nothing (a crossed-out eye) — see the line above'
    leftEmpty    = 'A device connected and left without asking or sending anything — AE: {0}. If it meant to send images, the server may not have accepted that image type (SOP Class) or transfer mode → guide "④ sent but nothing arrives".'
    srvRefused   = "The image server refused the device's connection — check the server name (AE) and address on the device."
    srvAborted   = "The connection with the device broke off — cable, network, or the device stopped sending. Look at the device's send queue."
    srvStorage   = 'The image server could not store the received images — check the disk space on the server PC.'
    srvData      = "The image server could not read what it received — check the device's transfer mode (compression) and image type."
    srvOther     = 'The image server noted something during a device connection — take a photo of the text below.'
    bridgeErr    = 'Bridge: {0}'
    bridgeNoEmr  = 'The bridge cannot reach the EMR — the device worklist is no longer updated. Check that the EMR is running.'
    bridgeNotEmr = 'Bridge: a program other than the EMR answers — run check-windows-ports.ps1 to see if a program uses the EMR port (9080).'
    pingHead     = 'Can this PC reach the device — {0}'
    pingOk       = '  ping: answers ({0} ms)'
    pingNo       = '  ping: no answer (device off, wrong address, or set not to answer ping)'
    portOk       = '  port {0}: open'
    portNo       = '  port {0}: closed'
    echoOk       = '  DICOM test (C-ECHO, AE {0}, port {1}): answers'
    echoNo       = '  DICOM test (C-ECHO, AE {0}, port {1}): failed — {2}'
    echoSkip     = "  DICOM test: the device's port is unknown — give it with -DevicePort (often 104, 4242, 11112)"
    echoNoAet    = '  (Device AE unknown: give it with -DeviceAet. Tested with "{0}")'
  }
}[$Lang]

function Say([string]$text, [string]$color = 'Gray', $when = $null) {
  $script:lastEvent = Get-Date
  $stamp = if ($when) { ([datetime]$when).ToString('HH:mm:ss') } else { (Get-Date).ToString('HH:mm:ss') }
  Write-Host ("$stamp  " + $text) -ForegroundColor $color
}
function Note([string]$text, [string]$color = 'Gray') { Write-Host ("          " + $text) -ForegroundColor $color }

# ── Orthanc REST ─────────────────────────────────────────────────────────────
$envVals = @{}
if (Test-Path $EnvFile) { foreach ($l in Get-Content $EnvFile) { if ($l -match '^\s*([A-Z_][A-Z0-9_]*)\s*=(.*)$') { $envVals[$Matches[1]] = $Matches[2].Trim() } } }
if (-not $envVals['ORTHANC_PASSWORD']) { Write-Host $T.noPassword -ForegroundColor Red; exit 1 }
$auth = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('admin:' + $envVals['ORTHANC_PASSWORD'])) }
function O([string]$method, [string]$path, $body = $null) {
  $req = @{ Method = $method; Uri = ($OrthancUrl.TrimEnd('/') + $path); Headers = $auth; UseBasicParsing = $true; TimeoutSec = 15; ErrorAction = 'Stop' }
  if ($null -ne $body) { $req.Body = $body; $req.ContentType = 'application/json' }
  return Invoke-RestMethod @req
}
try { $null = O GET '/system' } catch { Write-Host ($T.noOrthanc -f $_.Exception.Message) -ForegroundColor Red; exit 1 }

# ── -Reset: the log level back to normal ──────────────────────────────────────
if ($Reset) {
  foreach ($c in @('generic', 'dicom', 'plugins')) { try { $null = O PUT "/tools/log-level-$c" 'default' } catch { } }
  Say $T.resetDone 'Green'
  exit 0
}

# ── -Ping: can this PC reach the device? ─────────────────────────────────────
if ($Ping) {
  Say ($T.pingHead -f $Ping) 'Cyan'
  $p = Test-Connection -ComputerName $Ping -Count 2 -ErrorAction SilentlyContinue
  if ($p) { Note ($T.pingOk -f [int](($p | Measure-Object ResponseTime -Average).Average)) 'Green' } else { Note $T.pingNo 'Yellow' }
  $ports = if ($DevicePort) { @($DevicePort) } else { @(104, 4242, 11112) }
  $open = @()
  foreach ($port in $ports) {
    $c = New-Object Net.Sockets.TcpClient
    $ok = $false
    try { $ok = $c.ConnectAsync($Ping, $port).Wait(2000) -and $c.Connected } catch { } finally { $c.Close() }
    if ($ok) { Note ($T.portOk -f $port) 'Green'; $open += $port } else { Note ($T.portNo -f $port) 'Yellow' }
  }
  $echoPort = if ($DevicePort) { $DevicePort } elseif ($open.Count) { $open[0] } else { 0 }
  if (-not $echoPort) { Note $T.echoSkip 'Yellow' }
  else {
    $aet = if ($DeviceAet) { $DeviceAet } else { 'ANY-SCP' }
    if (-not $DeviceAet) { Note ($T.echoNoAet -f $aet) 'DarkGray' }
    # /tools/dicom-echo tries an association without registering the device in
    # Orthanc's configuration.
    try {
      $null = O POST '/tools/dicom-echo' (@{ AET = $aet; Host = $Ping; Port = $echoPort; Timeout = 5 } | ConvertTo-Json)
      Note ($T.echoOk -f $aet, $echoPort) 'Green'
    } catch {
      $why = $_.Exception.Message
      try { $why = ((($_.ErrorDetails.Message) | ConvertFrom-Json).Details) } catch { }
      Note ($T.echoNo -f $aet, $echoPort, $why) 'Yellow'
    }
  }
  exit 0
}

# ── helpers that read, never write ───────────────────────────────────────────
$today = (Get-Date).ToString('yyyyMMdd')
function Get-WorklistFiles {
  # accession | modality | station AE | date of every .wl file, read by the bridge's pydicom
  $py = "import glob,pydicom`nfor f in glob.glob('/worklists/*.wl'):`n  try:`n    d=pydicom.dcmread(f,force=True); s=(d.get('ScheduledProcedureStepSequence') or [{}])[0]`n    print('|'.join([str(d.get('AccessionNumber','')),str(s.get('Modality','')),str(s.get('ScheduledStationAETitle','')),str(s.get('ScheduledProcedureStepStartDate',''))]))`n  except Exception: pass"
  $out = @(docker exec $BridgeContainer python -c $py 2>$null)
  return @($out | Where-Object { $_ -match '\|' } | ForEach-Object { $a = "$_".Split('|'); [pscustomobject]@{ Acc = $a[0]; Modality = $a[1]; Station = $a[2]; Date = $a[3] } })
}
function Describe-List($files) {
  if (-not $files.Count) { return $T.listEmpty }
  return (($files | Group-Object Modality | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')
}
$emrHere = ((docker inspect -f '{{.State.Running}}' $EmrDbContainer 2>$null) -eq 'true')
function Safe([string]$v) { return ($v -match '^[0-9A-Za-z.\-_]{1,64}$') }
function Find-Order([string]$studyUid, [string]$acc) {
  if (-not $emrHere) { return $null }
  $conds = @()
  if (Safe $studyUid) { $conds += "wl.study_instance_uid = '$studyUid'"; $conds += "wl.image_study_uid = '$studyUid'" }
  if (Safe $acc) { $conds += "wl.accession_no = '$acc'" }
  if (-not $conds.Count) { return $null }
  $sql = "SELECT wl.accession_no, wl.study_instance_uid, oi.order_name, p.chart_no, p.last_name || ' ' || p.first_name, (wl.images_received_at IS NOT NULL) " +
         "FROM worklist_log wl JOIN order_item oi ON oi.id = wl.order_item_id JOIN patient p ON p.id = wl.patient_id " +
         "WHERE " + ($conds -join ' OR ') + " ORDER BY wl.id DESC LIMIT 1"
  $row = @(docker exec $EmrDbContainer psql -U medconnect -d medconnect -tA -F '|' -c $sql 2>$null) | Where-Object { $_ } | Select-Object -First 1
  if (-not $row) { return $null }
  $a = "$row".Split('|')
  return [pscustomobject]@{ Acc = $a[0]; StudyUid = $a[1]; Order = $a[2]; Chart = $a[3]; Name = $a[4]; Recorded = ($a[5] -eq 't') }
}
$tsNames = @{
  '1.2.840.10008.1.2.4.50' = 'JPEG'; '1.2.840.10008.1.2.4.51' = 'JPEG'; '1.2.840.10008.1.2.4.57' = 'JPEG lossless'; '1.2.840.10008.1.2.4.70' = 'JPEG lossless'
  '1.2.840.10008.1.2.4.80' = 'JPEG-LS'; '1.2.840.10008.1.2.4.81' = 'JPEG-LS'; '1.2.840.10008.1.2.4.90' = 'JPEG 2000'; '1.2.840.10008.1.2.4.91' = 'JPEG 2000'
  '1.2.840.10008.1.2.5' = 'RLE'
}

# ── -Detail: raise the log level openly, restore it on exit ──────────────────
$cats = @('generic', 'dicom', 'plugins')
$before = @{}
foreach ($c in $cats) { try { $before[$c] = "$(O GET "/tools/log-level-$c")".Trim() } catch { $before[$c] = '' } }
$verbose = -not ($before.Values | Where-Object { $_ -ne 'verbose' -and $_ -ne 'trace' })
Say ($T.start -f $OrthancUrl, $ServerAet) 'Cyan'
$raised = $false
if ($Detail -and -not $verbose) {
  foreach ($c in $cats) { try { $null = O PUT "/tools/log-level-$c" 'verbose' } catch { } }
  $verbose = $true; $raised = $true
  Note $T.detailOn 'DarkYellow'
} elseif (-not $verbose) {
  Note $T.quiet 'DarkYellow'
}

# ── the watch loop ───────────────────────────────────────────────────────────
$logSince = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$lastTicks = [int64]0
$bridgeSince = $logSince
$lastBridgeMsg = ''; $lastBridgeAt = [datetime]::MinValue
$seq = [int64]((O GET '/changes?last').Last)
$studies = @{}        # study UID -> pending image group
$followUps = @()      # orders waiting for the EMR's "images arrived"
$assoc = @{}          # "AET|IP" -> queue of connections (did it ask anything?)
$announced = @{}      # AE whose wrong server name was already said
$wl = $null           # the worklist query being read from the log
$script:lastEvent = $null; $script:lastConnect = $null
$started = Get-Date
$lastIdle = Get-Date

function Handle-LogLine([string]$line) {
  # "2026-09-30T08:10:55.291312345Z I0930 08:10:55.291312  THREAD file.cpp:NN] text"
  if ($line -notmatch '^(\S+)\s(.*)$') { return }
  $when = $null; try { $when = ([datetime]::Parse($Matches[1])).ToLocalTime() } catch { }
  $msg = $Matches[2]
  $body = if ($msg -match '^[IWEF]\d{4} [\d:.]+\s+\S+\s+\S+\] (.*)$') { $Matches[1] } else { $msg }

  if ($script:wl -ne $null) {
    # the JSON of a worklist query spans several lines after "Received worklist query"
    if ($msg -match '^[IWEF]\d{4} ') { $script:wl.Done = $true }
    else { $script:wl.Json += "`n" + $msg; return }
  }
  if ($body -match 'Incoming connection from AET ([^\s,]+) on IP ([^\s,]+), calling AET ([^\s,]+)') {
    $ae = $Matches[1]; $ip = $Matches[2]; $called = $Matches[3]; $key = "$ae|$ip"
    if (-not $script:assoc.ContainsKey($key)) { $script:assoc[$key] = New-Object System.Collections.ArrayList }
    [void]$script:assoc[$key].Add(@{ Used = $false })
    $script:lastConnect = $when
    Say ($T.connect -f $ae, $ip) 'White' $when
    if ($called -ne $ServerAet -and -not $script:announced.ContainsKey($ae)) { Note ($T.calledWrong -f $called, $ServerAet) 'Yellow'; $script:announced[$ae] = $true }
    return
  }
  if ($body -match 'Incoming (\w+) request from AET ([^\s,]+) on IP ([^\s,]+)') {
    $kind = $Matches[1]; $key = "$($Matches[2])|$($Matches[3])"
    if ($script:assoc.ContainsKey($key)) { foreach ($a in $script:assoc[$key]) { if (-not $a.Used) { $a.Used = $true; break } } }
    if ($kind -eq 'Echo') { Say ($T.echo -f $Matches[2]) 'Green' $when }
    elseif ($kind -eq 'Store') { if (-not $script:storeSaid) { Say ($T.store -f $Matches[2]) 'White' $when; $script:storeSaid = $true } }
    return
  }
  if ($body -match 'Received worklist query from remote modality (\S+):') {
    $script:wl = @{ Ae = $Matches[1]; Json = ''; When = $when; Done = $false }
    return
  }
  if ($body -match 'Worklist C-Find: .*found (\d+) match') {
    $n = [int]$Matches[1]
    $q = $null; $ae = '?'; $when0 = $when
    if ($script:wl) { $ae = $script:wl.Ae; $when0 = $script:wl.When; try { $q = $script:wl.Json | ConvertFrom-Json } catch { } }
    $script:wl = $null
    $mod = ''; $st = ''; $date = ''
    if ($q) {
      $sps = @($q.'0040,0100')
      if ($sps.Count -and $sps[0]) { $mod = "$($sps[0].'0008,0060')"; $st = "$($sps[0].'0040,0001')"; $date = "$($sps[0].'0040,0002')" }
    }
    $filt = @(); if ($mod) { $filt += "Modality=$mod" }; if ($st) { $filt += "Station AE=$st" }; if ($date) { $filt += "Date=$date" }
    Say ($T.wlAsk -f $ae, $(if ($filt.Count) { $T.wlFilter -f ($filt -join ', ') } else { '' })) 'White' $when0
    if ($n -gt 0) { Note ($T.wlAnswer -f $n) 'Green'; return }
    $files = @(Get-WorklistFiles)
    $why = if (-not $files.Count) { $T.whyNone }
           elseif ($st -and -not @($files | Where-Object { $_.Station -eq $st }).Count) { $T.whyStation -f $st }
           elseif ($mod -and -not @($files | Where-Object { $_.Modality -eq $mod }).Count) { $T.whyModality -f $mod, (Describe-List $files) }
           elseif ($date -and $date -notmatch [regex]::Escape($today) -and $date -notmatch '-') { $T.whyDate -f $date, $today }
           else { $T.whyOther -f (Describe-List $files) }
    Note ($T.wlZero -f $why) 'Yellow'
    return
  }
  if ($body -match 'Association Release with AET ([^\s,]+) on IP ([^\s,:]+)') {
    $key = "$($Matches[1])|$($Matches[2])"
    if ($script:assoc.ContainsKey($key) -and $script:assoc[$key].Count) {
      $a = $script:assoc[$key][0]; $script:assoc[$key].RemoveAt(0)
      if (-not $a.Used) { Say ($T.leftEmpty -f $Matches[1]) 'Yellow' $when }
    }
    $script:storeSaid = $false
    return
  }
  # Warnings and errors from Orthanc's DICOM threads only (DICOM-SERVER, DICOM-n):
  # those are the device talking. HTTP threads (the admin pages, the EMR's viewer,
  # the bridge), the housekeeper and Orthanc's own "W001:"-style notes are not.
  if ($msg -match '^([EW])\d{4} [\d:.]+\s+(.+?)\s+\S+:\d+\] (.*)$') {
    $thread = $Matches[2]; $text = $Matches[3]
    if ($thread -notmatch '^DICOM') { return }
    if ($text -match '^W\d{3}:') { return }
    $plain = if ($text -match 'reject|not allowed|Unknown remote|unknown modality|called AET') { $T.srvRefused }
             elseif ($text -match 'abort|timeout|timed out|Peer|closed|DUL') { $T.srvAborted }
             elseif ($text -match 'storage|disk|space|full|write') { $T.srvStorage }
             elseif ($text -match 'SOP class|transfer syntax|presentation context|Cannot|parse|corrupt|bad file') { $T.srvData }
             else { $T.srvOther }
    Say $plain 'Yellow' $when
    Note ('(' + $(if ($text.Length -gt 160) { $text.Substring(0, 160) + '…' } else { $text }) + ')') 'DarkGray'
  }
}
$script:storeSaid = $false

try {
  while ($true) {
    # 1) Orthanc's log (connections, echo, worklist, refusals)
    $lines = @(docker logs --timestamps --since $logSince $OrthancContainer 2>&1 | ForEach-Object { "$_" })
    foreach ($line in $lines) {
      # Docker's timestamps vary in length (trailing zeros dropped): compare them as times.
      $stamp = ($line -split '\s', 2)[0]
      $ticks = [int64]0; try { $ticks = [DateTimeOffset]::Parse($stamp).UtcTicks } catch { continue }
      if ($ticks -le $lastTicks) { continue }
      $lastTicks = $ticks; $logSince = $stamp
      Handle-LogLine $line
    }

    # 2) images received (Orthanc's change log - works at any log level)
    try { $page = O GET "/changes?since=$seq&limit=200" } catch { $page = $null }
    if ($page) {
      foreach ($c in @($page.Changes)) {
        if ($c.ChangeType -ne 'NewInstance') { continue }
        try {
          $tags = O GET "/instances/$($c.ID)/simplified-tags"
          $meta = O GET "/instances/$($c.ID)/metadata?expand"
        } catch { continue }
        $uid = "$($tags.StudyInstanceUID)"
        if (-not $studies.ContainsKey($uid)) {
          # Made by Orthanc itself from another image (ModifiedFrom), not received from a
          # device: the EMR put the images of an exam under another order.
          $studies[$uid] = @{ Count = 0; Ae = "$($meta.RemoteAET)"; Ip = "$($meta.RemoteIP)"; Pid = "$($tags.PatientID)"; Acc = "$($tags.AccessionNumber)"; Ts = @{}; First = Get-Date; Private = @{}; NoPixels = 0
                              Corrected = [bool]("$($meta.ModifiedFrom)" -and -not "$($meta.RemoteAET)") }
        }
        $g = $studies[$uid]; $g.Count++; $g.Last = Get-Date; $script:lastConnect = Get-Date
        $ts = "$($meta.TransferSyntax)"; if ($tsNames.ContainsKey($ts)) { $g.Ts[$tsNames[$ts]] = $true }
        # Image types outside the DICOM standard (UnknownSopClassAccepted stores them)
        # and objects without a picture: stored, but the viewer may show nothing.
        $sop = "$($meta.SopClassUid)"
        if ($sop -and $sop -notlike '1.2.840.10008.*') { $g.Private[$sop] = $true }
        if (-not $meta.PixelDataOffset) { $g.NoPixels++ }
        $script:lastEvent = Get-Date
      }
      $seq = [int64]$page.Last
    }
    # a study is summarised once no new image came for 5 seconds
    foreach ($uid in @($studies.Keys)) {
      $g = $studies[$uid]
      if (((Get-Date) - $g.Last).TotalSeconds -lt 5) { continue }
      $studies.Remove($uid)
      $comp = if ($g.Ts.Count) { $T.compressed -f (($g.Ts.Keys) -join ', ') } else { '' }
      if ($g.Corrected) {
        # The temporary study an exchange of two orders goes through says nothing to anyone.
        if ($g.Acc -like 'TMP-*') { continue }
        Say ($T.corrected -f $g.Count, $(if ($g.Pid) { $g.Pid } else { $T.noPid }), $(if ($g.Acc) { $g.Acc } else { $T.noPid })) 'Cyan'
      } else {
        Say ($T.received -f $g.Count, $g.Ae, $g.Ip, $(if ($g.Pid) { $g.Pid } else { $T.noPid }), $(if ($g.Acc) { $g.Acc } else { $T.noPid }), $comp) 'Cyan'
      }
      if ($g.Private.Count) { Note ($T.privateType -f (($g.Private.Keys) -join ', ')) 'Yellow' }
      if ($g.NoPixels) { Note ($T.noPixels -f $g.NoPixels) 'Yellow' }
      if (-not $emrHere) { Note ($T.noEmr -f $EmrDbContainer) 'DarkGray'; continue }
      $o = Find-Order $uid $g.Acc
      if (-not $o) { Note ($T.noOrder -f $(if ($g.Pid) { $g.Pid } else { $T.noPid })) 'Yellow'; continue }
      if ($o.StudyUid -ne $uid) { Note ($T.byAccession -f $o.Acc, $o.Order, $o.Chart, $o.Name) 'Yellow' }
      else { Note ($T.matched -f $o.Order, $o.Chart, $o.Name) 'Green' }
      if (-not $g.Pid) { Note $T.pidMissing 'Yellow' }
      elseif ($g.Pid.Trim().ToUpper() -ne $o.Chart.Trim().ToUpper()) { Note ($T.pidDiffers -f $g.Pid, $o.Chart) 'Red' }
      else { Note $T.pidOk 'Green' }
      $noView = [bool]($g.Private.Count -or $g.NoPixels)
      if (-not $o.Recorded) { $followUps += @{ Uid = $uid; Acc = $o.Acc; Order = $o.Order; Until = (Get-Date).AddMinutes(4); NoView = $noView } }
      elseif ($noView) { Note ($T.recordedNoView -f $o.Order) 'Yellow' }
      else { Note ($T.recorded -f $o.Order) 'Green' }
    }
    # 3) the EMR recording the arrival (after the bridge sees the study settle, ~1 min)
    if ($followUps.Count) {
      $keep = @()
      foreach ($f in $followUps) {
        $o = Find-Order $f.Uid $f.Acc
        if ($o -and $o.Recorded) { if ($f.NoView) { Say ($T.recordedNoView -f $f.Order) 'Yellow' } else { Say ($T.recorded -f $f.Order) 'Green' } }
        elseif ((Get-Date) -lt $f.Until) { $keep += $f }
      }
      $followUps = $keep
    }
    # 4) the bridge's errors (at most once a minute for the same text)
    $bl = @(docker logs --since $bridgeSince $BridgeContainer 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^bridge error:' })
    $bridgeSince = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    if ($bl.Count) {
      $m = ($bl[-1] -replace '^bridge error:\s*', '')
      if ($m -ne $lastBridgeMsg -or ((Get-Date) - $lastBridgeAt).TotalSeconds -gt 60) {
        $plain = if ($m -match 'Something other than the EMR') { $T.bridgeNotEmr }
                 elseif ($m -match 'Max retries|Failed to resolve|Connection refused|timed out|Name or service') { $T.bridgeNoEmr }
                 else { $T.bridgeErr -f $m }
        Say $plain 'Yellow'
        if ($plain -ne ($T.bridgeErr -f $m)) { Note ('(' + $(if ($m.Length -gt 140) { $m.Substring(0, 140) + '…' } else { $m }) + ')') 'DarkGray' }
        $lastBridgeMsg = $m; $lastBridgeAt = Get-Date
      }
    }
    # 5) nothing for 30 seconds
    $quietFor = if ($script:lastEvent) { ((Get-Date) - $script:lastEvent).TotalSeconds } else { ((Get-Date) - $started).TotalSeconds }
    if ($quietFor -ge 30 -and ((Get-Date) - $lastIdle).TotalSeconds -ge 30) {
      # printed directly: a waiting line is not an event
      $w = if ($script:lastConnect) { $T.waitingSince -f ([datetime]$script:lastConnect).ToString('HH:mm:ss') } else { $T.waiting }
      Write-Host ((Get-Date).ToString('HH:mm:ss') + '  ' + $w) -ForegroundColor DarkGray
      $lastIdle = Get-Date
    }
    if ($Seconds -gt 0 -and ((Get-Date) - $started).TotalSeconds -ge $Seconds) { break }
    Start-Sleep -Seconds 2
  }
} finally {
  # Only what this window raised is put back; a level someone else set stays.
  if ($raised) {
    $okBack = $true
    foreach ($c in $cats) {
      if ($before[$c] -and $before[$c] -ne 'verbose') { try { $null = O PUT "/tools/log-level-$c" $before[$c] } catch { $okBack = $false } }
    }
    if ($okBack) { Note $T.detailOff 'DarkYellow' } else { Note ($T.detailStuck -f $OrthancContainer) 'Red' }
  }
}
