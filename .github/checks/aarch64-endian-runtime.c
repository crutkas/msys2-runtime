typedef unsigned short __uint16_t;
typedef unsigned int __uint32_t;

#define _ANSIDECL_H_
#define _ELIDABLE_INLINE static __inline__ __attribute__ ((__always_inline__))
#define __MACHINE_ENDIAN_H__
#include "../../winsup/cygwin/include/machine/_endian.h"
#include "../../winsup/cygwin/include/bits/byteswap.h"

#if !defined(__aarch64__)
#error "Expected an AArch64 compiler target"
#endif

#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "Expected a little-endian AArch64 compiler target"
#endif

_Static_assert (sizeof (__uint16_t) == 2, "uint16 model must be 16-bit");
_Static_assert (sizeof (__uint32_t) == 4, "uint32 model must be 32-bit");
_Static_assert (sizeof (unsigned long long) == 8,
		"uint64 model must be 64-bit");

static __uint16_t
expected_16 (__uint16_t value)
{
  return (__uint16_t) ((value >> 8) | (value << 8));
}

static __uint32_t
expected_32 (__uint32_t value)
{
  return ((value & 0x000000ffu) << 24)
	 | ((value & 0x0000ff00u) << 8)
	 | ((value & 0x00ff0000u) >> 8)
	 | ((value & 0xff000000u) >> 24);
}

static unsigned long long
expected_64 (unsigned long long value)
{
  return ((unsigned long long) expected_32 ((__uint32_t) value) << 32)
	 | expected_32 ((__uint32_t) (value >> 32));
}

int
main (void)
{
  static const __uint16_t vectors_16[] =
    { 0x0000u, 0x0001u, 0x00ffu, 0x1234u, 0x8001u, 0xffffu };
  static const __uint32_t vectors_32[] =
    {
      0x00000000u, 0x00000001u, 0x000000ffu, 0x12345678u,
      0x80000001u, 0xffffffffu
    };
  static const unsigned long long vectors_64[] =
    {
      0x0000000000000000ull, 0x0000000000000001ull,
      0x0123456789abcdefull, 0x8000000000000001ull,
      0xffffffffffffffffull
    };
  unsigned int index;

  for (index = 0; index < sizeof (vectors_16) / sizeof (vectors_16[0]);
       ++index)
    if (__ntohs (vectors_16[index]) != expected_16 (vectors_16[index])
	|| __htons (vectors_16[index]) != expected_16 (vectors_16[index])
	|| __bswap_16 (vectors_16[index]) != expected_16 (vectors_16[index]))
      return 1;

  for (index = 0; index < sizeof (vectors_32) / sizeof (vectors_32[0]);
       ++index)
    if (__ntohl (vectors_32[index]) != expected_32 (vectors_32[index])
	|| __htonl (vectors_32[index]) != expected_32 (vectors_32[index])
	|| __bswap_32 (vectors_32[index]) != expected_32 (vectors_32[index]))
      return 2;

  for (index = 0; index < sizeof (vectors_64) / sizeof (vectors_64[0]);
       ++index)
    if (__bswap_64 (vectors_64[index]) != expected_64 (vectors_64[index]))
      return 3;

  {
    __uint16_t values[] = { 0x1234u, 0x5678u };
    unsigned int evaluation_count = 0;
    if (__htons (values[evaluation_count++]) != 0x3412u
	|| evaluation_count != 1)
      return 4;
  }

  {
    const unsigned char bytes[] = { 0xffu, 0x34u, 0x12u, 0xffu };
    __uint16_t value;
    __builtin_memcpy (&value, bytes + 1, sizeof (value));
    if (__ntohs (value) != 0x3412u)
      return 5;
  }

  if (__htons (-2) != expected_16 ((__uint16_t) -2)
      || __htonl (-2) != expected_32 ((__uint32_t) -2))
    return 6;

  return 0;
}
