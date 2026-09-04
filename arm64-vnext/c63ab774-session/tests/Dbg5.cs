// Test one specific hypothesis: the bad prev 0x80002D1000 differs from a valid
// cygheap pointer 0x8002D1000 in exactly one byte (byte[4]: 0x80 vs 0x08).
// If 0x8002D1000 contains a well-formed _cmalloc_entry (bucket < 32, prev
// in-heap) then the intended pointer was that, and the stored one is corrupt.
// If it contains nothing sensible, the hypothesis is dead and the pointer is
// a genuine reference to an mmap region that fork failed to reproduce.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Dbg5 {
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
  [DllImport("kernel32")] static extern IntPtr OpenThread(uint acc, bool inh, int tid);
  [DllImport("kernel32")] static extern bool GetThreadContext(IntPtr t, IntPtr ctx);
  [DllImport("kernel32")] static extern IntPtr VirtualQueryEx(IntPtr p, IntPtr a, out MBI b, IntPtr len);
  [DllImport("kernel32", SetLastError=true)]
  static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] buf, IntPtr n, out IntPtr got);
  [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);

  static string Region(IntPtr p, long a) {
    MBI m;
    if (VirtualQueryEx(p, (IntPtr)a, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) return "QUERY-FAIL";
    return (m.State == 0x1000 ? "COMMITTED" : m.State == 0x2000 ? "RESERVED" : "FREE")
           + " allocBase=0x" + m.AllocationBase.ToInt64().ToString("X");
  }
  static bool R(IntPtr p, long a, byte[] b) { IntPtr g;
    return ReadProcessMemory(p, (IntPtr)a, b, (IntPtr)b.Length, out g) && g.ToInt64() == b.Length; }
  static bool R64(IntPtr p, long a, out long v) { byte[] b = new byte[8]; v = 0;
    if (!R(p, a, b)) return false; v = BitConverter.ToInt64(b, 0); return true; }

  public static string Run(string exe, string cwd) {
    var sb = new StringBuilder();
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, null, IntPtr.Zero, IntPtr.Zero, false, 1, IntPtr.Zero, cwd, ref si, out pi))
      return "CreateProcess failed";
    int rootPid = pi.dwProcessId; IntPtr hP = pi.hProcess;
    var H = new Dictionary<int,IntPtr>(); H[rootPid] = hP;
    const long LOW = 0x800000000L, HIGH = 0xa00000000L;
    byte[] ev = new byte[256]; IntPtr ctx = Marshal.AllocHGlobal(4096); bool done = false;

    while (!done && WaitForDebugEvent(ev, 30000)) {
      int code = BitConverter.ToInt32(ev,0), pid = BitConverter.ToInt32(ev,4), tid = BitConverter.ToInt32(ev,8);
      uint cont = 0x00010002;
      if (code == 3) { IntPtr hp=(IntPtr)BitConverter.ToInt64(ev,24); if(!H.ContainsKey(pid)) H[pid]=hp; }
      else if (code == 1) {
        uint ec = BitConverter.ToUInt32(ev,16);
        if (ec != 0x80000003 && ec != 0x406D1388 && pid != rootPid) {
          IntPtr hC = H.ContainsKey(pid) ? H[pid] : IntPtr.Zero;
          IntPtr th = OpenThread(0x001F03FF,false,tid);
          for (int i=0;i<4096;i++) Marshal.WriteByte(ctx,i,0);
          Marshal.WriteInt32(ctx,0,unchecked((int)0x00400007));
          if (th != IntPtr.Zero && GetThreadContext(th, ctx)) {
            long x20 = Marshal.ReadInt64(ctx, 0x008+20*8), cygheap, chain, prev = 0, bad = 0, badSlot = 0;
            R64(hC, x20+8, out cygheap); R64(hC, cygheap+8, out chain);
            long rvc = chain; int n=0;
            while (rvc != 0 && n < 200) {
              if (!R64(hC, rvc+8, out prev)) break;
              if (prev != 0 && (prev < LOW || prev >= HIGH)) { bad = prev; badSlot = rvc; break; }
              rvc = prev; n++;
            }
            if (bad == 0) { sb.AppendLine("no bad prev this run"); }
            else {
              byte[] raw = BitConverter.GetBytes(bad);
              sb.AppendLine("bad prev      = 0x" + bad.ToString("X16") + "   bytes " + BitConverter.ToString(raw));
              sb.AppendLine("  held in entry 0x" + badSlot.ToString("X") + " at slot +8");
              sb.AppendLine("  parent: " + Region(hP, bad) + "   child: " + Region(hC, bad));
              sb.AppendLine();
              sb.AppendLine("=== TEST A: is the bad target a well-formed _cmalloc_entry IN THE PARENT? ===");
              byte[] pe = new byte[32];
              if (R(hP, bad, pe)) {
                long pb = BitConverter.ToInt64(pe,0), pp = BitConverter.ToInt64(pe,8);
                sb.AppendLine("  32 bytes at 0x" + bad.ToString("X") + " (PARENT): " + BitConverter.ToString(pe));
                sb.AppendLine("    b/ptr = 0x" + pb.ToString("X16"));
                sb.AppendLine("    prev  = 0x" + pp.ToString("X16") + "  in-cygheap? "
                              + (pp == 0 ? "NULL terminator" : (pp >= LOW && pp < HIGH ? "YES" : "NO")));
                bool wf = ((ulong)pb < 32 || (pb >= LOW && pb < HIGH)) && (pp == 0 || (pp >= LOW && pp < HIGH));
                sb.AppendLine("  >>> " + (wf
                  ? "WELL-FORMED in the parent. The chain LEGITIMATELY extends outside the cygheap;"
                    + " the child's failure is that this region was not reproduced."
                  : "NOT well-formed even in the parent. The chain itself is bad / over-walked."));
              } else sb.AppendLine("  UNREADABLE even in the parent.");
              sb.AppendLine();
              sb.AppendLine("=== TEST B: byte[4] 0x80-vs-0x08 corruption hypothesis ===");
              // hypothesis: byte[4] should be 0x08 not 0x80
              byte[] fix = (byte[])raw.Clone(); fix[4] = 0x08;
              long cand = BitConverter.ToInt64(fix, 0);
              sb.AppendLine("HYPOTHESIS candidate = 0x" + cand.ToString("X16") + "   bytes " + BitConverter.ToString(fix));
              sb.AppendLine("  in cygheap range? " + (cand >= LOW && cand < HIGH ? "YES" : "NO"));
              sb.AppendLine("  parent: " + Region(hP, cand) + "   child: " + Region(hC, cand));
              byte[] e = new byte[32];
              if (R(hC, cand, e)) {
                sb.AppendLine("  32 bytes at candidate (child): " + BitConverter.ToString(e));
                long b0 = BitConverter.ToInt64(e,0), p0 = BitConverter.ToInt64(e,8);
                sb.AppendLine("    interpreted as _cmalloc_entry:");
                sb.AppendLine("      b/ptr = 0x" + b0.ToString("X16") + "   bucket<32? "
                              + ((ulong)b0 < 32 ? "YES" : "no (may be a ptr union)"));
                sb.AppendLine("      prev  = 0x" + p0.ToString("X16") + "   in-heap? "
                              + ((p0 == 0) ? "NULL (list terminator)" : (p0 >= LOW && p0 < HIGH ? "YES" : "NO")));
                sb.AppendLine();
                bool wellFormed = ((ulong)b0 < 32 || (b0 >= LOW && b0 < HIGH))
                                  && (p0 == 0 || (p0 >= LOW && p0 < HIGH));
                sb.AppendLine("  >>> VERDICT: " + (wellFormed
                  ? "WELL-FORMED _cmalloc_entry. Hypothesis SUPPORTED: the stored pointer is corrupt in byte[4]."
                  : "NOT a well-formed entry. Hypothesis REFUTED: treat 0x" + bad.ToString("X")
                    + " as a genuine reference to a region fork did not reproduce."));
              } else sb.AppendLine("  candidate unreadable in child: hypothesis not supported");
            }
            CloseHandle(th);
          }
          done = true; cont = 0x80010001;
        }
      }
      else if (code == 5 && pid == rootPid) { ContinueDebugEvent(pid,tid,cont); break; }
      ContinueDebugEvent(pid,tid,cont);
    }
    Marshal.FreeHGlobal(ctx);
    return sb.ToString();
  }
}
