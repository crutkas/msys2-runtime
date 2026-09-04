// Fork-aware debugger + cygheap chain walker.
// At the fault, read the child's memory directly and walk cygheap->chain to
// find exactly which entry carries the bad prev pointer and what it looks like.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Dbg3 {
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
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern uint GetModuleFileNameExW(IntPtr p, IntPtr m, StringBuilder n, uint sz);
  [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);

  static IntPtr proc;
  static string Where(long addr) {
    if (addr == 0) return "(null)";
    MBI m;
    if (VirtualQueryEx(proc, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero)
      return "UNMAPPED";
    string st = m.State == 0x1000 ? "committed" : m.State == 0x2000 ? "RESERVED-not-committed" : "free";
    var sb = new StringBuilder(260);
    string n = GetModuleFileNameExW(proc, m.AllocationBase, sb, 260) > 0
             ? System.IO.Path.GetFileName(sb.ToString()) : "(anon)";
    return string.Format("{0} [{1}] allocBase=0x{2:X}", n, st, m.AllocationBase.ToInt64());
  }
  static bool R64(long addr, out long val) {
    byte[] b = new byte[8]; IntPtr got;
    val = 0;
    if (!ReadProcessMemory(proc, (IntPtr)addr, b, (IntPtr)8, out got) || got.ToInt64() != 8) return false;
    val = BitConverter.ToInt64(b, 0); return true;
  }

  public static string Run(string exe, string cwd) {
    var sb = new StringBuilder();
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, null, IntPtr.Zero, IntPtr.Zero, false, 0x00000001, IntPtr.Zero, cwd, ref si, out pi))
      return "CreateProcess failed err=" + Marshal.GetLastWin32Error();
    int rootPid = pi.dwProcessId;
    var handles = new Dictionary<int,IntPtr>();
    handles[rootPid] = pi.hProcess;

    const long CYGHEAP_LOW  = 0x800000000L;
    const long CYGHEAP_HIGH = 0xa00000000L;

    byte[] ev = new byte[256];
    IntPtr ctxBuf = Marshal.AllocHGlobal(4096);
    bool done = false;
    while (!done && WaitForDebugEvent(ev, 30000)) {
      int code = BitConverter.ToInt32(ev, 0);
      int pid  = BitConverter.ToInt32(ev, 4);
      int tid  = BitConverter.ToInt32(ev, 8);
      uint cont = 0x00010002;
      if (code == 3) {
        IntPtr hp = (IntPtr)BitConverter.ToInt64(ev, 24);
        if (!handles.ContainsKey(pid)) handles[pid] = hp;
      }
      else if (code == 1) {
        uint ec = BitConverter.ToUInt32(ev, 16);
        bool first = BitConverter.ToInt32(ev, 168) != 0;
        if (ec != 0x80000003 && ec != 0x406D1388 && pid != rootPid) {
          proc = handles.ContainsKey(pid) ? handles[pid] : pi.hProcess;
          IntPtr th = OpenThread(0x001F03FF, false, tid);
          for (int i = 0; i < 4096; i++) Marshal.WriteByte(ctxBuf, i, 0);
          Marshal.WriteInt32(ctxBuf, 0, unchecked((int)0x00400007));
          if (th != IntPtr.Zero && GetThreadContext(th, ctxBuf)) {
            long x19 = Marshal.ReadInt64(ctxBuf, 0x008 + 19*8);
            long x20 = Marshal.ReadInt64(ctxBuf, 0x008 + 20*8);
            sb.AppendLine("CHILD pid=" + pid + " fault 0x" + ec.ToString("X8")
                          + (first ? " (first chance)" : " (second chance)"));
            sb.AppendLine("  x19 (rvc) = 0x" + x19.ToString("X16") + "  " + Where(x19));
            sb.AppendLine("  x20 (&cygheap in .data) = 0x" + x20.ToString("X16"));
            long cygheap;
            if (R64(x20 + 8, out cygheap)) {
              sb.AppendLine("  cygheap = 0x" + cygheap.ToString("X16") + "  " + Where(cygheap));
              sb.AppendLine("  expected range [0x" + CYGHEAP_LOW.ToString("X") + ", 0x"
                            + CYGHEAP_HIGH.ToString("X") + ")");
              sb.AppendLine("  --- walking cygheap->chain (prev at +8, b at +0) ---");
              long chain;
              if (R64(cygheap + 8, out chain)) {
                long rvc = chain; int n = 0;
                while (rvc != 0 && n < 60) {
                  bool inHeap = rvc >= CYGHEAP_LOW && rvc < CYGHEAP_HIGH;
                  long b, prev;
                  bool okB = R64(rvc, out b), okP = R64(rvc + 8, out prev);
                  sb.AppendLine(string.Format("   [{0,2}] rvc=0x{1:X16} {2} b/ptr=0x{3:X16} prev=0x{4:X16}{5}",
                    n, rvc, inHeap ? "IN-HEAP " : "OUT-OF-HEAP", okB ? b : -1, okP ? prev : -1,
                    okB ? "" : "  <== UNREADABLE: " + Where(rvc)));
                  if (!okB || !okP) { sb.AppendLine("   STOP: entry not readable in the child."); break; }
                  if (!inHeap) sb.AppendLine("   NOTE: this entry is OUTSIDE the cygheap: " + Where(rvc));
                  rvc = prev; n++;
                }
                sb.AppendLine("  walked " + n + " entries");
              } else sb.AppendLine("  could not read cygheap->chain");
            } else sb.AppendLine("  could not read cygheap pointer");
            CloseHandle(th);
          }
          done = true;
          cont = 0x80010001;
        }
      }
      else if (code == 5 && pid == rootPid) { ContinueDebugEvent(pid, tid, cont); break; }
      ContinueDebugEvent(pid, tid, cont);
    }
    Marshal.FreeHGlobal(ctxBuf);
    return sb.ToString();
  }
}
