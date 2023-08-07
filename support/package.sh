#!/usr/bin/env bash

set -eux

upstream_version=$(head -1 debian/changelog | awk '{ print $2 }' | sed -e 's/[()]//g' | awk -F- '{ print $1 }')
TMPDIR=$(mktemp -d)

cleanup () {
  rm -rf "${TMPDIR}"
}

trap cleanup ERR
trap cleanup EXIT

mkdir "${TMPDIR}/puppet-code_${upstream_version}"
cp -R environments modules LICENSE README.md "${TMPDIR}/puppet-code_${upstream_version}"

tar zcf "../puppet-code_${upstream_version}.orig.tar.gz" -C "${TMPDIR}" "puppet-code_${upstream_version}"
debuild --build=all -us -uc
