// Bethesda CD - talking to the EMR. The program talks to the EMR only - never to the image
// server, whose password it does not have. The EMR decides who may copy or bring in what
// and writes the change-log line.
//   copying out:  GET /api/pacs/export/patient, GET /api/pacs/export/bundle
//   bringing in:  GET /api/pacs/import/patient, POST /import/check, /import/begin,
//                 PUT /import/{id}/instance (one DICOM file, as it is), POST …/finish, …/cancel
//                 (the EMR's wiki, reference/external-images-import-api.md)
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Web.Script.Serialization;

namespace Bethesda.Cd {
  // What came back: Status 0 = no answer at all. Code is the reason of a refusal, as the
  // EMR names it (or LOGIN, FORBIDDEN, HTTP_nnn, NO_ANSWER, BROKEN, CANCELLED).
  public class EmrAnswer {
    public bool Ok; public int Status; public Dictionary<string, object> Data; public string Code = "", Error = ""; public long Bytes;
    public Dictionary<string, string> Headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    public string Header(string name) { string v; return Headers.TryGetValue(name, out v) ? v : ""; }
  }

  // Reading what the EMR sends (JSON) without caring how each value was typed.
  public static class J {
    public static Dictionary<string, object> Parse(string text) {
      try { return new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.DeserializeObject(text) as Dictionary<string, object>; } catch (Exception) { return null; }
    }
    public static string Write(object o) { return new JavaScriptSerializer().Serialize(o); }
    public static object Get(Dictionary<string, object> d, string key) { object v; return d != null && d.TryGetValue(key, out v) ? v : null; }
    public static string Str(Dictionary<string, object> d, string key) { object v = Get(d, key); return v == null ? "" : Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture); }
    public static long Long(Dictionary<string, object> d, string key) { object v = Get(d, key); try { return v == null ? 0 : Convert.ToInt64(v, System.Globalization.CultureInfo.InvariantCulture); } catch (Exception) { return 0; } }
    public static bool IsNull(Dictionary<string, object> d, string key) { return Get(d, key) == null; }
    public static Dictionary<string, object> Dict(Dictionary<string, object> d, string key) { return Get(d, key) as Dictionary<string, object>; }
    public static List<Dictionary<string, object>> List(Dictionary<string, object> d, string key) {
      List<Dictionary<string, object>> o = new List<Dictionary<string, object>>(); IEnumerable e = Get(d, key) as IEnumerable;
      if (e != null && !(Get(d, key) is string)) foreach (object x in e) { Dictionary<string, object> row = x as Dictionary<string, object>; if (row != null) o.Add(row); }
      return o;
    }
    public static List<string> Strings(Dictionary<string, object> d, string key) {
      List<string> o = new List<string>(); IEnumerable e = Get(d, key) as IEnumerable;
      if (e != null && !(Get(d, key) is string)) foreach (object x in e) o.Add(Convert.ToString(x));
      return o;
    }
    public static bool Has(Dictionary<string, object> d, string key, string value) {
      IEnumerable e = Get(d, key) as IEnumerable; if (e == null || Get(d, key) is string) return false;
      foreach (object x in e) if (Convert.ToString(x) == value) return true;
      return false;
    }
  }

  public class EmrClient {
    public string Url = "", Token = ""; public Dictionary<string, object> User;
    // What this account may do here: copy out (Consultation or Payment), bring in (those, or
    // Registration - the desk that is handed the disc).
    public bool CanExport, CanImport;

    HttpWebRequest Request(string method, string path, int timeoutSec) {
      HttpWebRequest req = (HttpWebRequest)WebRequest.Create(Url.TrimEnd('/') + path);
      req.Method = method; req.Timeout = timeoutSec * 1000;
      req.ReadWriteTimeout = 120000;                       // two minutes without a byte: given up
      req.AllowAutoRedirect = false;
      req.Proxy = null;                                    // the EMR is on the clinic's own network
      req.UserAgent = "bethesda-cd/" + Product.Version;
      if (Token != "") req.Headers["Authorization"] = "Bearer " + Token;
      return req;
    }
    // The answer of a request that has been sent: its status, its headers, and its body -
    // saved to a file as it comes (`saveTo`), or read as JSON.
    void Answer(HttpWebRequest req, EmrAnswer o, string saveTo, Action<long> onBytes) {
      HttpWebResponse resp;
      try { resp = (HttpWebResponse)req.GetResponse(); }
      catch (WebException e) {
        resp = e.Response as HttpWebResponse;
        if (resp == null) { o.Code = "NO_ANSWER"; o.Error = e.Message; return; }
      }
      using (resp) {
        o.Status = (int)resp.StatusCode;
        foreach (string k in resp.Headers.AllKeys) o.Headers[k] = resp.Headers[k];
        using (Stream input = resp.GetResponseStream()) {
          if (!string.IsNullOrEmpty(saveTo) && o.Status == 200) {
            using (FileStream file = File.Create(saveTo)) {
              byte[] buf = new byte[262144]; long total = 0, told = 0; int n;
              while ((n = input.Read(buf, 0, buf.Length)) > 0) {
                file.Write(buf, 0, n); total += n;
                if (onBytes != null && total - told >= 1048576) { told = total; onBytes(total); }
              }
              if (onBytes != null) onBytes(total);
              o.Bytes = total; o.Ok = true;
            }
          } else {
            string text = new StreamReader(input, Encoding.UTF8).ReadToEnd();
            o.Data = J.Parse(text);
            o.Ok = o.Status >= 200 && o.Status < 300 && o.Data != null;
            if (!o.Ok) {
              string code = J.Str(o.Data, "code");
              o.Code = code != "" ? code : o.Status == 401 ? "LOGIN" : o.Status == 403 ? "FORBIDDEN" : "HTTP_" + o.Status;
              o.Error = J.Str(o.Data, "error");
            }
          }
        }
      }
    }

    // One request. `saveTo`: the body goes to that file as it comes (the bundle), and
    // `onBytes` hears how many bytes so far.
    public EmrAnswer Call(string method, string path, object body, string saveTo, Action<long> onBytes, int timeoutSec) {
      EmrAnswer o = new EmrAnswer();
      try {
        HttpWebRequest req = Request(method, path, timeoutSec);
        if (body != null) {
          byte[] bytes = Encoding.UTF8.GetBytes(J.Write(body));
          req.ContentType = "application/json; charset=utf-8"; req.ContentLength = bytes.Length;
          using (Stream s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
        } else if (method != "GET") req.ContentLength = 0;
        Answer(req, o, saveTo, onBytes);
      } catch (Exception e) {
        // the connection broke while the body was being read: a bundle cut short is never kept as if whole
        o.Ok = false; if (o.Code == "") o.Code = "BROKEN"; o.Error = e.Message;
        if (!string.IsNullOrEmpty(saveTo)) { try { File.Delete(saveTo); } catch (Exception) { } }
      }
      return o;
    }
    public EmrAnswer Get(string path) { return Call("GET", path, null, null, null, 30); }
    public EmrAnswer Post(string path, object body, int timeoutSec) { return Call("POST", path, body, null, null, timeoutSec); }

    // One file sent as it is (PUT, application/dicom): read from the disc and passed on block
    // by block - never held whole in memory, never written to this PC. `onBytes` hears how
    // far it is; `stop` is asked between blocks, and true gives the file up (CANCELLED).
    public EmrAnswer PutFile(string path, string file, Action<long> onBytes, Func<bool> stop, int timeoutSec) {
      EmrAnswer o = new EmrAnswer(); HttpWebRequest req = null; bool discFailed = true;       // (until the file is open)
      try {
        using (FileStream input = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read)) {
          discFailed = false;
          req = Request("PUT", path, timeoutSec);
          req.ReadWriteTimeout = timeoutSec * 1000;          // the EMR answers when the image server has taken the file
          req.ContentType = "application/dicom"; req.ContentLength = input.Length;
          req.AllowWriteStreamBuffering = false;             // a large file goes out as it is read
          using (Stream s = req.GetRequestStream()) {
            byte[] buf = new byte[262144]; long total = 0;
            while (true) {
              int n;
              try { n = input.Read(buf, 0, buf.Length); } catch (Exception) { discFailed = true; throw; }
              if (n <= 0) break;
              if (stop != null && stop()) { req.Abort(); o.Code = "CANCELLED"; return o; }
              s.Write(buf, 0, n); total += n;
              if (onBytes != null) onBytes(total);
            }
            o.Bytes = total;
          }
        }
        Answer(req, o, null, null);
      } catch (Exception e) {
        // The EMR may have refused the file before all of it was sent (too large, the import closed)
        // and shut the line: what it answered says why, and sending the file again would not help.
        if (o.Code == "" && !discFailed && req != null) {
          EmrAnswer early = new EmrAnswer();
          try {
            WebException we = e as WebException; HttpWebResponse got = we == null ? null : we.Response as HttpWebResponse;
            if (got != null) { using (got) { early.Status = (int)got.StatusCode; early.Data = J.Parse(new StreamReader(got.GetResponseStream(), Encoding.UTF8).ReadToEnd()); } }
            else Answer(req, early, null, null);
          } catch (Exception) { }
          if (early.Status >= 400) {
            early.Ok = false; if (early.Code == "") early.Code = J.Str(early.Data, "code") != "" ? J.Str(early.Data, "code") : "HTTP_" + early.Status;
            if (early.Error == "") early.Error = J.Str(early.Data, "error");
            try { req.Abort(); } catch (Exception) { }
            return early;
          }
        }
        // the disc could not be read (a scratched CD, a stick pulled out) - or the connection broke
        o.Ok = false; if (o.Code == "") o.Code = discFailed ? "UNREADABLE" : "BROKEN"; o.Error = e.Message;
        try { if (req != null) req.Abort(); } catch (Exception) { }
      }
      return o;
    }

    // Sign in with an EMR account. The token is kept in memory only, for as long as the
    // program runs; the password is not kept at all.
    public EmrAnswer Login(string url, string login, string password) {
      Url = (url ?? "").Trim(); Token = ""; User = null; CanExport = CanImport = false;
      if (!System.Text.RegularExpressions.Regex.IsMatch(Url, @"^https?://[^/\s]+")) return new EmrAnswer { Code = "BAD_URL" };
      EmrAnswer r = Call("POST", "/api/auth/login", new Dictionary<string, object> { { "login_id", login }, { "password", password } }, null, null, 30);
      string token = J.Str(r.Data, "token");
      if (r.Ok && token != "") {
        Dictionary<string, object> user = J.Dict(r.Data, "user");
        bool export = J.Has(user, "permissions", "consultation") || J.Has(user, "permissions", "payment");
        bool import = export || J.Has(user, "permissions", "registration");
        if (!import) return new EmrAnswer { Code = "FORBIDDEN", Status = r.Status };
        Token = token; User = user; CanExport = export; CanImport = import;
        return r;
      }
      r.Ok = false;
      if (r.Status == 401 || r.Status == 400) r.Code = "WRONG_LOGIN";
      else if (r.Status == 0) r.Code = "NO_ANSWER";
      else { r.Code = "NOT_EMR"; r.Error = "HTTP " + r.Status; }       // an address that answers but is not the EMR
      return r;
    }
    public void Logout() { Token = ""; User = null; CanExport = CanImport = false; }

    public EmrAnswer Patient(string chartNo) { return Get("/api/pacs/export/patient?chart_no=" + Uri.EscapeDataString((chartNo ?? "").Trim())); }
    // Bringing in: the patient, the limits and what was brought in for them before.
    public EmrAnswer ImportPatient(string chartNo) { return Get("/api/pacs/import/patient?chart_no=" + Uri.EscapeDataString((chartNo ?? "").Trim())); }
  }
}
