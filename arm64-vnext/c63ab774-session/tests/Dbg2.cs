// Fork-aware Win32 debugger. Launches under DEBUG_PROCESS so it follows
// children (which is the whole point: Cygwin's fork child is a separate
// Windows process), tracks a process handle per pid so VirtualQueryEx resolves
// modules IN THE FAULTING PROCESS, and reports the full ARM64 context.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Dbg2 {
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
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern uint GetModuleFileNameExW(IntPtr p, IntPtr m, StringBuilder n, uint sz);
  [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32")] static extern bool TerminateProcess(IntPtr h, uint c);

  static IntPtr proc;
  static string Where(long addr) {
    if (addr == 0) return "(null)";
    MBI m;
    if (VirtualQueryEx(proc, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero)
      return "UNMAPPED";
    if (m.State != 0x1000) return "not committed";
    var sb = new StringBuilder(260);
    string n = GetModuleFileNameExW(proc, m.AllocationBase, sb, 260) > 0
             ? System.IO.Path.GetFileName(sb.ToString()) : "(anon)";
    return string.Format("{0} base=0x{1:X} RVA=0x{2:X}", n, m.AllocationBase.ToInt64(),
                         addr - m.AllocationBase.ToInt64());
  }

  public static string Run(string exe, string cwd) {
    var sb = new StringBuilder();
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
    PROCESS_INFORMATION pi;
    // 0x00000001 = DEBUG_PROCESS: follow children too.
    if (!CreateProcessW(exe, null, IntPtr.Zero, IntPtr.Zero, false, 0x00000001, IntPtr.Zero, cwd, ref si, out pi))
      return "CreateProcess failed err=" + Marshal.GetLastWin32Error();
    int rootPid = pi.dwProcessId;
    var handles = new Dictionary<int,IntPtr>();
    handles[rootPid] = pi.hProcess;
    sb.AppendLine("root (parent) pid = " + rootPid);

    byte[] ev = new byte[256];
    IntPtr ctxBuf = Marshal.AllocHGlobal(4096);
    int faults = 0;
    while (WaitForDebugEvent(ev, 30000)) {
      int code = BitConverter.ToInt32(ev, 0);
      int pid  = BitConverter.ToInt32(ev, 4);
      int tid  = BitConverter.ToInt32(ev, 8);
      uint cont = 0x00010002; // DBG_CONTINUE
      string who = (pid == rootPid) ? "PARENT" : "CHILD";

      if (code == 3) { // CREATE_PROCESS_DEBUG_EVENT: union at 16 -> hFile,hProcess
        IntPtr hp = (IntPtr)BitConverter.ToInt64(ev, 24);
        if (!handles.ContainsKey(pid)) handles[pid] = hp;
        if (pid != rootPid) sb.AppendLine(">>> CHILD PROCESS CREATED, pid=" + pid + "  (fork child)");
      }
      else if (code == 1) { // EXCEPTION_DEBUG_EVENT
        uint ec   = BitConverter.ToUInt32(ev, 16);
        long addr = BitConverter.ToInt64(ev, 32);
        uint np   = BitConverter.ToUInt32(ev, 40);
        long p0   = np >= 1 ? BitConverter.ToInt64(ev, 48) : 0;
        long p1   = np >= 2 ? BitConverter.ToInt64(ev, 56) : 0;
        bool first = BitConverter.ToInt32(ev, 168) != 0;
        if (ec == 0x80000003 || ec == 0x406D1388 || ec == 0x4242420) { }
        else {
          faults++;
          proc = handles.ContainsKey(pid) ? handles[pid] : pi.hProcess;
          sb.AppendLine("=== " + who + " pid=" + pid + "  EXCEPTION 0x" + ec.ToString("X8")
                        + (first ? " (first chance)" : " (SECOND CHANCE - fatal)"));
          if (ec == 0xC0000005 && np >= 2)
            sb.AppendLine("  ACCESS_VIOLATION " + (p0==0?"READ":p0==1?"WRITE":p0==8?"EXECUTE":p0.ToString())
                          + " target=0x" + p1.ToString("X16") + "   " + Where(p1));
          if (ec == 0xC00000FD) sb.AppendLine("  STACK_OVERFLOW");
          sb.AppendLine("  ExceptionAddress = 0x" + addr.ToString("X16") + "   " + Where(addr));
          for (int i = 0; i < 4096; i++) Marshal.WriteByte(ctxBuf, i, 0);
          Marshal.WriteInt32(ctxBuf, 0, unchecked((int)0x00400007));
          IntPtr th = OpenThread(0x001F03FF, false, tid);
          if (th != IntPtr.Zero && GetThreadContext(th, ctxBuf)) {
            long pc = Marshal.ReadInt64(ctxBuf, 0x108);
            long sp = Marshal.ReadInt64(ctxBuf, 0x100);
            long lr = Marshal.ReadInt64(ctxBuf, 0x008 + 30*8);
            sb.AppendLine("  PC = 0x" + pc.ToString("X16") + "   " + Where(pc));
            sb.AppendLine("  LR = 0x" + lr.ToString("X16") + "   " + Where(lr) + "   <-- CALLER");
            sb.AppendLine("  SP = 0x" + sp.ToString("X16") + "   16-aligned: " + ((sp & 15) == 0 ? "YES" : "NO"));
            for (int i = 0; i <= 30; i++)
              sb.AppendLine(string.Format("  x{0,-2} = 0x{1:X16}   {2}", i,
                            Marshal.ReadInt64(ctxBuf, 0x008 + i*8),
                            Where(Marshal.ReadInt64(ctxBuf, 0x008 + i*8))));
            CloseHandle(th);
          } else sb.AppendLine("  (GetThreadContext failed err=" + Marshal.GetLastWin32Error() + ")");
          sb.AppendLine("----");
          if (!first) cont = 0x00010002; else cont = 0x80010001; // let it reach second chance
          if (faults > 8) { sb.AppendLine("(too many faults, stopping)"); break; }
        }
      }
      else if (code == 5) { // EXIT_PROCESS
        uint xc = BitConverter.ToUInt32(ev, 16);
        sb.AppendLine("<<< " + who + " pid=" + pid + " exited, code=" + xc
                      + " (0x" + xc.ToString("X8") + ")");
        if (pid == rootPid) { ContinueDebugEvent(pid, tid, cont); break; }
      }
      ContinueDebugEvent(pid, tid, cont);
    }
    Marshal.FreeHGlobal(ctxBuf);
    return sb.ToString();
  }
}
