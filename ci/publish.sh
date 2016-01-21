#!/bin/bash
set -e
set -o pipefail
set -x

cd debian
deb-s3 upload --bucket $APT_S3_BUCKET --prefix utilities/debian -a amd64 --sign $APT_KEY_ID -p -c jessie *.deb
cd ../ubuntu
deb-s3 upload --bucket $APT_S3_BUCKET --prefix utilities/ubuntu -a amd64 --sign $APT_KEY_ID -p -c trusty *.deb
