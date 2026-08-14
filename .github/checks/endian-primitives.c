#include <asm/byteorder.h>
#include <byteswap.h>
#include <sys/endian.h>

#if __BYTE_ORDER != __LITTLE_ENDIAN
#error "Cygwin targets must use little-endian byte order"
#endif

#if _BYTE_ORDER != _LITTLE_ENDIAN || BYTE_ORDER != LITTLE_ENDIAN
#error "Public byte-order macros must agree"
#endif

#define TYPE_IS(expression, type) \
  _Generic ((expression), type: 1, default: 0)

_Static_assert (__constant_ntohs (0x1234u) == 0x3412u,
		"constant ntohs must swap bytes");
_Static_assert (__constant_ntohl (0x12345678u) == 0x78563412u,
		"constant ntohl must swap bytes");
_Static_assert (ntohs (0x1234u) == 0x3412u,
		"ntohs constants must remain integer constant expressions");
_Static_assert (ntohl (0x12345678u) == 0x78563412u,
		"ntohl constants must remain integer constant expressions");
_Static_assert (TYPE_IS (ntohs (0), int),
		"optimized ntohs macros preserve integer promotion");
_Static_assert (TYPE_IS (htons (0), int),
		"optimized htons macros preserve integer promotion");
_Static_assert (TYPE_IS (ntohl (0), uint32_t),
		"ntohl must return uint32_t");
_Static_assert (TYPE_IS (htonl (0), uint32_t),
		"htonl must return uint32_t");
_Static_assert (TYPE_IS (bswap_16 (0), unsigned short),
		"bswap_16 must return unsigned short");
_Static_assert (TYPE_IS (bswap_32 (0), unsigned int),
		"bswap_32 must return unsigned int");
_Static_assert (TYPE_IS (bswap_64 (0), unsigned long long),
		"bswap_64 must return unsigned long long");

#define CHECKED __attribute__ ((__noinline__, __used__))

CHECKED uint16_t
checked_ntohs (uint16_t value)
{
  return ntohs (value);
}

CHECKED uint32_t
checked_ntohl (uint32_t value)
{
  return ntohl (value);
}

CHECKED uint16_t
checked_htons (uint16_t value)
{
  return htons (value);
}

CHECKED uint32_t
checked_htonl (uint32_t value)
{
  return htonl (value);
}

CHECKED unsigned short
checked_bswap_16 (unsigned short value)
{
  return bswap_16 (value);
}

CHECKED unsigned int
checked_bswap_32 (unsigned int value)
{
  return bswap_32 (value);
}

CHECKED unsigned long long
checked_bswap_64 (unsigned long long value)
{
  return bswap_64 (value);
}

CHECKED uint16_t
checked_constant_ntohs (void)
{
  return ntohs (0x1234u);
}

CHECKED uint32_t
checked_constant_ntohl (void)
{
  return ntohl (0x12345678u);
}

CHECKED uint16_t
checked_unaligned_ntohs (const unsigned char *bytes)
{
  uint16_t value;
  __builtin_memcpy (&value, bytes, sizeof (value));
  return ntohs (value);
}

static uint16_t
expected_16 (uint16_t value)
{
  return (uint16_t) ((value >> 8) | (value << 8));
}

static uint32_t
expected_32 (uint32_t value)
{
  return ((value & 0x000000ffu) << 24)
	 | ((value & 0x0000ff00u) << 8)
	 | ((value & 0x00ff0000u) >> 8)
	 | ((value & 0xff000000u) >> 24);
}

static uint64_t
expected_64 (uint64_t value)
{
  return ((uint64_t) expected_32 ((uint32_t) value) << 32)
	 | expected_32 ((uint32_t) (value >> 32));
}

int
main (void)
{
  static const uint16_t vectors_16[] =
    { 0x0000u, 0x0001u, 0x00ffu, 0x1234u, 0x8001u, 0xffffu };
  static const uint32_t vectors_32[] =
    {
      0x00000000u, 0x00000001u, 0x000000ffu, 0x12345678u,
      0x80000001u, 0xffffffffu
    };
  static const uint64_t vectors_64[] =
    {
      0x0000000000000000ull, 0x0000000000000001ull,
      0x0123456789abcdefull, 0x8000000000000001ull,
      0xffffffffffffffffull
    };
  unsigned int index;

  for (index = 0; index < sizeof (vectors_16) / sizeof (vectors_16[0]);
       ++index)
    {
      uint16_t value = vectors_16[index];
      uint16_t expected = expected_16 (value);
      if (checked_ntohs (value) != expected
	  || checked_htons (value) != expected
	  || checked_bswap_16 (value) != expected
	  || htobe16 (value) != expected
	  || be16toh (value) != expected
	  || htole16 (value) != value
	  || le16toh (value) != value)
	return 1;
    }

  for (index = 0; index < sizeof (vectors_32) / sizeof (vectors_32[0]);
       ++index)
    {
      uint32_t value = vectors_32[index];
      uint32_t expected = expected_32 (value);
      if (checked_ntohl (value) != expected
	  || checked_htonl (value) != expected
	  || checked_bswap_32 (value) != expected
	  || htobe32 (value) != expected
	  || be32toh (value) != expected
	  || htole32 (value) != value
	  || le32toh (value) != value)
	return 2;
    }

  for (index = 0; index < sizeof (vectors_64) / sizeof (vectors_64[0]);
       ++index)
    {
      uint64_t value = vectors_64[index];
      uint64_t expected = expected_64 (value);
      if (checked_bswap_64 (value) != expected
	  || htobe64 (value) != expected
	  || be64toh (value) != expected
	  || htole64 (value) != value
	  || le64toh (value) != value)
	return 3;
    }

  {
    uint16_t values[] = { 0x1234u, 0x5678u };
    unsigned int evaluation_count = 0;
    if (ntohs (values[evaluation_count++]) != 0x3412u
	|| evaluation_count != 1)
      return 4;
  }

  {
    uint32_t values[] = { 0x12345678u, 0x90abcdefu };
    unsigned int evaluation_count = 0;
    if (htonl (values[evaluation_count++]) != 0x78563412u
	|| evaluation_count != 1)
      return 5;
  }

  {
    const unsigned char bytes[] = { 0xffu, 0x34u, 0x12u, 0xffu };
    if (checked_unaligned_ntohs (bytes + 1) != 0x3412u
	|| be16dec (bytes + 1) != 0x3412u
	|| le16dec (bytes + 1) != 0x1234u)
      return 6;
  }

  if (htons (-2) != expected_16 ((uint16_t) -2)
      || htonl (-2) != expected_32 ((uint32_t) -2))
    return 7;

  return 0;
}
