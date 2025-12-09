#!/bin/sh
# Build script for livereduce RPM
# Based on the pattern from neutrons/finddata
# https://github.com/neutrons/finddata/blob/main/rpmbuild.sh

SPECFILE="$(dirname "$(realpath "$0")")/livereduce.spec"

# Get the version from the pyproject.toml file
VERSION=$(grep ^version pyproject.toml | cut -d "=" -f 2 | sed 's/"//g' | tr -d ' ')
echo "version in pyproject.toml is ${VERSION}"

# Create the source tarball
if command -v pixi >/dev/null 2>&1; then
    # This runs outside of docker where pixi exists
    echo "building sdist..."
    pixi run build || exit 1
else
    # Must be inside of docker
    echo "assuming sdist already exists"
fi

# Setup rpm directories for building
TARBALL_SRC="livereduce-${VERSION}.tar.gz"
if [ ! -f dist/"${TARBALL_SRC}" ]; then
    echo "Failed to find source tarball: dist/${TARBALL_SRC}"
    exit 1
fi
mkdir -p "${HOME}"/rpmbuild/SOURCES
cp dist/"${TARBALL_SRC}" "${HOME}"/rpmbuild/SOURCES/"${TARBALL_SRC}" || exit 1

# Build the rpm
echo "building the rpm"
rpmbuild -ba "${SPECFILE}" --define "version ${VERSION}" || exit 1

# Give people a hint on how to verify the rpm
# shellcheck disable=SC1083
DIST=$(rpm --eval %{?dist})
echo "========================================"
echo "Successfully built rpm. To manually inspect package run"
echo "rpm -qilRp ~/rpmbuild/RPMS/noarch/python-livereduce-${VERSION}-1${DIST}.noarch.rpm"
echo "rpm -qilRp ~/rpmbuild/RPMS/noarch/python-livereduce-watchdog-${VERSION}-1${DIST}.noarch.rpm"
