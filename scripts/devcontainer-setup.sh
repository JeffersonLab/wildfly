#!/bin/bash

FUNCTIONS=(download
           unzip_and_chmod
           create_symbolic_links
           adjust_jvm_options)

VARIABLES=(WILDFLY_BIND_ADDRESS
           WILDFLY_HTTPS_PORT
           WILDFLY_USER
           WILDFLY_USER_HOME
           WILDFLY_VERSION
           JDK_HOME
           JDK_MAX_HEAP
           JDK_MIN_HEAP)

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

WILDFLY_APP_HOME=${WILDFLY_USER_HOME}/${WILDFLY_VERSION}

download() {
cd /tmp
curl -L -O https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.zip
}

unzip_and_chmod() {
unzip /tmp/wildfly-${WILDFLY_VERSION}.zip -d ${WILDFLY_USER_HOME}
mv ${WILDFLY_USER_HOME}/wildfly-${WILDFLY_VERSION} ${WILDFLY_APP_HOME}
chown -R ${WILDFLY_USER}:${WILDFLY_GROUP} ${WILDFLY_USER_HOME}
}

create_symbolic_links() {
cd ${WILDFLY_USER_HOME}
ln -s ${WILDFLY_VERSION} current
ln -s current/standalone/configuration configuration
ln -s current/standalone/log log
}

adjust_jvm_options() {
sed -i "s|#JAVA_HOME=\"/opt/java/jdk\"|JAVA_HOME=\"${JDK_HOME}\"|g" ${WILDFLY_APP_HOME}/bin/standalone.conf
sed -i "s/Xms64m/Xms${JDK_MIN_HEAP}/g" ${WILDFLY_APP_HOME}/bin/standalone.conf
sed -i "s/Xmx512m/Xmx${JDK_MAX_HEAP}/g" ${WILDFLY_APP_HOME}/bin/standalone.conf
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
