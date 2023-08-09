#!/bin/bash

FUNCTIONS=(wildfly_start_and_wait
           config_keycloak_client
           config_oracle_client
           wildfly_reload
           wildfly_stop)

VARIABLES=(KEYCLOAK_REALM
           KEYCLOAK_RESOURCE
           KEYCLOAK_SECRET
           KEYCLOAK_SERVER_URL
           KEYCLOAK_WAR
           WILDFLY_APP_HOME)

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

# Optional params
# - ORACLE_DATASOURCE
# - ORACLE_PASS
# - ORACLE_SERVER
# - ORACLE_SERVICE
# - ORACLE_USER
# - WILDFLY_SKIP_START
# - WILDFLY_SKIP_STOP

WILDFLY_CLI_PATH=${WILDFLY_APP_HOME}/bin/jboss-cli.sh

wildfly_start_and_wait() {
if [[ ! -z "${WILDFLY_SKIP_START}" ]]; then
  echo "Skipping Wildfly start because WILDFLY_SKIP_START defined"
  return 0
fi

${WILDFLY_APP_HOME}/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0 &

until curl http://localhost:8080 -sf -o /dev/null;
do
  echo $(date) " Still waiting for Wildfly to start..."
  sleep 5
done

echo $(date) " Wildfly started!"
}

config_keycloak_client() {
DEPLOYMENT_CONFIG=principal-attribute="preferred_username",ssl-required=EXTERNAL,resource="${KEYCLOAK_RESOURCE}",realm="${KEYCLOAK_REALM}",auth-server-url=${KEYCLOAK_SERVER_URL}

${WILDFLY_CLI_PATH} -c <<EOF
batch
/subsystem=elytron-oidc-client/secure-deployment="${KEYCLOAK_WAR}"/:add(${DEPLOYMENT_CONFIG})
/subsystem=elytron-oidc-client/secure-deployment="${KEYCLOAK_WAR}"/credential=secret:add(secret="${KEYCLOAK_SECRET}")
run-batch
EOF
}

config_oracle_client()
if [[ -z "${ORACLE_DATASOURCE}" ]]; then
  echo "Skipping config_oracle_client because ORACLE_DATASOURCE undefined"
  return 0
fi

${WILDFLY_CLI_PATH} -c <<EOF
batch
data-source add --name=jdbc/${ORACLE_DATASOURCE} --driver-name=oracle --jndi-name=java:/jdbc/${ORACLE_DATASOURCE} --connection-url=jdbc:oracle:thin:@//${ORACLE_SERVER}/${ORACLE_SERVICE} --user-name=${ORACLE_USER} --password=${ORACLE_PASS} --max-pool-size=3 --min-pool-size=1 --flush-strategy=EntirePool --use-fast-fail=true --blocking-timeout-wait-millis=5000 --query-timeout=30 --idle-timeout-minutes=5 --background-validation=true --background-validation-millis=30000 --validate-on-match=false --check-valid-connection-sql="select 1 from dual" --prepared-statements-cache-size=10 --share-prepared-statements=true
run-batch
EOF
}

wildfly_reload() {
${WILDFLY_CLI_PATH} -c reload
}

wildfly_stop() {
if [[ ! -z "${WILDFLY_SKIP_STOP}" ]]; then
  echo "Skipping Wildfly stop because WILDFLY_SKIP_STOP defined"
  return 0
fi

${WILDFLY_CLI_PATH} -c shutdown
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
