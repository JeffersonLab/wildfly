#!/bin/bash

FUNCTIONS=(add_modules
           enable_globals)

VARIABLES=(WILDFLY_APP_HOME)

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

WILDFLY_CLI_PATH=${WILDFLY_APP_HOME}/bin/jboss-cli.sh

set_global() {
${WILDFLY_CLI_PATH} -c "/subsystem=ee/:list-add(name=global-modules,value={\"name\"=>\"${MODULE_NAME}\",\"slot\"=>\"main\"})"
}

add_module() {

cd /tmp

LOCAL_RESOURCES=()
IFS=","
read -a resources <<<"${RESOURCES_CSV}"
for x in "${resources[@]}" ;do
    #echo "> [$x]"
    wget -nv ${x}
    LOCAL_RESOURCES+=(/tmp/`basename "${x}"`)
done

IFS=","
LOCAL_RESOURCES_CSV=`echo "${LOCAL_RESOURCES[*]}"`

${WILDFLY_CLI_PATH} -c <<EOF
module add --name=${DEP_NAME} --resource-delimiter=, --resources=${LOCAL_RESOURCES_CSV} --dependencies=${DEPENDENCIES_CSV}
EOF
}

add_modules() {
  if [[ -z "${ADD_JBOSS_MODULES}" ]]; then
    echo "Skipping add_globals because ADD_JBOSS_MODULES undefined"
    return 0
  fi

IFS=$'\n'
for LINE in $(echo "${ADD_JBOSS_MODULES}")
do
  echo "${LINE}"
  IFS="|"
  read -a fields <<<"${LINE}"
  SCOPE=${fields[0]}
  DEP_NAME=${fields[1]}
  RESOURCES_CSV=${fields[2]}
  DEPENDENCIES_CSV=${fields[3]}

  echo "SCOPE: ${SCOPE}"
  echo "DEP_NAME: ${DEP_NAME}"
  echo "RESOURCES_CSV: ${RESOURCES_CSV}"
  echo "DEPENDENCIES_CSV: ${DEPENDENCIES_CSV}"

  add_module

  if [[ "global" = "${SCOPE}" ]]; then
    MODULE_NAME="${DEP_NAME}"
    set_global
  fi
done
unset IFS
}

# It's possible that Wildfly already includes a lib you want and you simply need to enable it.
# This is rare however, because Wildfly is pretty aggressive of implicitly enabling libs it has
# and actually you may find you need to manually exclude libs that conflict with app libs.
# You can always use jboss-deployment-structure.xml or a Manifest to add instead of making global.
# See: https://docs.wildfly.org/26/Developer_Guide.html
enable_globals() {
  if [[ -z "${GLOBAL_ENABLE_LIBS}" ]]; then
    echo "Skipping enable_globals because GLOBAL_ENABLE_LIBS undefined"
    return 0
  fi

IFS=$'\n'
for LINE in $(echo "${GLOBAL_ENABLE_LIBS}")
do
  echo "${LINE}"
  MODULE_NAME=${LINE}
  set_global
done
unset IFS
}

if [ ! -z "$2" ]
then
  echo "------------------------"
  echo "$2"
  echo "------------------------"
  $2
else
for i in "${!FUNCTIONS[@]}"; do
  echo ""
  echo "------------------------"
  echo "${FUNCTIONS[$i]}"
  echo "------------------------"
  ${FUNCTIONS[$i]};
done
fi

