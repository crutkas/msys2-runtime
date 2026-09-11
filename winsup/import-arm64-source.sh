#!/bin/bash
set -euo pipefail
export LC_ALL=C
if [[ $# != 2 ]]; then
    echo "usage: $0 EXPORT_DIRECTORY NEW_SOURCE_DIRECTORY" >&2
    exit 2
fi
export_dir=$(realpath "$1")
source_dir=$(realpath -m "$2")
if [[ -e $source_dir ]]; then
    echo "Refusing to overwrite source directory: $source_dir" >&2
    exit 1
fi
cd "$export_dir"
sha256sum --check SHA256SUMS
mkdir -p "$source_dir"
tar -xf base.tar -C "$source_dir"
cd "$source_dir"
if [[ -s $export_dir/tracked.patch ]]; then
    git apply --check "$export_dir/tracked.patch"
    git apply "$export_dir/tracked.patch"
fi
if [[ -f $export_dir/untracked.tar ]]; then
    tar -xf "$export_dir/untracked.tar"
fi
find . -type f -printf '%P\n' | sort > "$source_dir.files"
sort "$export_dir/source-files.txt" > "$source_dir.expected-files"
cmp "$source_dir.files" "$source_dir.expected-files"
while IFS= read -r file; do
    sha256sum "$file"
done < "$source_dir.files" > "$source_dir.SHA256SUMS"
cp "$export_dir/source-version.env" "$source_dir.env"
printf 'Imported and hashed %s source files into %s\n' "$(wc -l < "$source_dir.files")" "$source_dir"
