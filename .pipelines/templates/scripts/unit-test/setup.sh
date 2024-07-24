#!/usr/bin/env bash

set -eoux pipefail

./scripts/pkgdep.sh
export MAKEFLAGS
MAKEFLAGS="-j$(nproc)"

apt-get install -y jq lcov

pip install lcov_cobertura

./configure --enable-debug --enable-coverage --disable-examples --disable-apps --without-isal
make
