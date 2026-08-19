static __thread int tls_value = 17;

int
main (void)
{
  int value = tls_value;

  tls_value = value + 1;
  return tls_value != value + 1;
}
