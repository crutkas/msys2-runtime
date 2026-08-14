#include <assert.h>
#include <stdint.h>

#include <vector>

enum cache_type
{
  cache_unified,
  cache_instruction,
  cache_data
};

enum cache_query
{
  l1i_size,
  l1i_assoc,
  l1i_line,
  l1d_size,
  l1d_assoc,
  l1d_line,
  l2_size,
  l2_assoc,
  l2_line,
  l3_size,
  l3_assoc,
  l3_line
};

struct group_info
{
  unsigned configured;
  unsigned online;
};

struct affinity
{
  unsigned group;
  uint64_t mask;
};

struct cache_info
{
  unsigned level;
  cache_type type;
  unsigned associativity;
  unsigned line_size;
  unsigned size;
  std::vector<affinity> affinities;
};

static unsigned
processor_count (const std::vector<group_info> &groups, bool configured)
{
  unsigned count = 0;

  for (const group_info &group : groups)
    count += configured ? group.configured : group.online;
  return count;
}

static bool
cache_matches (cache_query query, const cache_info &cache)
{
  switch (query)
    {
    case l1i_size:
    case l1i_assoc:
    case l1i_line:
      return cache.level == 1
	     && (cache.type == cache_instruction
		 || cache.type == cache_unified);
    case l1d_size:
    case l1d_assoc:
    case l1d_line:
      return cache.level == 1
	     && (cache.type == cache_data || cache.type == cache_unified);
    case l2_size:
    case l2_assoc:
    case l2_line:
      return cache.level == 2;
    case l3_size:
    case l3_assoc:
    case l3_line:
      return cache.level == 3;
    }
  return false;
}

static bool
processor_uses_cache (const cache_info &cache, unsigned group,
		      unsigned processor)
{
  for (const affinity &affinity : cache.affinities)
    if (affinity.group == group && processor < 64
	&& (affinity.mask & (UINT64_C (1) << processor)) != 0)
      return true;
  return false;
}

static bool
size_query (cache_query query)
{
  return query == l1i_size || query == l1d_size || query == l2_size
	 || query == l3_size;
}

static unsigned
cache_property (cache_query query, const cache_info &cache)
{
  switch (query)
    {
    case l1i_size:
    case l1d_size:
    case l2_size:
    case l3_size:
      return cache.size;
    case l1i_assoc:
    case l1d_assoc:
    case l2_assoc:
    case l3_assoc:
      return cache.associativity == 0xff ? 0x8000 : cache.associativity;
    case l1i_line:
    case l1d_line:
    case l2_line:
    case l3_line:
      return cache.line_size;
    }
  return 0;
}

static unsigned
query_cache (const std::vector<cache_info> &caches, cache_query query,
	     unsigned group, unsigned processor)
{
  unsigned value = 0;
  bool found = false;
  bool inconsistent = false;

  for (const cache_info &cache : caches)
    if (cache_matches (query, cache)
	&& processor_uses_cache (cache, group, processor))
      {
	unsigned property = cache_property (query, cache);

	if (property == 0)
	  inconsistent = true;
	else if (size_query (query))
	  {
	    value += property;
	    found = true;
	  }
	else if (!found)
	  {
	    value = property;
	    found = true;
	  }
	else if (value != property)
	  inconsistent = true;
      }
  return found && !inconsistent ? value : 0;
}

int
main ()
{
  const std::vector<group_info> groups = {
    { 64, 64 },
    { 64, 48 },
    { 32, 17 },
  };
  assert (processor_count (groups, true) == 160);
  assert (processor_count (groups, false) == 129);

  const std::vector<cache_info> caches = {
    { 1, cache_instruction, 4, 64, 64 * 1024, {{ 0, UINT64_MAX }} },
    { 1, cache_data, 4, 64, 64 * 1024, {{ 0, UINT64_MAX }} },
    { 2, cache_unified, 8, 64, 512 * 1024, {{ 0, UINT64_MAX }} },
    { 1, cache_instruction, 4, 64, 64 * 1024, {{ 1, UINT64_MAX }} },
    { 1, cache_data, 8, 128, 128 * 1024, {{ 1, UINT64_MAX }} },
    { 2, cache_unified, 0xff, 128, 1024 * 1024,
      {{ 1, UINT64_MAX }} },
    { 3, cache_unified, 16, 128, 16 * 1024 * 1024,
      {{ 0, UINT64_MAX }, { 1, UINT64_MAX }} },
  };

  assert (query_cache (caches, l1i_size, 0, 3) == 64 * 1024);
  assert (query_cache (caches, l1d_line, 0, 3) == 64);
  assert (query_cache (caches, l1d_size, 1, 2) == 128 * 1024);
  assert (query_cache (caches, l1d_line, 1, 2) == 128);
  assert (query_cache (caches, l2_assoc, 1, 2) == 0x8000);
  assert (query_cache (caches, l3_size, 0, 63) == 16 * 1024 * 1024);
  assert (query_cache (caches, l3_size, 1, 63) == 16 * 1024 * 1024);
  assert (query_cache (caches, l3_size, 2, 0) == 0);

  std::vector<cache_info> split = {
    { 2, cache_instruction, 4, 64, 256 * 1024, {{ 0, 1 }} },
    { 2, cache_data, 8, 64, 256 * 1024, {{ 0, 1 }} },
  };
  assert (query_cache (split, l2_size, 0, 0) == 512 * 1024);
  assert (query_cache (split, l2_assoc, 0, 0) == 0);
}
