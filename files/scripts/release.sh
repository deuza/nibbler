#!/bin/sh
#
# Build the release archives of Nibbler in a reproducible way.
#
# Usage, from a clean clone of the repository, at the commit or tag to release:
#
#     sh files/scripts/release.sh
#
# What it does:
#
#   1. Reads the Nibbler version from files/src/package.json and the Electron
#      version from files/scripts/builder.py.
#   2. Downloads the official Electron archives for Windows and Linux (x64),
#      with Electron's own SHA256SUMS list, and checks them against it.
#   3. Runs builder.py, which assembles the Windows and Linux versions.
#   4. Normalises what could differ from one build to another (dates, file
#      permissions, file order, owners) and creates:
#          files/scripts/dist/nibbler-<version>-windows.zip
#          files/scripts/dist/nibbler-<version>-linux.tar.gz
#          files/scripts/dist/SHA256SUMS
#
# All dates are set to SOURCE_DATE_EPOCH, see
# https://reproducible-builds.org/specs/source-date-epoch/
# If it is not set, the date of the current commit is used, so two builds of
# the same commit give the same archives, byte for byte, as long as the same
# tools are used (GNU tar, gzip and Info-ZIP zip). With other versions of these
# tools the archives may differ, but their contents must stay identical: the
# reliable check is then to extract both and compare them with diff -r.
#
# Needs: git, curl, sha256sum, python3, zip, GNU tar, gzip and GNU coreutils
# (touch -d @SECONDS). Written for a POSIX shell; tested on Debian.

set -eu

die() {
	printf 'release.sh: %s\n' "$1" >&2
	exit 1
}

info() {
	printf '==> %s\n' "$1"
}

# Everything below must not depend on the environment of whoever runs the
# script: fixed locale for sorting, UTC for the dates stored in zip files, and
# a umask that does not leave files group-writable.
LC_ALL=C
TZ=UTC
export LC_ALL TZ
umask 022

for tool in git curl sha256sum python3 zip tar gzip find sort touch chmod awk sed; do
	command -v "$tool" >/dev/null 2>&1 || die "$tool is needed but was not found"
done

# Locate the repository from the place of this script, wherever it is run from.
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/../.." && pwd)
[ -f "$repo_dir/files/src/package.json" ] || die "cannot find files/src/package.json from $script_dir"
cd "$repo_dir"

# builder.py copies files/src and files/res as they are on disk: any file that
# is not exactly the committed one (modified, untracked or ignored) would end
# up in the archives without being part of the commit.
if [ -n "$(git status --porcelain --ignored -- files/src files/res)" ]; then
	git status --short --ignored -- files/src files/res >&2
	die "files/src or files/res differ from the commit (see above): build from a clean checkout"
fi

version=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' files/src/package.json)
electron_linux=$(sed -n 's/.*electron-v\([0-9][0-9.]*\)-linux-x64\.zip.*/\1/p' files/scripts/builder.py)
electron_windows=$(sed -n 's/.*electron-v\([0-9][0-9.]*\)-win32-x64\.zip.*/\1/p' files/scripts/builder.py)
[ -n "$electron_linux" ] || die "cannot read the Electron version from builder.py"
[ "$electron_linux" = "$electron_windows" ] || die "builder.py uses Electron $electron_windows for Windows but $electron_linux for Linux"
electron=$electron_linux

# The reference date of the build: the one given by the caller, or the date
# of the commit being built.
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
	SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
fi
case $SOURCE_DATE_EPOCH in
'' | *[!0-9]*) die "SOURCE_DATE_EPOCH must be a number of seconds, not '$SOURCE_DATE_EPOCH'" ;;
esac
export SOURCE_DATE_EPOCH

info "Nibbler $version, Electron $electron, commit $(git rev-parse HEAD)"
info "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH ($(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d %H:%M:%S UTC'))"

# Electron archives: downloaded once into electron_zipped (ignored by git),
# and checked against Electron's SHA256SUMS on every run.
zip_dir=$script_dir/electron_zipped
base_url=https://github.com/electron/electron/releases/download/v$electron
mkdir -p "$zip_dir"
cd "$zip_dir"

info "Fetching Electron's SHA256SUMS"
curl --proto '=https' --tlsv1.2 -fsSL -o SHASUMS256.txt "$base_url/SHASUMS256.txt" ||
	die "cannot download $base_url/SHASUMS256.txt"

for platform in win32-x64 linux-x64; do
	archive=electron-v$electron-$platform.zip
	if [ ! -f "$archive" ]; then
		info "Downloading $archive"
		curl --proto '=https' --tlsv1.2 -fL -o "$archive.part" "$base_url/$archive" ||
			die "cannot download $base_url/$archive"
		mv "$archive.part" "$archive"
	fi
	# The list writes "<hash> *<name>": keep the line of this archive only, in
	# the "<hash>  <name>" form that sha256sum -c expects.
	expected=$(awk -v name="$archive" '{ n = $2; sub(/^\*/, "", n); if (n == name) print $1 "  " n }' SHASUMS256.txt)
	[ -n "$expected" ] || die "$archive is not listed in Electron's SHA256SUMS"
	if ! printf '%s\n' "$expected" | sha256sum -c --quiet -; then
		rm -f "$archive"
		die "$archive does not match Electron's SHA256SUMS; it has been deleted, run the script again"
	fi
	info "$archive matches Electron's SHA256SUMS"
done

# Fresh build directory, then builder.py.
cd "$repo_dir"
dist_dir=$script_dir/dist
rm -rf "$dist_dir"
info "Running builder.py"
python3 "$script_dir/builder.py"

windows=nibbler-$version-windows
linux=nibbler-$version-linux
for build in "$windows" "$linux"; do
	[ -d "$dist_dir/$build" ] || die "builder.py did not create $build"
	# Same permissions whatever the umask of the clone: read for everyone,
	# write for the owner only, execute only where the file already had it.
	chmod -R u+rwX,go+rX,go-w "$dist_dir/$build"
	# Same date for every file and directory.
	find "$dist_dir/$build" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
done

cd "$dist_dir"

# Windows: zip, files only (-D, no directory entries), in sorted order, with no
# extra field (-X: no uid, gid or extended timestamps).
info "Creating $windows.zip"
find "$windows" ! -type d | sort | zip -q -X -D -9 "$windows.zip" -@

# Linux: tar keeps the executable permissions that a zip extracted by most
# tools would lose. Sorted names, numeric owner 0:0, fixed dates, and gzip -n
# so that gzip does not store its own name and date.
info "Creating $linux.tar.gz"
tar --sort=name --format=gnu --owner=0 --group=0 --numeric-owner \
	--mtime="@$SOURCE_DATE_EPOCH" -cf - "$linux" | gzip -9 -n >"$linux.tar.gz"

sha256sum "$windows.zip" "$linux.tar.gz" >SHA256SUMS

info "Done, in $dist_dir:"
cat SHA256SUMS
cat <<EOF

To sign the list of checksums:
    gpg --armor --detach-sign $dist_dir/SHA256SUMS
EOF
