#!/usr/bin/env bash

set -eux

CODENAME="jammy"
GPG_KEY_DIR=/etc/apt/cloud-init.gpg.d
GPG_KEY_PUB="${GPG_KEY_DIR}/infrahouse.gpg"
GPG_KEY_URL="https://release-${CODENAME}.infrahouse.com/DEB-GPG-KEY-release-${CODENAME}.infrahouse.com"

mkdir -p $GPG_KEY_DIR
curl -s $GPG_KEY_URL | gpg --dearmor > ${GPG_KEY_PUB}

echo "deb [signed-by=${GPG_KEY_PUB}] https://release-${CODENAME}.infrahouse.com/ ${CODENAME} main" \
  > /etc/apt/sources.list.d/infrahouse.list

apt-get update
make bootstrap
apt-get -y install infrahouse-toolkit reprepro gpg s3fs
