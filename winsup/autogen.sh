#!/bin/sh
set -e
cd "$(dirname "$0")"

: "${ACLOCAL:=/usr/bin/aclocal}"
: "${AUTOCONF:=/usr/bin/autoconf}"
: "${AUTOMAKE:=/usr/bin/automake}"
: "${RM:=/bin/rm}"

"$ACLOCAL" --force
"$AUTOCONF" -f
"$AUTOMAKE" -ac
"$RM" -rf autom4te.cache
