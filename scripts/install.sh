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

NAME="f5-bigip-runtime-init"
VERSION="demo"
SVC_ACCOUNT="f5devcentral"

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

install_location="/tmp/${NAME}"
mkdir -p ${install_location}

# discover cloud environment from instance metadata availability
declare -A CLOUD_MAP=( [azure]='http://169.254.169.254/metadata/instance?api-version=2019-06-01 -H Metadata:true' \
[aws]='http://169.254.169.254/latest/meta-data/' \
[gcp]='http://metadata.google.internal/computeMetadata/v1/instance/ -H Metadata-Flavor:Google' )

# loop until we find a cloud or time out and give up
COUNTER=0
until [[ -n ${CLOUD} ]] || [[ ${COUNTER} -gt 12 ]]; do
    for KEY in "${!CLOUD_MAP[@]}"; do
        echo $KEY is ${CLOUD_MAP[$KEY]};
        VALUE=${CLOUD_MAP[$KEY]}
        RESPONSE=$(curl -s -o /dev/null -w '%{http_code}' ${VALUE} | grep 200)
        if [[ $RESPONSE == "200" ]]; then
            echo "FOUND CLOUD: ${KEY}"
            CLOUD=$KEY
            break
        fi
    done
    ((COUNTER++))
    sleep 5
done

# write environment to file for use by onboarder
if [[ -z ${CLOUD} ]]; then
    echo "Could not find a cloud, install all libraries."
    CLOUD="all"
fi 
echo ${CLOUD} > /config/cloud/environment

download_location="/tmp/${NAME}-${CLOUD}.tar.gz"

CLOUD_PACKAGE_NAME=${NAME}-${CLOUD}
curl --location https://github.com/${SVC_ACCOUNT}/${NAME}/releases/download/v${VERSION}/${CLOUD_PACKAGE_NAME}.tar.gz --output ${download_location}
curl --location https://github.com/${SVC_ACCOUNT}/${NAME}/releases/download/v${VERSION}/${CLOUD_PACKAGE_NAME}.tar.gz.sha256 --output ${download_location}.sha256

# verify package 
dir=$(pwd)
cd /tmp && cat ${download_location}.sha256 | sha256sum -c | grep OK
if [[ $? -ne 0 ]]; then
    echo "Couldn't verify the f5-bigip-runtime-init package, exiting."
    exit 1
fi
cd $dir

# unzip package
tar xfz ${download_location} --directory ${install_location}

# try to get the latest metadata
curl --location https://cdn.f5.com/product/cloudsolutions/f5-extension-metadata/latest/metadata.json --output toolchain_metadata_tmp.json
cat toolchain_metadata_tmp.json | jq empty > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    diff=$(jq -n --slurpfile latest toolchain_metadata_tmp.json --slurpfile current ${install_location}/src/lib/bigip/toolchain/toolchain_metadata.json '$latest != $current')
    if [[ $diff == "true" ]]; then
        cp toolchain_metadata_tmp.json ${install_location}/src/lib/bigip/toolchain/toolchain_metadata.json
        rm toolchain_metadata_tmp.json
    fi
else
    echo "Couldn't get the latest toolchain metadata, using local copy."
fi

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
