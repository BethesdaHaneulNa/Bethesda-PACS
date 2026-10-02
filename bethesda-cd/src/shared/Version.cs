// Bethesda CD - the one place its name and version are written. Compiled into both
// programs (Bethesda-CD.exe and the viewer VIEWER.EXE): what the window shows, what
// Windows shows in a file's properties and what CHANGELOG.md says are this number.
using System.Reflection;

[assembly: AssemblyProduct(Bethesda.Product.Name)]
[assembly: AssemblyVersion(Bethesda.Product.Version + ".0")]
[assembly: AssemblyFileVersion(Bethesda.Product.Version + ".0")]
[assembly: AssemblyInformationalVersion(Bethesda.Product.Version)]
[assembly: AssemblyCopyright("Bethesda EMR project - see LICENSE")]

namespace Bethesda {
  public static class Product {
    public const string Name = "Bethesda CD";
    public const string Version = "1.0.0";
  }
}
