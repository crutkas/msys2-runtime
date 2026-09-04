// CHUNK vs SEGMENT discriminator.
// Reads dlmalloc's _gm_ segment list directly from the live process and asks
// whether the wild cygheap chain terminator lies INSIDE a dlmalloc segment.
//
//   _ZL4_gm_ : RVA 0x303250   (VA 0x180343250, ImageBase 0x180040000 - both read)
//   offsetof(malloc_state, seg) = 888
//   malloc_segment { char *base @0; size_t size @8; msegment *next @16; flag_t sflags @24 }
//
// base <= V < base+size  => V is a CHUNK inside that segment
// V == base exactly      => V is a SEGMENT BASE
// no segment contains V  => V comes from somewhere else entirely
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class GmTest {
  [StructLayout(LayoutKind.Sequential)]
  struct STARTUPINFO { public int cb; public IntPtr r1,r2,r3;
    public int dwX,dwY,dwXSize,dwYSize,dwXCount,dwYCount,dwFillAttribute,dwFlags;
    public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)]
  struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [StructLayout(LayoutKind.Sequential)]
  struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public int pad;
    public IntPtr RegionSize; public uint State, Protect, Type; }

  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inh,
    uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32")] static extern bool WaitForDebugEvent(byte[] ev, uint ms);
  [DllImport("kernel32")] static extern bool ContinueDebugEvent(int pid, int tid, uint status);
  [DllImport("kernel32", SetLastError=true)]
  static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] buf, IntPtr n, out IntPtr got);
  [DllImport("kernel32")] static extern IntPtr VirtualQueryEx(IntPtr p, IntPtr a, out MBI b, IntPtr len);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern bool EnumProcessModulesEx(IntPtr p, [Out] IntPtr[] m, uint cb, out uint needed, uint filter);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern uint GetModuleBaseNameW(IntPtr p, IntPtr m, StringBuilder n, uint sz);
  [DllImport("kernel32")] static extern bool TerminateProcess(IntPtr h, uint c);

  const long LOW = 0x800000000L, HIGH = 0xa00000000L;
  const long GM_RVA = 0x303250L;      // read from nm, minus ImageBase read from the header
  const long SEG_OFF = 888L;

  static bool R64(IntPtr p, long a, out long v) {
    byte[] b = new byte[8]; IntPtr g; v = 0;
    if (!ReadProcessMemory(p, (IntPtr)a, b, (IntPtr)8, out g) || g.ToInt64() != 8) return false;
    v = BitConverter.ToInt64(b,0); return true;
  }
  static string Region(IntPtr p, long a) {
    MBI m;
    if (VirtualQueryEx(p, (IntPtr)a, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) return "QUERY-FAIL";
    return (m.State == 0x1000 ? "COMMITTED" : m.State == 0x2000 ? "RESERVED" : "FREE")
           + " allocBase=0x" + m.AllocationBase.ToInt64().ToString("X");
  }

  public static string Run(string exe, string cwd) {
    var sb = new StringBuilder();
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, null, IntPtr.Zero, IntPtr.Zero, false, 1, IntPtr.Zero, cwd, ref si, out pi))
      return "CreateProcess failed";
    int rootPid = pi.dwProcessId;
    var H = new Dictionary<int,IntPtr>(); H[rootPid] = pi.hProcess;
    byte[] ev = new byte[256]; bool done = false;

    while (!done && WaitForDebugEvent(ev, 30000)) {
      int code = BitConverter.ToInt32(ev,0), pid = BitConverter.ToInt32(ev,4), tid = BitConverter.ToInt32(ev,8);
      uint cont = 0x00010002;
      if (code == 3) { IntPtr hp=(IntPtr)BitConverter.ToInt64(ev,24); if(!H.ContainsKey(pid)) H[pid]=hp; }
      else if (code == 1) {
        uint ec = BitConverter.ToUInt32(ev,16);
        if (ec == 0xC0000005 && pid == rootPid) {      // rung9's deliberate fault
          IntPtr h = H[pid];
          // locate msys-2.0.dll load base
          IntPtr[] mods = new IntPtr[512]; uint need;
          long dllBase = 0;
          if (EnumProcessModulesEx(h, mods, (uint)(mods.Length*IntPtr.Size), out need, 3)) {
            int n = (int)(need / IntPtr.Size);
            for (int i = 0; i < n; i++) {
              var nm = new StringBuilder(260);
              if (GetModuleBaseNameW(h, mods[i], nm, 260) > 0 &&
                  nm.ToString().ToLower().Contains("msys-2.0")) { dllBase = mods[i].ToInt64(); break; }
            }
          }
          sb.AppendLine("msys-2.0.dll load base = 0x" + dllBase.ToString("X"));
          if (dllBase == 0) { sb.AppendLine("could not locate the DLL"); done = true; goto cont2; }

          long gm = dllBase + GM_RVA;
          sb.AppendLine("_gm_ = 0x" + gm.ToString("X") + "   (RVA 0x" + GM_RVA.ToString("X") + ")");

          // find the wild terminator
          long chain, wild = 0;
          R64(h, LOW + 8, out chain);
          long rvc = chain; int k = 0;
          while (rvc != 0 && k < 500) {
            long prev;
            if (!R64(h, rvc + 8, out prev)) break;
            if (prev != 0 && (prev < LOW || prev >= HIGH)) { wild = prev; break; }
            rvc = prev; k++;
          }
          sb.AppendLine("wild chain terminator = 0x" + wild.ToString("X16") + "   " + Region(h, wild));
          sb.AppendLine();
          sb.AppendLine("--- dlmalloc _gm_ segment list ---");
          long seg = gm + SEG_OFF; int s = 0; bool inside = false, isBase = false;
          while (seg != 0 && s < 64) {
            long b, size, next;
            if (!R64(h, seg, out b) || !R64(h, seg+8, out size) || !R64(h, seg+16, out next)) {
              sb.AppendLine("  [" + s + "] unreadable at 0x" + seg.ToString("X")); break;
            }
            sb.AppendLine(string.Format("  [{0}] base=0x{1:X16} size=0x{2:X} (end 0x{3:X})",
                          s, b, size, b + size));
            if (wild != 0 && b != 0) {
              if (wild == b) isBase = true;
              else if (wild >= b && wild < b + size) inside = true;
            }
            if (next == 0 || b == 0) break;
            seg = next; s++;
          }
          sb.AppendLine();
          sb.AppendLine(">>> VERDICT:");
          if (isBase)      sb.AppendLine("    The wild value EQUALS a dlmalloc SEGMENT BASE.");
          else if (inside) sb.AppendLine("    The wild value lies INSIDE a dlmalloc segment => it is a CHUNK pointer.");
          else             sb.AppendLine("    The wild value is in NO dlmalloc segment => it did NOT come from dlmalloc at all.");
          done = true;
        }
        else if (ec != 0x80000003) cont = 0x80010001;
      }
      else if (code == 5 && pid == rootPid) break;
      cont2:
      ContinueDebugEvent(pid, tid, cont);
    }
    TerminateProcess(pi.hProcess, 1);
    return sb.ToString();
  }
}
