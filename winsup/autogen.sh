#!/bin/sh
set -e
cd "$(dirname "$0")"

: "${ACLOCAL:=/usr/bin/aclocal}"
: "${AUTOCONF:=/usr/bin/autoconf}"
: "${AUTOHEADER:=/usr/bin/autoheader}"
: "${AUTOMAKE:=/usr/bin/automake}"
: "${RM:=/bin/rm}"

"$ACLOCAL" --force
"$AUTOCONF" -f
"$AUTOHEADER" -f
"$AUTOMAKE" -ac
find . -name Makefile.in -exec \
    sed -i 's|\\\$(DEPDIR)|/$(DEPDIR)|g' '{}' \;
"$RM" -rf autom4te.cache
