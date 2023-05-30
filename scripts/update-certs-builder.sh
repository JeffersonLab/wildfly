#!/bin/bash

# All arguments are treated as certificates
CUSTOM_CRT_URL="$@"

if [ -z "${CUSTOM_CRT_URL}" ] ; then
  echo "No custom certs passed.  Nothing to update"
  exit 0
fi

for cert in $CUSTOM_CRT_URL
do
  echo Downloading $cert
  name=$(echo $cert | rev | cut -f1 -d"/" | rev | cut -f1 -d'.') || exit 1
  wget -O /usr/local/share/ca-certificates/custom-${name}.crt $cert || exit 1
done

update-ca-certificates || exit 1

for cert in $CUSTOM_CRT_URL
do
  echo Importing $cert
  name=$(echo $cert | rev | cut -f1 -d"/" | rev | cut -f1 -d'.') || exit 1
  keytool -import -alias custom_${name} -file /usr/local/share/ca-certificates/custom-${name}.crt -cacerts -storepass changeit -noprompt || exit 1
done
