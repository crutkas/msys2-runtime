#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysinfo.h>
#include <unistd.h>
#include <windows.h>

static int
is_power_of_two (long value)
{
  return value > 0 && (value & (value - 1)) == 0;
}

static void
windows_processor_counts (long *configured, long *online)
{
  DWORD size = 0;
  PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX info;

  *configured = 0;
  *online = 0;
  assert (!GetLogicalProcessorInformationEx (RelationGroup, NULL, &size));
  assert (GetLastError () == ERROR_INSUFFICIENT_BUFFER);
  assert (size > 0);

  info = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) malloc (size);
  assert (info);
  assert (GetLogicalProcessorInformationEx (RelationGroup, info, &size));

  for (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX current = info;
       (BYTE *) current < (BYTE *) info + size;
       current = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)
		 ((BYTE *) current + current->Size))
    if (current->Relationship == RelationGroup)
      for (WORD i = 0; i < current->Group.ActiveGroupCount; ++i)
	{
	  *configured += current->Group.GroupInfo[i].MaximumProcessorCount;
	  *online += current->Group.GroupInfo[i].ActiveProcessorCount;
	}

  free (info);
}

#ifdef __aarch64__
static void
check_arm64_cpuinfo (long online)
{
  FILE *cpuinfo = fopen ("/proc/cpuinfo", "r");
  char line[1024];
  long processors = 0;
  long feature_lines = 0;

  assert (cpuinfo);
  while (fgets (line, sizeof line, cpuinfo))
    {
      if (strncmp (line, "processor\t:", 11) == 0)
	++processors;
      else if (strncmp (line, "Features\t: fp asimd", 20) == 0)
	++feature_lines;
    }
  assert (!ferror (cpuinfo));
  assert (fclose (cpuinfo) == 0);
  assert (processors == online);
  assert (feature_lines == online);
}
#endif

int
main (void)
{
  static const int sizes[] = {
    _SC_LEVEL1_ICACHE_SIZE,
    _SC_LEVEL1_DCACHE_SIZE,
    _SC_LEVEL2_CACHE_SIZE,
    _SC_LEVEL3_CACHE_SIZE,
    _SC_LEVEL4_CACHE_SIZE,
  };
  static const int lines[] = {
    _SC_LEVEL1_ICACHE_LINESIZE,
    _SC_LEVEL1_DCACHE_LINESIZE,
    _SC_LEVEL2_CACHE_LINESIZE,
    _SC_LEVEL3_CACHE_LINESIZE,
    _SC_LEVEL4_CACHE_LINESIZE,
  };
  SYSTEM_INFO system_info;
  long expected_configured;
  long expected_online;
  long configured;
  long online;
  long page_size;

  windows_processor_counts (&expected_configured, &expected_online);
  configured = sysconf (_SC_NPROCESSORS_CONF);
  online = sysconf (_SC_NPROCESSORS_ONLN);
  assert (configured == expected_configured);
  assert (online == expected_online);
  assert (get_nprocs_conf () == configured);
  assert (get_nprocs () == online);
  assert (configured >= online);
  assert (online > 0);

  GetSystemInfo (&system_info);
  page_size = sysconf (_SC_PAGESIZE);
  assert (page_size == system_info.dwAllocationGranularity);
  assert (is_power_of_two (page_size));

  for (size_t i = 0; i < sizeof sizes / sizeof sizes[0]; ++i)
    {
      long size = sysconf (sizes[i]);
      long line = sysconf (lines[i]);

      assert (size >= 0);
      assert (line >= 0);
      if (size != 0 && line != 0)
	{
	  assert (is_power_of_two (line));
	  assert (size >= line);
	  assert (size % line == 0);
	}
    }

#ifdef __aarch64__
  check_arm64_cpuinfo (online);
#endif
  return 0;
}
