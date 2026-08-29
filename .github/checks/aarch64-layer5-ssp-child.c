#include <stdio.h>
#include <stdint.h>
#include <windows.h>

static DWORD WINAPI
worker (void *arg)
{
  volatile DWORD value = (DWORD) (uintptr_t) arg;

  value += 5;
  OutputDebugStringA ("ssp off");
  return value;
}

int
main (void)
{
  char pid_path[MAX_PATH];
  FILE *pid_file;
  HANDLE thread;
  DWORD result;
  USHORT process_machine;
  USHORT native_machine;

  if (!IsWow64Process2 (GetCurrentProcess (), &process_machine, &native_machine)
      || process_machine != IMAGE_FILE_MACHINE_UNKNOWN
      || native_machine != IMAGE_FILE_MACHINE_ARM64)
    {
      fputs ("SSP child is not a native ARM64 process\n", stderr);
      return 1;
    }

  if (GetEnvironmentVariableA ("LAYER5_SSP_CHILD_PID_FILE", pid_path,
			       sizeof (pid_path)))
    {
      pid_file = fopen (pid_path, "w");
      if (!pid_file)
	{
	  fputs ("Unable to create SSP child PID file\n", stderr);
	  return 1;
	}
      fprintf (pid_file, "%u\n", (unsigned int) GetCurrentProcessId ());
      fclose (pid_file);
    }

  OutputDebugStringA ("ssp on");
  thread = CreateThread (NULL, 0, worker, (void *) (uintptr_t) 37, 0, NULL);
  if (!thread)
    {
      fprintf (stderr, "CreateThread failed: %u\n",
	       (unsigned int) GetLastError ());
      return 1;
    }
  if (WaitForSingleObject (thread, 10000) != WAIT_OBJECT_0
      || !GetExitCodeThread (thread, &result))
    {
      fputs ("SSP child thread did not complete\n", stderr);
      CloseHandle (thread);
      return 1;
    }
  CloseHandle (thread);
  if (result != 42)
    {
      fprintf (stderr, "SSP child returned %u\n", (unsigned int) result);
      return 1;
    }

  puts ("SSP_CHILD_OK");
  return 0;
}
