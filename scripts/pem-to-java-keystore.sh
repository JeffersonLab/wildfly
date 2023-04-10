#!/bin/bash

FUNCTIONS=(combine_with_intermediate
           convert_to_pkcs12
           convert_to_keystore)

VARIABLES=(KEYSTORE_OUTPUT_PATH
           KEYSTORE_PASS
           PEM_CERT_PATH
           PEM_INTERMEDIATE_CERT_PATH
           PEM_KEY_PATH)

if [[ $# -eq 0 ]] ; then
    echo "Usage: $0 [var file] <optional function>"
    echo "The var file arg should be the path to a file with bash variables that will be sourced."
    echo "The optional function name arg if provided is the sole function to call, else all functions are invoked sequentially."
    printf 'Variables: '
    printf '%s ' "${VARIABLES[@]}"
    printf '\n'
    printf 'Functions: '
    printf '%s ' "${FUNCTIONS[@]}"
    printf '\n'
    exit 0
fi

if [ ! -z "$1" ] && [ -f "$1" ]
then
echo "Loading environment $1"
. $1
fi

# Verify expected env set:
for i in "${!VARIABLES[@]}"; do
  var=${VARIABLES[$i]}
  [ -z "${!var}" ] && { echo "$var is not set. Exiting."; exit 1; }
done

combine_with_intermediate() {
cat ${PEM_CERT_PATH} ${PEM_INTERMEDIATE_CERT_PATH} > /tmp/combined.pem
}

convert_to_pkcs12() {
openssl pkcs12 -export -in /tmp/combined.pem -inkey ${PEM_KEY_PATH} -name combined -password pass:${KEYSTORE_PASS} > /tmp/combined.p12
}

convert_to_keystore() {
keytool -importkeystore -srckeystore /tmp/combined.p12 -destkeystore ${KEYSTORE_OUTPUT_PATH} -srcstoretype pkcs12 -alias combined -deststorepass ${KEYSTORE_PASS} -srcstorepass ${KEYSTORE_PASS}
}

if [ ! -z "$2" ]
then
  echo "------------------------"
  echo "$2"
  echo "------------------------"
  $2
else
for i in "${!FUNCTIONS[@]}"; do
  echo "------------------------"
  echo "${FUNCTIONS[$i]}"
  echo "------------------------"
  ${FUNCTIONS[$i]};
done
fi
