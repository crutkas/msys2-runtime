#include <ctype.h>
#include <iostream>
#include <locale>
#include <sstream>
#include <string>
#include <type_traits>

static_assert (std::is_same<decltype (_ctype_), const char[]>::value,
	       "The ctype ABI must remain an imported const char array");

int
main ()
{
  const std::ctype<char>& facet =
    std::use_facet<std::ctype<char> > (std::locale::classic ());
  const std::ctype<char>::mask *table = std::ctype<char>::classic_table ();
  if (static_cast<const void *> (table) != static_cast<const void *> (_ctype_ + 1))
    return 1;
  for (unsigned c = 0; c < 256; ++c)
    if (facet.is (std::ctype_base::alpha, static_cast<char> (c))
	!= !!((unsigned char) _ctype_[c + 1] & (_U | _L)))
      return 2;
  if (facet.toupper ('a') != 'A' || facet.tolower ('Z') != 'z'
      || !facet.is (std::ctype_base::space, '\t')
      || !facet.is (std::ctype_base::digit, '9'))
    return 3;
  std::istringstream input (" \t42 3.5 true sample");
  input.imbue (std::locale::classic ());
  int integer = 0;
  double number = 0;
  bool boolean = false;
  std::string word;
  input >> integer >> number >> std::boolalpha >> boolean >> word;
  if (!input || integer != 42 || number != 3.5 || !boolean || word != "sample")
    return 4;
  std::ostringstream output;
  output.imbue (std::locale::classic ());
  output << integer << ' ' << number << ' ' << std::boolalpha << boolean
	 << ' ' << word;
  if (output.str () != "42 3.5 true sample")
    return 5;
  std::cout << "hosted ctype and iostream passed\n";
  return !std::cout;
}
