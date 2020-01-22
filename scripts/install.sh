# Copyright 2020 F5 Networks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# USAGE: curl https://raw.githubusercontent.com/<org>/<repo>/v0.9.0/scripts/install.sh | bash

# catch 22, we do not have package.json prior to install from remote so we cannot do below
# TODO: figure out alternate mechanism to avoid version drift
#
# MAINDIR="$(dirname $0)/.."
# NAME=$(cat ${MAINDIR}/package.json | jq .name -r)
# VERSION=$(cat ${MAINDIR}/package.json | jq .version -r)

NAME="f5-cloud-onboarder"
VERSION="0.9.0"
SVC_ACCOUNT="jsevedge"

# usage: logger "log message"
logger() {
    echo "${1}"
}

# usage: platform_check 
# returns: LINUX|BIGIP
platform_check() {
    platform="LINUX"
    if [ -f "/VERSION" ]; then
        platform="BIGIP"
    fi
    echo ${platform}
}

logger "Package name: ${NAME}"
logger "Package version: ${VERSION}"

download_location="/tmp/${NAME}.tar.gz"
install_location="/tmp/${NAME}"
mkdir -p ${install_location}

# TODO: determine environment we are in

# download package (TODO: based on environment)
# - f5-cloud-onboarder-azure
# - f5-cloud-onboarder-aws
# - f5-cloud-onboarder-gcp
curl --location https://github.com/${SVC_ACCOUNT}/${NAME}/releases/download/v${VERSION}/${NAME}.tar.gz --output ${download_location}

# unzip package
tar xfz ${download_location} --directory ${install_location}

# create command line utility
utility_location="/usr/local/bin/${NAME}"
if [[ "$(platform_check)" == "LINUX" ]]; then
    echo "node ${install_location}/src/cli.js \"\$@\"" > ${utility_location}
    chmod 744 ${utility_location}
else
    mount -o remount,rw /usr
    echo "f5-rest-node ${install_location}/src/cli.js \"\$@\"" > ${utility_location}
    chmod 744 ${utility_location}
    mount -o remount,ro /usr
fi