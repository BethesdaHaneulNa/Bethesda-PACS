// Bethesda CD - every word the window says, in one place: French first (the staff's
// language); Korean and English are for the people who install and support it.
// The language is the line "lang=" of Bethesda-CD.ini (fr when there is none).
using System.Collections.Generic;

namespace Bethesda.Cd {
  public static class Texts {
    public static string Lang = "fr";
    public static string Unit { get { return Lang == "fr" ? "Mo" : "MB"; } }
    static int Column { get { return Lang == "ko" ? 1 : Lang == "en" ? 2 : 0; } }
    public static bool Known(string lang) { return lang == "fr" || lang == "ko" || lang == "en"; }

    public static string Get(string key) { string[] v; return T.TryGetValue(key, out v) ? v[Column] : key; }
    public static string Get(string key, params object[] a) { return string.Format(Get(key), a); }
    public static bool Has(string key) { return T.ContainsKey(key); }
    // The words for a refusal: by its code, and the reason as it came when the code is unknown.
    public static string Error(string code, string detail, params object[] a) {
      if (!T.ContainsKey("e_" + code)) return Get("e_other", (code + " " + detail).Trim());
      return string.Format(Get("e_" + code), a.Length == 0 ? new object[] { "", "" } : a);
    }

    static readonly Dictionary<string, string[]> T = new Dictionary<string, string[]> {
      //                  French                                         Korean                                   English
      { "title",      new[] { "Bethesda CD — Copie des images sur CD", "Bethesda CD — 영상 CD 반출", "Bethesda CD — Copy images to CD" } },
      { "emrUrl",     new[] { "Adresse de l'EMR", "EMR 주소", "EMR address" } },
      { "login",      new[] { "Identifiant", "아이디", "Login" } },
      { "password",   new[] { "Mot de passe", "비밀번호", "Password" } },
      { "signIn",     new[] { "Se connecter", "로그인", "Sign in" } },
      { "signOut",    new[] { "Se déconnecter", "로그아웃", "Sign out" } },
      { "loginHint",  new[] { "Connectez-vous avec votre compte de l'EMR (Consultation ou Paiement).", "EMR 계정으로 로그인하세요(진료 또는 수납 권한).", "Sign in with your EMR account (Consultation or Payment)." } },
      { "connected",  new[] { "Connecté : {0}", "로그인: {0}", "Signed in: {0}" } },
      { "chart",      new[] { "N° dossier", "차트번호", "Chart no." } },
      { "search",     new[] { "Chercher", "조회", "Find" } },
      { "patient",    new[] { "{0} — né(e) le {1} — {2}", "{0} — 생년월일 {1} — {2}", "{0} — born {1} — {2}" } },
      { "noPatientYet", new[] { "Tapez le N° dossier du patient, puis Entrée.", "환자의 차트번호를 치고 Enter를 누르세요.", "Type the patient's chart number, then Enter." } },
      { "colDate",    new[] { "Date", "날짜", "Date" } },
      { "colType",    new[] { "Type", "종류", "Type" } },
      { "colExam",    new[] { "Examen", "검사", "Exam" } },
      { "colImages",  new[] { "Images", "영상", "Images" } },
      { "colSize",    new[] { "Taille", "크기", "Size" } },
      { "colState",   new[] { "État", "상태", "State" } },
      { "selNone",    new[] { "Cochez les examens à copier.", "반출할 검사를 체크하세요.", "Tick the exams to copy." } },
      { "sel",        new[] { "Sélection : {0} examen(s) · {1} image(s) · {2}", "선택: 검사 {0}건 · 영상 {1}장 · {2}", "Chosen: {0} exam(s) · {1} image(s) · {2}" } },
      { "selMax",     new[] { "Au plus {0} examens à la fois.", "한 번에 {0}건까지입니다.", "At most {0} exams at a time." } },
      { "noBurner",   new[] { "Aucun graveur sur ce PC — « Enregistrer en fichier ISO » et « Enregistrer dans un dossier » restent possibles.", "이 PC에는 굽는 드라이브가 없습니다 — 「ISO 파일로 저장」과 「폴더에 저장」은 됩니다.", "No disc burner on this PC — \"Save as ISO file\" and \"Save to a folder\" still work." } },
      { "noDisc",     new[] { "Graveur {0} — insérez un disque vierge.", "드라이브 {0} — 빈 디스크를 넣으세요.", "Burner {0} — insert a blank disc." } },
      { "discBlank",  new[] { "Graveur {0} — {1} vierge, {2} libres", "드라이브 {0} — 빈 {1}, {2} 남음", "Burner {0} — blank {1}, {2} free" } },
      { "fits",       new[] { "  ✔ tient sur ce disque", "  ✔ 이 디스크에 들어갑니다", "  ✔ fits on this disc" } },
      { "tooBig",     new[] { "  ✘ {0} de trop : décochez un examen ou utilisez un DVD", "  ✘ {0} 넘침: 검사를 줄이거나 DVD를 쓰세요", "  ✘ {0} too much: untick an exam or use a DVD" } },
      { "discUsed",   new[] { "Graveur {0} — ce disque n'est pas vierge : il ne sera pas utilisé.", "드라이브 {0} — 빈 디스크가 아닙니다. 이 디스크에는 굽지 않습니다.", "Burner {0} — this disc is not blank: it will not be used." } },
      { "stViewer",   new[] { "Ajout de la visionneuse…", "뷰어를 넣는 중…", "Adding the viewer…" } },
      { "noViewer",   new[] { "\n\n(La visionneuse VOIR.EXE n'a pas pu être ajoutée : {0})", "\n\n(뷰어 VOIR.EXE를 넣지 못했습니다: {0})", "\n\n(The viewer VOIR.EXE could not be added: {0})" } },
      { "unpacked",   new[] { "\n\n(Certaines images étaient dans un format que la visionneuse ne lit pas : toutes les images de cette copie ont été décompressées, sans perte. La copie est plus volumineuse.)",
                              "\n\n(뷰어가 읽지 못하는 형식의 영상이 있어, 이 사본의 영상을 모두 압축을 풀어 넣었습니다(화질 손실 없음). 사본이 더 큽니다.)",
                              "\n\n(Some images were in a format the viewer does not read: every image of this copy was decompressed, without loss. The copy is larger.)" } },
      { "burn",       new[] { "Graver ce CD…", "이 CD에 굽기…", "Burn this CD…" } },
      { "iso",        new[] { "Enregistrer en fichier ISO…", "ISO 파일로 저장…", "Save as ISO file…" } },
      { "folder",     new[] { "Enregistrer dans un dossier…", "폴더에 저장…", "Save to a folder…" } },
      { "askBurn",    new[] { "Graver {0} examen(s) ({1}) de {2} sur le disque du lecteur {3} ?", "{2} 님의 검사 {0}건({1})을 {3} 드라이브의 디스크에 구울까요?", "Burn {0} exam(s) ({1}) of {2} to the disc in drive {3}?" } },
      { "askFolder",  new[] { "Choisissez le dossier (ou la clé USB) où créer la copie", "사본을 만들 폴더(또는 USB)를 고르세요", "Choose the folder (or USB stick) where the copy is made" } },
      { "stFetch",    new[] { "Récupération des images… {0}", "영상을 받는 중… {0}", "Fetching the images… {0}" } },
      { "stReadme",   new[] { "Préparation du disque…", "디스크 내용을 준비하는 중…", "Preparing the disc…" } },
      { "stCopy",     new[] { "Copie… {0} / {1}", "복사 중… {0} / {1}", "Copying… {0} / {1}" } },
      { "stImage",    new[] { "Préparation de l'image du disque…", "디스크 이미지를 만드는 중…", "Preparing the disc image…" } },
      { "stIso",      new[] { "Écriture du fichier ISO… {0} %", "ISO 파일을 쓰는 중… {0} %", "Writing the ISO file… {0} %" } },
      { "stBurn",     new[] { "Gravure en cours… {0} %   {1}", "굽는 중… {0} %   {1}", "Burning… {0} %   {1}" } },
      { "stCheck",    new[] { "Vérification du disque…", "구운 디스크를 확인하는 중…", "Checking the disc…" } },
      { "doneFolder", new[] { "Terminé. La copie est dans :\n{0}\n\n{1} fichiers, {2}. Chaque fichier a été relu et comparé.\n\nCe dossier contient les images d'un patient : supprimez-le quand il n'est plus utile.",
                              "끝났습니다. 사본의 자리:\n{0}\n\n파일 {1}개, {2}. 파일마다 다시 읽어 원본과 비교했습니다.\n\n이 폴더에는 환자의 영상이 들어 있습니다. 쓸 일이 끝나면 지우세요.",
                              "Done. The copy is in:\n{0}\n\n{1} files, {2}. Every file was read back and compared.\n\nThis folder holds a patient's images: delete it when it is no longer needed." } },
      { "doneIso",    new[] { "Terminé. Fichier ISO :\n{0}\n({1})\n\nCe fichier contient les images d'un patient : supprimez-le quand il n'est plus utile.",
                              "끝났습니다. ISO 파일:\n{0}\n({1})\n\n이 파일에는 환자의 영상이 들어 있습니다. 쓸 일이 끝나면 지우세요.",
                              "Done. ISO file:\n{0}\n({1})\n\nThis file holds a patient's images: delete it when it is no longer needed." } },
      { "doneBurn",   new[] { "Terminé : le disque est gravé et vérifié.\n\nÉcrivez le nom du patient et la date sur le disque.", "끝났습니다. 디스크를 굽고 확인했습니다.\n\n디스크에 환자 이름과 날짜를 적으세요.", "Done: the disc is burnt and checked.\n\nWrite the patient's name and the date on the disc." } },
      { "doneBurnDrive", new[] { "Terminé : le disque est gravé (vérifié par le graveur).\n\nÉcrivez le nom du patient et la date sur le disque.", "끝났습니다. 디스크를 구웠습니다(드라이브가 확인함).\n\n디스크에 환자 이름과 날짜를 적으세요.", "Done: the disc is burnt (checked by the burner).\n\nWrite the patient's name and the date on the disc." } },
      { "doneBurnUnread", new[] { "Le disque est gravé, mais il n'a pas pu être relu pour la vérification.\nRemettez-le dans le lecteur et vérifiez qu'il s'ouvre avant de le remettre.", "디스크는 구웠지만, 확인하려고 다시 읽지 못했습니다.\n디스크를 다시 넣어 열리는지 본 뒤에 건네세요.", "The disc is burnt, but it could not be read back for the check.\nPut it back in the drive and see that it opens before handing it over." } },
      { "badBurn",    new[] { "La gravure a échoué : ce disque est à jeter.\n{0}\n\nMettez un autre disque vierge et recommencez.", "굽기에 실패했습니다. 이 디스크는 버리세요.\n{0}\n\n다른 빈 디스크를 넣고 다시 하세요.", "Burning failed: throw this disc away.\n{0}\n\nInsert another blank disc and start again." } },
      { "badVerify",  new[] { "La vérification a échoué — ne remettez pas ce disque.\n{0} fichier(s) différent(s). Mettez un autre disque vierge et recommencez.", "확인에서 어긋났습니다 — 이 디스크를 건네지 마세요.\n다른 파일 {0}개. 다른 빈 디스크를 넣고 다시 하세요.", "The check failed — do not hand this disc over.\n{0} file(s) differ. Insert another blank disc and start again." } },
      { "busyClose",  new[] { "Une copie est en cours. Attendez qu'elle se termine.", "반출하는 중입니다. 끝날 때까지 기다리세요.", "A copy is being made. Wait until it is finished." } },
      { "expired",    new[] { "La session a expiré. Reconnectez-vous.", "로그인이 만료되었습니다. 다시 로그인하세요.", "The session has expired. Sign in again." } },
      { "male",       new[] { "M", "남", "M" } },
      { "female",     new[] { "F", "여", "F" } },
      { "e_BAD_URL",  new[] { "L'adresse de l'EMR doit commencer par http:// (exemple : http://192.168.1.10:9080).", "EMR 주소는 http:// 로 시작해야 합니다(예: http://192.168.1.10:9080).", "The EMR address must start with http:// (example: http://192.168.1.10:9080)." } },
      { "e_NO_ANSWER", new[] { "L'EMR ne répond pas à cette adresse. Vérifiez l'adresse et le réseau.", "이 주소에서 EMR이 응답하지 않습니다. 주소와 네트워크를 확인하세요.", "The EMR does not answer at this address. Check the address and the network." } },
      { "e_NOT_EMR",  new[] { "Cette adresse répond, mais ce n'est pas l'EMR.", "이 주소는 응답하지만 EMR이 아닙니다.", "This address answers, but it is not the EMR." } },
      { "e_WRONG_LOGIN", new[] { "Identifiant ou mot de passe incorrect.", "아이디 또는 비밀번호가 틀렸습니다.", "Wrong login or password." } },
      { "e_FORBIDDEN", new[] { "Ce compte n'a pas le droit de copier des images (il faut Consultation ou Paiement).", "이 계정은 영상을 반출할 권한이 없습니다(진료 또는 수납 권한이 필요).", "This account may not copy images (Consultation or Payment is needed)." } },
      { "e_NO_PATIENT", new[] { "Aucun patient avec ce N° dossier.", "이 차트번호의 환자가 없습니다.", "No patient with this chart number." } },
      { "e_CANCELLED", new[] { "examen annulé", "취소된 검사", "cancelled exam" } },
      { "e_NO_IMAGES", new[] { "pas d'images", "영상 없음", "no images" } },
      { "e_IDENTITY", new[] { "avertissement d'identité : à régler d'abord dans l'EMR", "환자 번호 경고 — EMR에서 먼저 바로잡으세요", "identity warning: settle it in the EMR first" } },
      { "e_BUSY",     new[] { "correction en cours : réessayez dans quelques minutes", "영상을 바로잡는 중 — 몇 분 뒤에 다시", "being corrected: try again in a few minutes" } },
      { "e_NOT_ON_SERVER", new[] { "images absentes du serveur d'images", "영상 서버에 영상이 없음", "images missing on the image server" } },
      { "e_UNREACHABLE", new[] { "Le serveur d'images ne répond pas. Réessayez dans un instant.", "영상 서버가 응답하지 않습니다. 잠시 뒤에 다시 하세요.", "The image server does not answer. Try again in a moment." } },
      { "e_NOT_PAIRED", new[] { "Le serveur d'images n'est pas relié à l'EMR. Prévenez l'administrateur.", "영상 서버가 EMR과 연결되어 있지 않습니다. 관리자에게 알리세요.", "The image server is not linked to the EMR. Tell the administrator." } },
      { "e_NOT_LOGGED", new[] { "Le journal des modifications n'a pas pu être écrit : rien n'a été copié.", "변경 기록을 남기지 못했습니다. 아무것도 반출하지 않았습니다.", "The change log could not be written: nothing was copied." } },
      { "e_OTHER_PATIENT", new[] { "Les examens ne sont pas du même patient.", "같은 환자의 검사가 아닙니다.", "The exams are not of the same patient." } },
      { "e_TOO_MANY_EXAMS", new[] { "Trop d'examens à la fois.", "한 번에 반출하기에는 검사가 너무 많습니다.", "Too many exams at a time." } },
      { "e_BROKEN",   new[] { "La connexion a été coupée pendant la récupération. Rien n'a été copié ; recommencez.", "받는 도중에 연결이 끊겼습니다. 아무것도 반출하지 않았습니다. 다시 하세요.", "The connection was cut while fetching. Nothing was copied; start again." } },
      { "e_BAD_BUNDLE", new[] { "Les images reçues sont incomplètes. Rien n'a été copié ; recommencez.", "받은 영상이 온전하지 않습니다. 아무것도 반출하지 않았습니다. 다시 하세요.", "The images received are incomplete. Nothing was copied; start again." } },
      { "e_NO_ROOM",  new[] { "Pas assez de place à cet endroit : il faut {0}, il reste {1}.", "그 자리에 공간이 모자랍니다: {0} 필요, {1} 남음.", "Not enough room there: {0} needed, {1} left." } },
      { "e_NO_FOLDER", new[] { "Ce dossier n'existe pas.", "그 폴더가 없습니다.", "This folder does not exist." } },
      { "e_WRITE_FAILED", new[] { "La copie a échoué : {0}", "복사에 실패했습니다: {0}", "The copy failed: {0}" } },
      { "e_NOT_VERIFIED", new[] { "La copie a été relue et elle est différente de l'original ({0} fichier(s)).\nSupprimez le dossier {1} et recommencez.", "사본을 다시 읽었더니 원본과 다릅니다(파일 {0}개).\n{1} 폴더를 지우고 다시 하세요.", "The copy was read back and differs from the original ({0} file(s)).\nDelete the folder {1} and start again." } },
      { "e_EXISTS",   new[] { "Ce fichier existe déjà. Choisissez un autre nom.", "같은 이름의 파일이 이미 있습니다. 다른 이름을 고르세요.", "This file already exists. Choose another name." } },
      { "e_ISO",      new[] { "Le fichier ISO n'a pas pu être écrit : {0}", "ISO 파일을 쓰지 못했습니다: {0}", "The ISO file could not be written: {0}" } },
      { "e_other",    new[] { "Erreur : {0}", "오류: {0}", "Error: {0}" } },
    };
  }
}
