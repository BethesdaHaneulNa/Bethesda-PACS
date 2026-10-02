// VOIR.EXE - every word the viewer shows, in one place: French (the language of the
// hospitals the disc goes to) when Windows is in French, English otherwise.
using System.Collections.Generic;
using System.Globalization;

namespace Bethesda.Viewer {
  public static class Texts {
    public static string Lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr" ? "fr" : "en";

    static readonly Dictionary<string, string[]> T = new Dictionary<string, string[]> {
      //                     French                                                              English
      { "app",        new[] { "Visionneuse d'images",                                             "Image viewer" } },
      { "notice",     new[] { "Visionneuse de consultation — non destinée au diagnostic",         "Viewer for reference — not for diagnosis" } },
      { "exams",      new[] { "Examens",                                                          "Exams" } },
      { "prev",       new[] { "◀ Image",                                                          "◀ Image" } },
      { "next",       new[] { "Image ▶",                                                          "Image ▶" } },
      { "fit",        new[] { "Ajuster",                                                          "Fit" } },
      { "invert",     new[] { "Inverser",                                                         "Invert" } },
      { "reset",      new[] { "Réinitialiser",                                                    "Reset" } },
      { "help",       new[] { "?",                                                                "?" } },
      { "image",      new[] { "image {0} / {1}",                                                  "image {0} / {1}" } },
      { "frames",     new[] { "{0} images dans ce fichier — la première est affichée",            "{0} frames in this file — the first is shown" } },
      { "frame",      new[] { "fichier à plusieurs images : {0} / {1} (molette)",                 "a file of several frames: {0} / {1} (wheel)" } },
      { "window",     new[] { "Fenêtre C {0}  L {1}",                                             "Window C {0}  W {1}" } },
      { "tone",       new[] { "Luminosité {0}  Contraste {1}",                                    "Brightness {0}  Contrast {1}" } },
      { "bright",     new[] { "Luminosité",                                                       "Brightness" } },
      { "contrast",   new[] { "Contraste",                                                        "Contrast" } },
      { "zoom",       new[] { "zoom {0} %",                                                       "zoom {0} %" } },
      { "reading",    new[] { "Lecture de l'image…",                                              "Reading the image…" } },
      { "empty",      new[] { "Aucune image DICOM dans ce dossier.",                              "No DICOM image in this folder." } },
      { "choose",     new[] { "Choisissez le dossier (ou le disque) qui contient les images",     "Choose the folder (or the disc) that holds the images" } },
      { "pick",       new[] { "Choisissez une série dans la liste de gauche.",                    "Choose a series in the list on the left." } },
      { "noPicture",  new[] { "Ce fichier ne contient pas d'image (rapport de l'appareil).",      "This file holds no picture (a report of the device)." } },
      { "compressed", new[] { "Cette image ne peut pas être affichée ici (compression non prise en charge).\nOuvrez le disque avec un logiciel d'imagerie.",
                              "This image cannot be shown here (compression not supported).\nOpen the disc with imaging software." } },
      { "unsupported",new[] { "Cette image ne peut pas être affichée ici.\nOuvrez le disque avec un logiciel d'imagerie.",
                              "This image cannot be shown here.\nOpen the disc with imaging software." } },
      { "unreadable", new[] { "Ce fichier n'a pas pu être lu (disque abîmé ?).",                  "This file could not be read (damaged disc?)." } },
      { "helpText",   new[] {
          "Visionneuse d'images — pour consulter les images de ce disque.\nElle n'est pas destinée au diagnostic : pour un diagnostic, ouvrez le disque avec un logiciel d'imagerie médicale (fichier DICOMDIR).\n\n" +
          "Liste de gauche : les examens et leurs séries. Cliquez sur une série.\n\n" +
          "Molette : image précédente / suivante\nBouton gauche + glisser : luminosité (haut / bas) et contraste (gauche / droite) — aussi avec les deux curseurs en bas, sur les images en gris comme en couleur\nCtrl + molette : zoom\nBouton droit + glisser : déplacer l'image\nDouble-clic : ajuster à la fenêtre\n\n" +
          "Touches : ← → image   ↑ ↓ série   I inverser   R réinitialiser\n\n" +
          "Cette visionneuse ne s'installe pas et ne laisse rien sur cet ordinateur.\n\n" + Product.Name + " " + Product.Version,
          "Image viewer — for looking at the images of this disc.\nIt is not meant for diagnosis: for a diagnosis, open the disc with medical imaging software (file DICOMDIR).\n\n" +
          "List on the left: the exams and their series. Click a series.\n\n" +
          "Wheel: previous / next image\nLeft button + drag: brightness (up / down) and contrast (left / right) - also with the two sliders at the bottom, on grey and on colour images\nCtrl + wheel: zoom\nRight button + drag: move the image\nDouble-click: fit to the window\n\n" +
          "Keys: ← → image   ↑ ↓ series   I invert   R reset\n\n" +
          "This viewer installs nothing and leaves nothing on this computer.\n\n" + Product.Name + " " + Product.Version } },
    };

    public static string Get(string key) { string[] v; return T.TryGetValue(key, out v) ? v[Lang == "fr" ? 0 : 1] : key; }
    public static string Get(string key, params object[] a) { return string.Format(Get(key), a); }
  }
}
