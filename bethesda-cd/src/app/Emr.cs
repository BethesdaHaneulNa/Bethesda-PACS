// Bethesda CD - talking to the EMR. The program talks to the EMR only (sign in,
// GET /api/pacs/export/patient, GET /api/pacs/export/bundle) - never to the image
// server, whose password it does not have. The EMR decides who may copy what and writes
// the change-log line.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Web.Script.Serialization;

namespace Bethesda.Cd {
  // What came back: Status 0 = no answer at all. Code is the reason of a refusal, as the
  // EMR names it (or LOGIN, FORBIDDEN, HTTP_nnn, NO_ANSWER, BROKEN).
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
    public static Dictionary<string, object> Dict(Dictionary<string, object> d, string key) { return Get(d, key) as Dictionary<string, object>; }
    public static List<Dictionary<string, object>> List(Dictionary<string, object> d, string key) {
      List<Dictionary<string, object>> o = new List<Dictionary<string, object>>(); IEnumerable e = Get(d, key) as IEnumerable;
      if (e != null && !(Get(d, key) is string)) foreach (object x in e) { Dictionary<string, object> row = x as Dictionary<string, object>; if (row != null) o.Add(row); }
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

    // One request. `saveTo`: the body goes to that file as it comes (the bundle), and
    // `onBytes` hears how many bytes so far.
    public EmrAnswer Call(string method, string path, object body, string saveTo, Action<long> onBytes, int timeoutSec) {
      EmrAnswer o = new EmrAnswer();
      try {
        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(Url.TrimEnd('/') + path);
        req.Method = method; req.Timeout = timeoutSec * 1000;
        req.ReadWriteTimeout = 120000;                       // two minutes without a byte: given up
        req.AllowAutoRedirect = false;
        req.Proxy = null;                                    // the EMR is on the clinic's own network
        req.UserAgent = "bethesda-cd/" + Product.Version;
        if (Token != "") req.Headers["Authorization"] = "Bearer " + Token;
        if (body != null) {
          byte[] bytes = Encoding.UTF8.GetBytes(J.Write(body));
          req.ContentType = "application/json; charset=utf-8"; req.ContentLength = bytes.Length;
          using (Stream s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
        }
        HttpWebResponse resp;
        try { resp = (HttpWebResponse)req.GetResponse(); }
        catch (WebException e) {
          resp = e.Response as HttpWebResponse;
          if (resp == null) { o.Code = "NO_ANSWER"; o.Error = e.Message; return o; }
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
      } catch (Exception e) {
        // the connection broke while the body was being read: a bundle cut short is never kept as if whole
        o.Ok = false; if (o.Code == "") o.Code = "BROKEN"; o.Error = e.Message;
        if (!string.IsNullOrEmpty(saveTo)) { try { File.Delete(saveTo); } catch (Exception) { } }
      }
      return o;
    }
    public EmrAnswer Get(string path) { return Call("GET", path, null, null, null, 30); }

    // Sign in with an EMR account. The token is kept in memory only, for as long as the
    // program runs; the password is not kept at all.
    public EmrAnswer Login(string url, string login, string password) {
      Url = (url ?? "").Trim(); Token = ""; User = null;
      if (!System.Text.RegularExpressions.Regex.IsMatch(Url, @"^https?://[^/\s]+")) return new EmrAnswer { Code = "BAD_URL" };
      EmrAnswer r = Call("POST", "/api/auth/login", new Dictionary<string, object> { { "login_id", login }, { "password", password } }, null, null, 30);
      string token = J.Str(r.Data, "token");
      if (r.Ok && token != "") {
        Dictionary<string, object> user = J.Dict(r.Data, "user");
        if (!J.Has(user, "permissions", "consultation") && !J.Has(user, "permissions", "payment")) return new EmrAnswer { Code = "FORBIDDEN", Status = r.Status };
        Token = token; User = user;
        return r;
      }
      r.Ok = false;
      if (r.Status == 401 || r.Status == 400) r.Code = "WRONG_LOGIN";
      else if (r.Status == 0) r.Code = "NO_ANSWER";
      else { r.Code = "NOT_EMR"; r.Error = "HTTP " + r.Status; }       // an address that answers but is not the EMR
      return r;
    }
    public void Logout() { Token = ""; User = null; }

    public EmrAnswer Patient(string chartNo) { return Get("/api/pacs/export/patient?chart_no=" + Uri.EscapeDataString((chartNo ?? "").Trim())); }
  }
}
