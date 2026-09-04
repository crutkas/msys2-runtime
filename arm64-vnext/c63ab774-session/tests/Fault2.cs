// Fault capture v2. Fixes the deficiencies in my earlier harness:
//   - dumps the FULL ARM64 CONTEXT: x0-x30, Sp, Pc, Cpsr
//   - captures x30 (LR) -- WHO branched, not just where
//   - resolves module bases with VirtualQuery AT FAULT TIME on both Pc and Lr,
//     never from an assumed ImageBase (that assumption invalidated my earlier work)
//   - reports which register held the faulting target
//
// ARM64 CONTEXT layout: ContextFlags@0x000 Cpsr@0x004 X[0..30]@0x008..0x0FF
//                       Sp@0x100 Pc@0x108
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class Fault2 {
  public static string OutFile;

  [StructLayout(LayoutKind.Sequential)]
  public struct ER {
    public uint Code; public uint Flags; public IntPtr Rec; public IntPtr Addr;
    public uint NumParams;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=15)] public IntPtr[] Info;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct EP { public IntPtr Rec; public IntPtr Ctx; }

  [StructLayout(LayoutKind.Sequential)]
  public struct MBI {
    public IntPtr BaseAddress, AllocationBase;
    public uint AllocationProtect; public int __pad;
    public IntPtr RegionSize;
    public uint State, Protect, Type;
  }

  public delegate int VEH(IntPtr p);
  static VEH keep;

  [DllImport("kernel32")] static extern IntPtr AddVectoredExceptionHandler(uint f, VEH h);
  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern IntPtr LoadLibraryExW(string p, IntPtr h, uint f);
  [DllImport("kernel32")] static extern IntPtr VirtualQuery(IntPtr a, out MBI b, IntPtr len);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern uint GetModuleFileNameExW(IntPtr proc, IntPtr mod, System.Text.StringBuilder n, uint sz);
  [DllImport("kernel32")] static extern IntPtr GetCurrentProcess();

  static string Where(IntPtr addr) {
    if (addr == IntPtr.Zero) return "(null)";
    MBI m;
    if (VirtualQuery(addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero)
      return "UNMAPPED";
    if (m.State != 0x1000) return "not committed (State=0x" + m.State.ToString("X") + ")";
    var sb = new System.Text.StringBuilder(260);
    string name = GetModuleFileNameExW(GetCurrentProcess(), m.AllocationBase, sb, 260) > 0
                ? Path.GetFileName(sb.ToString()) : "(anon)";
    long rva = addr.ToInt64() - m.AllocationBase.ToInt64();
    return string.Format("{0} base=0x{1:X} RVA=0x{2:X}", name, m.AllocationBase.ToInt64(), rva);
  }

  static int Handler(IntPtr p) {
    try {
      EP ep = (EP)Marshal.PtrToStructure(p, typeof(EP));
      ER er = (ER)Marshal.PtrToStructure(ep.Rec, typeof(ER));
      if (er.Code == 0xE0434352 || er.Code == 0x406D1388) return 0;   // CLR noise
      var s = new System.Text.StringBuilder();
      s.AppendLine("EXCEPTION 0x" + er.Code.ToString("X8") + "  params=" + er.NumParams);
      if (er.Code == 0xC0000005 && er.NumParams >= 2) {
        long op = er.Info[0].ToInt64();
        s.AppendLine("  ACCESS_VIOLATION " + (op == 0 ? "READ" : op == 1 ? "WRITE" : op == 8 ? "EXECUTE" : op.ToString())
                     + " target=0x" + er.Info[1].ToInt64().ToString("X16"));
      }
      IntPtr c = ep.Ctx;
      long pc = Marshal.ReadInt64(c, 0x108);
      long sp = Marshal.ReadInt64(c, 0x100);
      long lr = Marshal.ReadInt64(c, 0x008 + 30 * 8);
      s.AppendLine("  PC  = 0x" + pc.ToString("X16") + "   " + Where((IntPtr)pc));
      s.AppendLine("  LR  = 0x" + lr.ToString("X16") + "   " + Where((IntPtr)lr) + "   <-- WHO BRANCHED");
      s.AppendLine("  SP  = 0x" + sp.ToString("X16"));
      for (int i = 0; i <= 30; i++) {
        long v = Marshal.ReadInt64(c, 0x008 + i * 8);
        string tag = (v == pc && pc != 0) ? "   <== held the faulting target" : "";
        s.AppendLine(string.Format("  x{0,-2} = 0x{1:X16}{2}", i, v, tag));
      }
      s.AppendLine("----");
      File.AppendAllText(OutFile, s.ToString());
    } catch (Exception e) { try { File.AppendAllText(OutFile, "handler err: " + e + "\n"); } catch {} }
    return 0;
  }

  public static string Go(string path, string outfile) {
    OutFile = outfile;
    if (File.Exists(outfile)) File.Delete(outfile);
    keep = new VEH(Handler);
    AddVectoredExceptionHandler(1, keep);
    IntPtr h = LoadLibraryExW(path, IntPtr.Zero, 0);
    return h != IntPtr.Zero ? "LOADED 0x" + h.ToInt64().ToString("X")
                            : "FAILED err=" + Marshal.GetLastWin32Error();
  }
}
