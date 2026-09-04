// Corrected fault capture. Fixes the flaws the coordinator rightly flagged in r03:
//  - resolves the module base AT FAULT TIME via GetModuleHandleW, so RVA is real
//  - ignores CLR exception 0xE0434352 (harness noise, not the DLL)
//  - only treats 0xC0000005 with NumberParameters==2 as an access violation
//  - no map-only pre-load, so DllMain genuinely runs
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class Fault {
  public static string OutFile;
  public static string DllName;

  [StructLayout(LayoutKind.Sequential)]
  public struct ER {
    public uint Code; public uint Flags; public IntPtr Rec; public IntPtr Addr;
    public uint NumParams;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=15)] public IntPtr[] Info;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct EP { public IntPtr Rec; public IntPtr Ctx; }

  public delegate int VEH(IntPtr p);
  static VEH keep;

  [DllImport("kernel32")] static extern IntPtr AddVectoredExceptionHandler(uint f, VEH h);
  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern IntPtr LoadLibraryExW(string p, IntPtr h, uint f);
  [DllImport("kernel32", CharSet=CharSet.Unicode)]
  static extern IntPtr GetModuleHandleW(string n);

  static int Handler(IntPtr p) {
    try {
      EP ep = (EP)Marshal.PtrToStructure(p, typeof(EP));
      ER er = (ER)Marshal.PtrToStructure(ep.Rec, typeof(ER));
      if (er.Code == 0xE0434352 || er.Code == 0x406D1388 || er.Code == 0x4242420)
        return 0;                                   // CLR / debug noise
      string s = "EXCEPTION 0x" + er.Code.ToString("X8");
      if (er.Code == 0xC0000005 && er.NumParams >= 2) {
        long op = er.Info[0].ToInt64();
        s += "  ACCESS_VIOLATION " + (op == 0 ? "READ" : op == 1 ? "WRITE" : "EXEC")
           + " target=0x" + er.Info[1].ToInt64().ToString("X16");
      }
      s += "\n  at 0x" + er.Addr.ToInt64().ToString("X16");
      IntPtr b = GetModuleHandleW(DllName);
      if (b != IntPtr.Zero) {
        s += "\n  module base 0x" + b.ToInt64().ToString("X16");
        s += "\n  RVA 0x" + (er.Addr.ToInt64() - b.ToInt64()).ToString("X");
        s += "\n  file VA (base 0x180000000) 0x"
           + (0x180000000L + (er.Addr.ToInt64() - b.ToInt64())).ToString("X");
      } else s += "\n  module not yet in loader list";
      s += "\n----\n";
      File.AppendAllText(OutFile, s);
    } catch { }
    return 0;
  }

  public static string Go(string path, string outfile) {
    OutFile = outfile;
    DllName = Path.GetFileName(path);
    if (File.Exists(outfile)) File.Delete(outfile);
    keep = new VEH(Handler);
    AddVectoredExceptionHandler(1, keep);
    IntPtr h = LoadLibraryExW(path, IntPtr.Zero, 0);
    int err = Marshal.GetLastWin32Error();
    return h != IntPtr.Zero
      ? ("LOADED base=0x" + h.ToInt64().ToString("X"))
      : ("FAILED lasterror=" + err);
  }
}
