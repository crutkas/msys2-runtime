// Walk cygheap->chain in ANY faulting process (root included), using the FIXED
// cygheap base 0x800000000 rather than a register, so it works without needing
// the fault to occur inside cygheap code.
// PURPOSE: decide whether the unterminated chain is fork-specific or is present
// in every process.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Dbg6 {
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
  [DllImport("kernel32")] static extern IntPtr VirtualQueryEx(IntPtr p, IntPtr a, out MBI b, IntPtr len);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern bool EnumProcessModulesEx(IntPtr p, [Out] IntPtr[] m, uint cb, out uint need, uint f);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern uint GetModuleBaseNameW(IntPtr p, IntPtr m, StringBuilder n, uint sz);
  [DllImport("kernel32", SetLastError=true)]
  static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] buf, IntPtr n, out IntPtr got);

  const long LOW = 0x800000000L, HIGH = 0xa00000000L;

  static string Region(IntPtr p, long a) {
    MBI m;
    if (VirtualQueryEx(p, (IntPtr)a, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) return "QUERY-FAIL";
    return (m.State == 0x1000 ? "COMMITTED" : m.State == 0x2000 ? "RESERVED" : "FREE")
           + " allocBase=0x" + m.AllocationBase.ToInt64().ToString("X")
           + " size=0x" + m.RegionSize.ToInt64().ToString("X");
  }
  static bool R64(IntPtr p, long a, out long v) {
    byte[] b = new byte[8]; IntPtr g; v = 0;
    if (!ReadProcessMemory(p, (IntPtr)a, b, (IntPtr)8, out g) || g.ToInt64() != 8) return false;
    v = BitConverter.ToInt64(b,0); return true;
  }

  public static string Walk(IntPtr h, string label) {
    var sb = new StringBuilder();
    sb.AppendLine("--- " + label + " ---");
    sb.AppendLine("  cygheap region @0x800000000: " + Region(h, LOW));
    long chain;
    if (!R64(h, LOW + 8, out chain)) { sb.AppendLine("  cannot read cygheap->chain"); return sb.ToString(); }
    sb.AppendLine("  cygheap->chain = 0x" + chain.ToString("X16"));
    long rvc = chain; int n = 0; long lowest = long.MaxValue;
    while (rvc != 0 && n < 500) {
      long b, prev;
      if (!R64(h, rvc, out b) || !R64(h, rvc + 8, out prev)) {
        sb.AppendLine("  [" + n + "] rvc=0x" + rvc.ToString("X") + " UNREADABLE  " + Region(h, rvc));
        sb.AppendLine("  >>> CHAIN IS BROKEN: walk died after " + n + " entries.");
        return sb.ToString();
      }
      if (rvc < lowest) lowest = rvc;
      if (prev != 0 && (prev < LOW || prev >= HIGH)) {
        sb.AppendLine("  [" + n + "] rvc=0x" + rvc.ToString("X") + "  b=0x" + b.ToString("X")
                      + "  prev=0x" + prev.ToString("X16") + "  <== OUT OF CYGHEAP");
        sb.AppendLine("      that prev: " + Region(h, prev));
        sb.AppendLine("  >>> CHAIN IS UNTERMINATED after " + (n+1) + " entries."
                      + "  lowest entry seen = 0x" + lowest.ToString("X"));
        return sb.ToString();
      }
      rvc = prev; n++;
    }
    sb.AppendLine("  >>> CHAIN TERMINATED CLEANLY with NULL after " + n + " entries."
                  + "  lowest entry = 0x" + lowest.ToString("X"));
    return sb.ToString();
  }

  // Dump the cygheap header and hunt for a given value inside it, to identify
  // which field (if any) aliases the wild chain terminator.
  // Dump memory around the deepest chain entry, to see whether the preceding
  // allocation looks like a buffer that ran up to (and past) the boundary.
  public static string Around(IntPtr h, long entry) {
    var sb = new StringBuilder();
    sb.AppendLine("--- 128 bytes BEFORE the deepest entry, then the entry itself ---");
    long start = entry - 128;
    byte[] buf = new byte[128 + 32]; IntPtr g;
    if (!ReadProcessMemory(h, (IntPtr)start, buf, (IntPtr)buf.Length, out g)) return "  unreadable\n";
    for (int off = 0; off < buf.Length; off += 16) {
      long a = start + off;
      var hex = new StringBuilder(); var asc = new StringBuilder();
      for (int i = 0; i < 16; i++) {
        byte b = buf[off+i];
        hex.Append(b.ToString("X2")).Append(i == 7 ? "-" : " ");
        asc.Append(b >= 32 && b < 127 ? (char)b : '.');
      }
      string mark = a == entry ? "  <== ENTRY (b field)" : a == entry + 8 ? "" : "";
      if (a == entry - 16) mark = "  <-- last 16B of the PRECEDING allocation";
      sb.AppendLine(string.Format("   0x{0:X} {1} |{2}|{3}", a, hex, asc, mark));
    }
    sb.AppendLine("   (entry+8 = the prev slot = 0x" + (entry+8).ToString("X") + ")");
    return sb.ToString();
  }

  public static string Header(IntPtr h, long hunt) {
    var sb = new StringBuilder();
    sb.AppendLine("--- cygheap header, first 0x140 bytes ---");
    byte[] buf = new byte[0x140]; IntPtr g;
    long lo = LOW;
    if (!ReadProcessMemory(h, (IntPtr)lo, buf, (IntPtr)buf.Length, out g)) return "  unreadable\n";
    for (int off = 0; off < buf.Length; off += 8) {
      long v = BitConverter.ToInt64(buf, off);
      string name = off == 0 ? "  locale.mbtowc" : off == 8 ? "  chain        "
                  : (off >= 16 && off < 16 + 32*8) ? "  buckets[" + ((off-16)/8) + "]" : "  +0x" + off.ToString("X");
      if (v != 0 || off < 24)
        sb.AppendLine(string.Format("   {0,-16} @+0x{1:X3} = 0x{2:X16}{3}", name, off, v,
                      (hunt != 0 && v == hunt) ? "   <<<<<< MATCHES THE WILD TERMINATOR" : ""));
    }
    return sb.ToString();
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
        if (ec != 0x80000003 && ec != 0x406D1388) {
          IntPtr h = H.ContainsKey(pid) ? H[pid] : pi.hProcess;
          sb.AppendLine("fault 0x" + ec.ToString("X8") + " in pid=" + pid
                        + (pid == rootPid ? "  (ROOT - never forked)" : "  (child)"));
          sb.Append(Walk(h, pid == rootPid ? "ROOT PROCESS cygheap chain" : "CHILD cygheap chain"));
          // find the wild terminator value again so we can hunt for it
          long chain2, wild = 0, deepest = 0;
          if (R64(h, LOW + 8, out chain2)) {
            long r = chain2; int k = 0;
            while (r != 0 && k < 500) {
              long pv;
              if (!R64(h, r + 8, out pv)) break;
              if (pv != 0 && (pv < LOW || pv >= HIGH)) { wild = pv; deepest = r; break; }
              r = pv; k++;
            }
          }
          sb.AppendLine("--- loaded modules ---");
          {
            IntPtr[] mods = new IntPtr[1024]; uint need;
            if (EnumProcessModulesEx(h, mods, (uint)(mods.Length*IntPtr.Size), out need, 3)) {
              int n = (int)(need / IntPtr.Size);
              var names = new List<string>();
              for (int i = 0; i < n; i++) {
                var nm = new StringBuilder(260);
                if (GetModuleBaseNameW(h, mods[i], nm, 260) > 0) names.Add(nm.ToString());
              }
              names.Sort();
              sb.AppendLine("   count=" + names.Count + ": " + string.Join(" ", names));
              bool net = names.Exists(s => s.ToLower().StartsWith("netapi32") || s.ToLower().StartsWith("netutils")
                                        || s.ToLower().StartsWith("samcli")   || s.ToLower().StartsWith("logoncli"));
              sb.AppendLine("   netapi32/netutils/samcli/logoncli PRESENT? " + (net ? "YES" : "NO"));
            }
          }
          sb.AppendLine();
          sb.AppendLine("--- THREAD_STORAGE arena [0x600000000,0x800000000) region scan ---");
          {
            long a = 0x600000000L; int nreg = 0; long topEnd = 0;
            while (a < 0x800000000L && nreg < 200) {
              MBI m;
              if (VirtualQueryEx(h, (IntPtr)a, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
              long rb = m.BaseAddress.ToInt64(), rs = m.RegionSize.ToInt64();
              if (m.State != 0x10000) {   // not MEM_FREE
                sb.AppendLine(string.Format("   0x{0:X}..0x{1:X}  {2}  size=0x{3:X}",
                  rb, rb+rs, m.State==0x1000?"COMMITTED":"RESERVED ", rs));
                nreg++;
                if (rb + rs > topEnd) topEnd = rb + rs;
              }
              a = rb + rs;
            }
            if (nreg == 0) sb.AppendLine("   (no committed or reserved regions in the thread arena)");
            else sb.AppendLine("   highest end address in arena = 0x" + topEnd.ToString("X")
                               + (topEnd == 0x800000000L ? "   <<<<<< TOUCHES THE CYGHEAP BOUNDARY" : "   (does not reach 0x800000000)"));
          }
          sb.AppendLine();
          sb.AppendLine("--- targeted entry reads (measured, not inferred) ---");
          foreach (long ea in new long[]{0x8000048A0L, 0x8000050B0L, 0x8000068C0L, 0x8000068F0L}) {
            long bb, pp;
            if (R64(h, ea, out bb) && R64(h, ea+8, out pp))
              sb.AppendLine(string.Format("   entry 0x{0:X}  b={1}  prev=0x{2:X16}", ea, bb, pp));
            else sb.AppendLine(string.Format("   entry 0x{0:X}  UNREADABLE", ea));
          }
          sb.Append(Header(h, wild));
          if (deepest != 0) sb.Append(Around(h, deepest));
          done = true; cont = 0x80010001;
        }
      }
      else if (code == 5 && pid == rootPid) break;
      ContinueDebugEvent(pid, tid, cont);
    }
    return sb.ToString();
  }
}




