#!/bin/bash

###########################################################################
# Copyright (C) 2022, 2023 IoT.bzh                                        #
#                                                                         #
# Authors:  Salma   Raiss   <salma.raiss@iot.bzh>                         #
#                                                                         #
# Licensed under the Apache License, Version 2.0 (the "License");         #
# you may not use this file except in compliance with the License.        #
# You may obtain a copy of the License at                                 #
#                                                                         #
#     http://www.apache.org/licenses/LICENSE-2.0                          #
#                                                                         #
# Unless required by applicable law or agreed to in writing, software     #
# distributed under the License is distributed on an "AS IS" BASIS,       #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.#
# See the License for the specific language governing permissions and     #
# limitations under the License.                                          #
###########################################################################
set -e

usage ()
{
cat << EOF
Usage: $script MENDER_ARTEFACT_FILE
Generate a pair of private/public keys to pre-authorize devices

  -o, --output: Full path to output keys files
EOF
}

while [ "$#" -ne "0" ]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -o|--output_d)
            shift
            output_dir="$1"
            ;;
     esac
     shift
done

PRIVATE_KEY="mender-agent.pem"
PUBLIC_KEY="public.key"

# verify openssl is present and sufficiently recent (genpkey seems to require openssl 1.0+)
command -v openssl >/dev/null 2>&1 || { echo >&2 "ERROR: Please install the openssl utility version 1.0.0 or newer to generate keys."; exit 1; }

OPENSSL_VERSION_REGEX_MAJOR_BACKREF="OpenSSL ([0-9]+).*"
OPENSSL_VERSION_STRING=$(openssl version)
OPENSSL_VERSION_MAJOR=$(echo "$OPENSSL_VERSION_STRING" | sed -En "s/$OPENSSL_VERSION_REGEX_MAJOR_BACKREF/\1/p")

if [ "$OPENSSL_VERSION_MAJOR" != "1" ]; then
  echo "ERROR: openssl is too old, need version 1.0.0 or newer"
  echo "ERROR: OPENSSL_VERSION_STRING=$OPENSSL_VERSION_STRING"
  exit 1
fi

CLIENT_KEYS_DIR="$output_dir"/keys-client-generated
echo $CLIENT_KEYS_DIR

mkdir -p "$CLIENT_KEYS_DIR"
cd "$CLIENT_KEYS_DIR"

openssl genpkey -algorithm RSA -out $PRIVATE_KEY -pkeyopt rsa_keygen_bits:3072

# convert to RSA private key format
openssl rsa -in $PRIVATE_KEY -out $PRIVATE_KEY

# extract public key (e.g. for preauthorization)
openssl rsa -in $PRIVATE_KEY -out $PUBLIC_KEY -pubout

echo "A Mender client keypair has been generated in $CLIENT_KEYS_DIR."
echo "You can use the public key ($PUBLIC_KEY) to preauthorize the device in the Mender server."
echo "And copy the private key ($PRIVATE_KEY) to the device at the path : /var/lib/mender"
exit 0