#!/bin/bash

FUNCTIONS=(wildfly_start_and_wait
           allow_elytron_url_params
           config_oracle_driver
           config_mariadb_driver
           config_access_log
           config_admin_user
           config_ssl
           config_gzip
           config_email
           config_persist_sessions_on_redeploy
           config_param_limits
           config_provided
           config_proxy
           wildfly_reload
           wildfly_stop)

VARIABLES=(WILDFLY_APP_HOME
           WILDFLY_RUN_USER)

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
# - ADD_JBOSS_MODULES
# - APPLY_ELYTRON_PATCH
# - MAX_PARAM_COUNT
# - KEYSTORE_NAME
# - KEYSTORE_PASS
# - PERSISTENT_SESSIONS
# - EMAIL_FROM
# - EMAIL_HOST
# - EMAIL_PORT
# - ORACLE_DRIVER_PATH
# - ORACLE_DRIVER_URL
# - MARIADB_DRIVER_PATH
# - MARIADB_DRIVER_URL
# - WILDFLY_USER
# - WILDFLY_PASS
# - WILDFLY_SKIP_START
# - WILDFLY_SKIP_STOP

WILDFLY_CLI_PATH=${WILDFLY_APP_HOME}/bin/jboss-cli.sh
MAIN_ENV_FILE=$1

wildfly_start_and_wait() {
if [[ ! -z "${WILDFLY_SKIP_START}" ]]; then
  echo "Skipping Wildfly start because WILDFLY_SKIP_START defined"
  return 0
fi

su -s /bin/sh ${WILDFLY_RUN_USER} -c "${WILDFLY_APP_HOME}/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0 &"

until curl http://localhost:8080 -sf -o /dev/null;
do
  echo $(date) " Still waiting for Wildfly to start..."
  sleep 5
done

echo $(date) " Wildfly started!"
}

config_oracle_driver() {
if [[ -z "${ORACLE_DRIVER_PATH}" ]]; then
    echo "Skipping Oracle Driver Setup: Must provide ORACLE_DRIVER_PATH in environment"
    return 0
fi

wget -O "${ORACLE_DRIVER_PATH}" "${ORACLE_DRIVER_URL}"

${WILDFLY_CLI_PATH} -c <<EOF
batch
module add --name=com.oracle.database.jdbc --resources=${ORACLE_DRIVER_PATH} --dependencies=javax.api,javax.transaction.api
/subsystem=datasources/jdbc-driver=oracle:add(driver-name=oracle,driver-module-name=com.oracle.database.jdbc)
run-batch
EOF
}

config_mariadb_driver() {
echo "Configuring mariadb_driver"
if [[ -z "${MARIADB_DRIVER_PATH}" ]]; then
    echo "Skipping MariaDB Driver Setup: Must provide MARIADB_DRIVER_PATH in environment"
    return 0
fi

echo wget -O "${MARIADB_DRIVER_PATH}" "${MARIADB_DRIVER_URL}"
wget -O "${MARIADB_DRIVER_PATH}" "${MARIADB_DRIVER_URL}"

${WILDFLY_CLI_PATH} -c <<EOF
batch
module add --name=org.mariadb.jdbc --resources=${MARIADB_DRIVER_PATH} --dependencies=javax.api,javax.transaction.api
/subsystem=datasources/jdbc-driver=mariadb:add(driver-name=mariadb,driver-module-name=org.mariadb.jdbc)
run-batch
EOF
}

allow_elytron_url_params() {
${WILDFLY_CLI_PATH} -c <<EOF
batch
/system-property=wildfly.elytron.oidc.allow.query.params:add(value=true)
run-batch
EOF
}

config_admin_user() {
if [[ -z "${WILDFLY_USER}" ]]; then
  echo "Skipping config admin because WILDFLY_USER undefined"
  return 0
fi

${WILDFLY_APP_HOME}/bin/add-user.sh "${WILDFLY_USER}" "${WILDFLY_PASS}"
}

config_ssl() {
if [[ -z "${KEYSTORE_NAME}" ]]; then
  echo "Skipping config ssl because KEYSTORE_NAME undefined"
  return 0
else
  ${WILDFLY_CLI_PATH} -c <<EOF
  batch
  /subsystem=elytron/key-store=httpsKS:add(path=${KEYSTORE_NAME},relative-to=jboss.server.config.dir,credential-reference={clear-text=${KEYSTORE_PASS}},type=PKCS12)
  /subsystem=elytron/key-manager=httpsKM:add(key-store=httpsKS,credential-reference={clear-text=${KEYSTORE_PASS}})
  /subsystem=elytron/server-ssl-context=httpsSSC:add(key-manager=httpsKM,protocols=["TLSv1.2"])
  /subsystem=undertow/server=default-server/https-listener=https:undefine-attribute(name=security-realm)
  /subsystem=undertow/server=default-server/https-listener=https:write-attribute(name=ssl-context,value=httpsSSC)
  run-batch
EOF
fi

if [[ -z "${ENABLE_MANAGEMENT_HTTPS}" ]]; then
  echo "Skipping config management ssl because ENABLE_MANAGEMENT_HTTPS undefined"
  return 0
else
  ${WILDFLY_CLI_PATH} -c <<EOF
  batch
  /core-service=management/management-interface=http-interface:write-attribute(name=ssl-context,value=httpsSSC)
  /core-service=management/management-interface=http-interface:write-attribute(name=secure-socket-binding, value=management-https)
  run-batch
EOF
fi
}

config_proxy() {
if [[ -z "${PROXY}" ]]; then
  echo "Skipping proxy config because PROXY undefined"
  return 0
fi

${WILDFLY_CLI_PATH} -c <<EOF
batch
/subsystem=undertow/server=default-server/https-listener=https:write-attribute(name=proxy-address-forwarding,value=true)
run-batch
EOF
}

config_access_log() {
if [[ -z "${ACCESS_LOG}" ]]; then
  echo "Skipping access log config because ACCESS_LOG undefined"
  return 0
fi

${WILDFLY_CLI_PATH} -c <<EOF
batch
/subsystem=undertow/server=default-server/host=default-host/setting=access-log:add(pattern="%h %l %u %t \"%r\" %s %b")
run-batch
EOF
}

config_gzip() {
if [[ -z "${GZIP}" ]]; then
  echo "Skipping gzip config because GZIP undefined"
  return 0
fi

${WILDFLY_CLI_PATH} -c <<EOF
batch
/subsystem=undertow/configuration=filter/gzip=gzipFilter:add()
/subsystem=undertow/server=default-server/host=default-host/filter-ref=gzipFilter:add()
run-batch
EOF
}

config_email() {
if [[ -z "${EMAIL_FROM}" ]]; then
  echo "Skipping email config because EMAIL_FROM undefined"
  return 0
fi

${WILDFLY_CLI_PATH} -c <<EOF
batch
/subsystem=mail/mail-session=jlab:add(from="${EMAIL_FROM}", jndi-name="java:/mail/jlab")
/socket-binding-group=standard-sockets/remote-destination-outbound-socket-binding=mail-smtp-jlab:add(host=${EMAIL_HOST}, port=${EMAIL_PORT})
/subsystem=mail/mail-session=jlab/server=smtp:add(outbound-socket-binding-ref=mail-smtp-jlab)
run-batch
EOF
}

config_persist_sessions_on_redeploy() {
if [[ -z "${PERSISTENT_SESSIONS}" ]]; then
  echo "Skipping persistent sessions on redeploy because PERSISTENT_SESSIONS undefined"
  return 0
fi

${WILDFLY_CLI_PATH} -c "/subsystem=undertow/servlet-container=default/setting=persistent-sessions:add()"
}

config_param_limits() {
if [[ -z "${MAX_PARAM_COUNT}" ]]; then
  echo "Skipping max param count because MAX_PARAM_COUNT undefined"
  return 0
fi

${WILDFLY_CLI_PATH} -c <<EOF
batch
/subsystem=undertow/server=default-server/http-listener=default:write-attribute(name=max-parameters,value=${MAX_PARAM_COUNT})
/subsystem=undertow/server=default-server/https-listener=https:write-attribute(name=max-parameters,value=${MAX_PARAM_COUNT})
run-batch
EOF
}

do_provided_config() {
echo "Using env file: ${ENV_FILE}"

DIRNAME=`dirname "$0"`
SCRIPT_HOME=`cd -P "$DIRNAME"; pwd`
${SCRIPT_HOME}/provided-setup.sh "${ENV_FILE}"
}

config_provided() {
if [[ -z "${ADD_JBOSS_MODULES}" ]]; then
  echo "Skipping config of provided dependencies because ADD_JBOSS_MODULES undefined"
  return 0
fi

ENV_FILE="${MAIN_ENV_FILE}"

do_provided_config
}

wildfly_reload() {
if [[ ! -z "${WILDFLY_SKIP_RELOAD}" ]]; then
  echo "Skipping Wildfly reload because WILDFLY_SKIP_RELOAD defined"
  return 0
fi

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





