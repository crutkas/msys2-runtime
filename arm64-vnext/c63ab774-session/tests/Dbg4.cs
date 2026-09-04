// Read the SAME cygheap chain slot in BOTH parent and child.
// Discriminator: if the parent holds a sane value and the child holds garbage,
// child_copy corrupted/failed to reproduce it. If both hold the same value,
// the chain is like that in the parent too and only the child ever walks it.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Dbg4 {
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

  static string Region(IntPtr p, long addr) {
    MBI m;
    if (VirtualQueryEx(p, (IntPtr)addr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero)
      return "VirtualQuery FAILED";
    string st = m.State == 0x1000 ? "COMMITTED" : m.State == 0x2000 ? "RESERVED (not committed)" : "FREE (unmapped)";
    return st + " allocBase=0x" + m.AllocationBase.ToInt64().ToString("X")
           + " size=0x" + m.RegionSize.ToInt64().ToString("X");
  }
  static bool R64(IntPtr p, long addr, out long val) {
    byte[] b = new byte[8]; IntPtr got; val = 0;
    if (!ReadProcessMemory(p, (IntPtr)addr, b, (IntPtr)8, out got) || got.ToInt64() != 8) return false;
    val = BitConverter.ToInt64(b, 0); return true;
  }

  public static string Run(string exe, string cwd) {
    var sb = new StringBuilder();
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, null, IntPtr.Zero, IntPtr.Zero, false, 0x00000001, IntPtr.Zero, cwd, ref si, out pi))
      return "CreateProcess failed err=" + Marshal.GetLastWin32Error();
    int rootPid = pi.dwProcessId;
    IntPtr hParent = pi.hProcess;
    var handles = new Dictionary<int,IntPtr>();
    handles[rootPid] = hParent;
    const long LOW = 0x800000000L, HIGH = 0xa00000000L;

    byte[] ev = new byte[256];
    IntPtr ctxBuf = Marshal.AllocHGlobal(4096);
    bool done = false;
    while (!done && WaitForDebugEvent(ev, 30000)) {
      int code = BitConverter.ToInt32(ev, 0);
      int pid = BitConverter.ToInt32(ev, 4), tid = BitConverter.ToInt32(ev, 8);
      uint cont = 0x00010002;
      if (code == 3) { IntPtr hp = (IntPtr)BitConverter.ToInt64(ev, 24);
                       if (!handles.ContainsKey(pid)) handles[pid] = hp; }
      else if (code == 1) {
        uint ec = BitConverter.ToUInt32(ev, 16);
        if (ec != 0x80000003 && ec != 0x406D1388 && pid != rootPid) {
          IntPtr hChild = handles.ContainsKey(pid) ? handles[pid] : IntPtr.Zero;
          IntPtr th = OpenThread(0x001F03FF, false, tid);
          for (int i = 0; i < 4096; i++) Marshal.WriteByte(ctxBuf, i, 0);
          Marshal.WriteInt32(ctxBuf, 0, unchecked((int)0x00400007));
          if (th != IntPtr.Zero && GetThreadContext(th, ctxBuf)) {
            long x20 = Marshal.ReadInt64(ctxBuf, 0x008 + 20*8);
            long cygheap;
            R64(hChild, x20 + 8, out cygheap);
            sb.AppendLine("cygheap = 0x" + cygheap.ToString("X") + "  (both processes use the fixed address)");
            sb.AppendLine("  parent: " + Region(hParent, cygheap));
            sb.AppendLine("  child : " + Region(hChild,  cygheap));
            sb.AppendLine();

            // walk the child's chain to find the slot holding the bad pointer
            long chain, rvc, prev = 0, badSlot = 0, badVal = 0;
            R64(hChild, cygheap + 8, out chain);
            rvc = chain; int n = 0;
            while (rvc != 0 && n < 200) {
              if (!R64(hChild, rvc + 8, out prev)) break;
              if (prev != 0 && (prev < LOW || prev >= HIGH)) { badSlot = rvc + 8; badVal = prev; break; }
              rvc = prev; n++;
            }
            if (badSlot == 0) { sb.AppendLine("no out-of-range prev found this run"); }
            else {
              sb.AppendLine("BAD prev FOUND at chain entry 0x" + (badSlot-8).ToString("X")
                            + "  (slot = entry+8 = 0x" + badSlot.ToString("X") + ")");
              sb.AppendLine("  child  value = 0x" + badVal.ToString("X16"));
              long pv;
              bool okp = R64(hParent, badSlot, out pv);
              sb.AppendLine("  PARENT value = " + (okp ? "0x" + pv.ToString("X16") : "UNREADABLE in parent"));
              sb.AppendLine();
              sb.AppendLine("  >>> DISCRIMINATOR <<<");
              if (okp && pv == badVal)
                sb.AppendLine("  IDENTICAL. child_copy reproduced the parent's bytes faithfully.");
              else if (okp)
                sb.AppendLine("  DIFFERENT. The child's copy does NOT match the parent -> copy defect.");
              sb.AppendLine();
              sb.AppendLine("  Is the bad target 0x" + badVal.ToString("X") + " mapped anywhere?");
              sb.AppendLine("   parent: " + Region(hParent, badVal));
              sb.AppendLine("   child : " + Region(hChild,  badVal));
              // dump raw bytes around the slot in both
              byte[] bp = new byte[32], bc = new byte[32]; IntPtr g;
              bool op = ReadProcessMemory(hParent, (IntPtr)(badSlot-8), bp, (IntPtr)32, out g);
              bool oc = ReadProcessMemory(hChild,  (IntPtr)(badSlot-8), bc, (IntPtr)32, out g);
              sb.AppendLine();
              sb.AppendLine("  32 bytes at entry 0x" + (badSlot-8).ToString("X") + ":");
              sb.AppendLine("   parent: " + (op ? BitConverter.ToString(bp) : "unreadable"));
              sb.AppendLine("   child : " + (oc ? BitConverter.ToString(bc) : "unreadable"));
            }
            CloseHandle(th);
          }
          done = true; cont = 0x80010001;
        }
      }
      else if (code == 5 && pid == rootPid) { ContinueDebugEvent(pid, tid, cont); break; }
      ContinueDebugEvent(pid, tid, cont);
    }
    Marshal.FreeHGlobal(ctxBuf);
    return sb.ToString();
  }
}
