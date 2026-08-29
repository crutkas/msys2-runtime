#define WIN32_LEAN_AND_MEAN
#include <windows.h>

class fcwd_access_t;
fcwd_access_t **find_fast_cwd_pointer_aarch64 ();

#ifndef LAYER4_EXPECTED_PROCESS_MACHINE
#error LAYER4_EXPECTED_PROCESS_MACHINE must describe this executable
#endif

extern "C" int
mainCRTStartup ()
{
  USHORT process_machine = 0;
  USHORT native_machine = 0;
  PROCESS_MACHINE_INFORMATION machine = {};
  MEMORY_BASIC_INFORMATION memory = {};
  fcwd_access_t **fast_cwd;

  if (!IsWow64Process2 (GetCurrentProcess (), &process_machine,
			&native_machine))
    ExitProcess (51);
  if (native_machine != IMAGE_FILE_MACHINE_ARM64)
    ExitProcess (52);
  if (!GetProcessInformation (GetCurrentProcess (), ProcessMachineTypeInfo,
			      &machine, sizeof machine)
      || machine.ProcessMachine != LAYER4_EXPECTED_PROCESS_MACHINE)
    ExitProcess (53);
  if (process_machine != IMAGE_FILE_MACHINE_UNKNOWN
      && process_machine != LAYER4_EXPECTED_PROCESS_MACHINE)
    ExitProcess (55);

  fast_cwd = find_fast_cwd_pointer_aarch64 ();
  if (!fast_cwd
      || VirtualQuery (fast_cwd, &memory, sizeof memory) != sizeof memory
      || memory.State != MEM_COMMIT
      || (memory.Protect & (PAGE_NOACCESS | PAGE_GUARD)) != 0)
    ExitProcess (56);

  ExitProcess (0);
}
