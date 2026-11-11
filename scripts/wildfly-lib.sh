#!/bin/bash
#
# wildfly-lib.sh: functions that install and configure Wildfly.
#
# Source it and call the functions from your own script:
#
#   . /wildfly-lib.sh
#   WILDFLY_APP_HOME=/opt/wildfly/current
#   wildfly_start_and_wait && config_gzip && wildfly_reload && wildfly_stop
#
# or run it with an env file and the functions to call, in order:
#
#   /wildfly-lib.sh -e /app-setup.env wildfly_start_and_wait config_keycloak_client wildfly_stop
#
# Each function checks the variables it needs, says which are missing, and returns non-zero. It
# never exits, so it can't end the shell that sourced it. Run it with --help for the list of
# functions and their variables.
#
# Names starting with _ are private helpers: they may change and can't be run from the command line.

#### Install Wildfly on a host or in an image

# Installs Java 21 with yum and removes Java 11 and 17.
install_java() {
  yum install java-21-openjdk -y \
    && yum remove java-11-openjdk-headless -y \
    && yum remove java-17-openjdk-headless -y
}

# Creates the system user and group that run Wildfly, with WILDFLY_USER_HOME as the user's home.
# Required: WILDFLY_GROUP WILDFLY_GROUP_ID WILDFLY_USER WILDFLY_USER_HOME WILDFLY_USER_ID
create_user_and_group() {
  _require_vars WILDFLY_GROUP WILDFLY_GROUP_ID WILDFLY_USER WILDFLY_USER_HOME WILDFLY_USER_ID || return
  groupadd -r -g "${WILDFLY_GROUP_ID}" "${WILDFLY_GROUP}" \
    && useradd -r -m -u "${WILDFLY_USER_ID}" -g "${WILDFLY_GROUP_ID}" -d "${WILDFLY_USER_HOME}" \
         -s /bin/bash "${WILDFLY_USER}"
}

# Downloads the Wildfly release zip to /tmp.
# Required: WILDFLY_VERSION
download_wildfly() {
  _require_vars WILDFLY_VERSION || return
  curl -fsSL -o "/tmp/wildfly-${WILDFLY_VERSION}.zip" \
    "https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.zip"
}

# Unzips the downloaded release to WILDFLY_USER_HOME/WILDFLY_VERSION, owned by WILDFLY_USER.
# Required: WILDFLY_USER WILDFLY_USER_HOME WILDFLY_VERSION
# Optional: WILDFLY_GROUP: the owning group; the user's login group if unset
unzip_wildfly() {
  _require_vars WILDFLY_USER WILDFLY_USER_HOME WILDFLY_VERSION || return
  unzip -q "/tmp/wildfly-${WILDFLY_VERSION}.zip" -d "${WILDFLY_USER_HOME}" \
    && mv "${WILDFLY_USER_HOME}/wildfly-${WILDFLY_VERSION}" "${WILDFLY_USER_HOME}/${WILDFLY_VERSION}" \
    && chown -R "${WILDFLY_USER}:${WILDFLY_GROUP:-}" "${WILDFLY_USER_HOME}"
}

# Links WILDFLY_USER_HOME/current to the release, and configuration and log to its standalone dirs.
# Required: WILDFLY_USER_HOME WILDFLY_VERSION
create_wildfly_symlinks() {
  _require_vars WILDFLY_USER_HOME WILDFLY_VERSION || return
  ln -s "${WILDFLY_VERSION}" "${WILDFLY_USER_HOME}/current" \
    && ln -s current/standalone/configuration "${WILDFLY_USER_HOME}/configuration" \
    && ln -s current/standalone/log "${WILDFLY_USER_HOME}/log"
}

# Sets JAVA_HOME and the heap sizes in the release's bin/standalone.conf.
# Required: JDK_HOME JDK_MAX_HEAP JDK_MIN_HEAP WILDFLY_USER_HOME WILDFLY_VERSION
adjust_jvm_options() {
  _require_vars JDK_HOME JDK_MAX_HEAP JDK_MIN_HEAP WILDFLY_USER_HOME WILDFLY_VERSION || return
  sed -i -e "s|#JAVA_HOME=\"/opt/java/jdk\"|JAVA_HOME=\"${JDK_HOME}\"|g" \
         -e "s/Xms64m/Xms${JDK_MIN_HEAP}/g" \
         -e "s/Xmx512m/Xmx${JDK_MAX_HEAP}/g" \
         "${WILDFLY_USER_HOME}/${WILDFLY_VERSION}/bin/standalone.conf"
}

# Creates and enables the wildfly systemd service, and lets it bind WILDFLY_HTTPS_PORT if below 1024.
# The service reads WILDFLY_USER_HOME/configuration/run.env.
# Required: WILDFLY_BIND_ADDRESS WILDFLY_HTTPS_PORT WILDFLY_USER WILDFLY_USER_HOME
create_systemd_service() {
  _require_vars WILDFLY_BIND_ADDRESS WILDFLY_HTTPS_PORT WILDFLY_USER WILDFLY_USER_HOME || return
  if (( WILDFLY_HTTPS_PORT < 1024 )); then
    sysctl -w "net.ipv4.ip_unprivileged_port_start=${WILDFLY_HTTPS_PORT}" >> /etc/sysctl.conf || return
  fi

  cat > /etc/systemd/system/wildfly.service <<EOF || return
[Unit]
Description=The WildFly Application Server
After=syslog.target network.target
Before=httpd.service
[Service]
EnvironmentFile=${WILDFLY_USER_HOME}/configuration/run.env
Environment=LAUNCH_JBOSS_IN_BACKGROUND=1
User=${WILDFLY_USER}
LimitNOFILE=102642
PIDFile=/run/wildfly.pid
ExecStart=${WILDFLY_USER_HOME}/current/bin/standalone.sh -b ${WILDFLY_BIND_ADDRESS} -bmanagement ${WILDFLY_BIND_ADDRESS} -Djboss.https.port=${WILDFLY_HTTPS_PORT}
StandardOutput=null
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable wildfly
}

# Adds a daily cron job, run as WILDFLY_USER, that deletes Wildfly logs older than 30 days.
# Required: WILDFLY_USER WILDFLY_USER_HOME
create_log_file_cleanup_cron() {
  _require_vars WILDFLY_USER WILDFLY_USER_HOME || return
  local script="${WILDFLY_USER_HOME}/delete-old-wildfly-logs.sh"
  cat > "${script}" <<EOF || return
#!/bin/sh
if [ -d ${WILDFLY_USER_HOME}/log ] ; then
 /usr/bin/find ${WILDFLY_USER_HOME}/log/ -mtime +30 -exec /usr/bin/rm {} \;
fi
EOF
  chmod +x "${script}" \
    && echo "0 0 * * * ${WILDFLY_USER} ${script} >/dev/null 2>&1" > /etc/cron.d/delete-old-wildfly-logs.cron
}

#### Start and stop Wildfly

# Starts Wildfly in the background and waits until it answers on port 8080.
# Required: WILDFLY_APP_HOME
# Optional: WILDFLY_RUN_USER: the user to run Wildfly as, if not the current user
wildfly_start_and_wait() {
  _require_vars WILDFLY_APP_HOME || return
  local -a cmd=("${WILDFLY_APP_HOME}/bin/standalone.sh" -b 0.0.0.0 -bmanagement 0.0.0.0)
  if [[ -n "${WILDFLY_RUN_USER:-}" && "$(id -un)" != "${WILDFLY_RUN_USER}" ]]; then
    su -s /bin/sh "${WILDFLY_RUN_USER}" -c "${cmd[*]@Q} &" || return
  else
    "${cmd[@]}" &
  fi

  until curl -sf -o /dev/null http://localhost:8080; do
    _log "$(date) Still waiting for Wildfly to start..."
    sleep 5
  done
  _log "$(date) Wildfly started!"
}

# Reloads Wildfly's configuration.
# Required: WILDFLY_APP_HOME
wildfly_reload() {
  _require_vars WILDFLY_APP_HOME || return
  _cli reload
}

# Shuts Wildfly down.
# Required: WILDFLY_APP_HOME
wildfly_stop() {
  _require_vars WILDFLY_APP_HOME || return
  _cli shutdown
}

#### Configure the server (Wildfly must be running)

# Replaces Elytron 2.6.4's OIDC client jar with a patched one, checked against its SHA-256, so logging
# in from a page whose URL has encoded characters (such as a date's space and colon) works. Elytron
# 2.6.4, in Wildfly 37.0.1, uses a decoded query in the OIDC redirect_uri, which fails with
# "Incorrect redirect_uri". The fix is in Elytron 2.6.7, which needs other jars too. Skips, and
# succeeds, if the 2.6.4 jar isn't there. Wildfly needn't be running.
# https://github.com/slominskir/wildfly-elytron/releases/tag/v2.6.4.Patch1
# https://github.com/JeffersonLab/dtm/issues/73
# Required: WILDFLY_APP_HOME
apply_elytron_patch() {
  _require_vars WILDFLY_APP_HOME || return
  local jar="${WILDFLY_APP_HOME}/modules/system/layers/base/org/wildfly/security/elytron-http-oidc/main/wildfly-elytron-http-oidc-2.6.4.Final.jar"
  local url=https://github.com/slominskir/wildfly-elytron/releases/download/v2.6.4.Patch1/wildfly-elytron-http-oidc-2.6.4.Final.jar
  local sha256=e9035f4226028fe5b62b088918414247af49acbd8af6622ac8c47a3bda9052b4
  if [[ ! -f "${jar}" ]]; then
    _log "Skipping elytron patch because ${jar} not found: the patch is for Elytron 2.6.4 (Wildfly 37.0.1)"
    return 0
  fi
  if ! curl -fsSL -o /tmp/elytron-patch.jar "${url}" \
       || ! echo "${sha256}  /tmp/elytron-patch.jar" | sha256sum -c -; then
    _err "Unable to download or verify elytron patch"
    return 1
  fi
  mv "${jar}" "${jar}.bak" \
    && mv /tmp/elytron-patch.jar "${jar}" \
    && chmod 644 "${jar}" \
    && _log "Applied elytron patch v2.6.4.Patch1"
}

# Lets the Elytron OIDC client keep the query parameters of the page that started the login.
# Required: WILDFLY_APP_HOME
allow_elytron_url_params() {
  _require_vars WILDFLY_APP_HOME || return
  _cli <<EOF
batch
/system-property=wildfly.elytron.oidc.allow.query.params:add(value=true)
run-batch
EOF
}

# Downloads the Oracle JDBC driver and adds it as a module and as the "oracle" JDBC driver.
# Required: ORACLE_DRIVER_PATH: where to save the jar
#           ORACLE_DRIVER_URL WILDFLY_APP_HOME
config_oracle_driver() {
  _require_vars ORACLE_DRIVER_PATH ORACLE_DRIVER_URL WILDFLY_APP_HOME || return
  curl -fsSL -o "${ORACLE_DRIVER_PATH}" "${ORACLE_DRIVER_URL}" || return
  _cli <<EOF
batch
module add --name=com.oracle.database.jdbc --resources=${ORACLE_DRIVER_PATH} --dependencies=javax.api,javax.transaction.api
/subsystem=datasources/jdbc-driver=oracle:add(driver-name=oracle,driver-module-name=com.oracle.database.jdbc)
run-batch
EOF
}

# Downloads the MariaDB JDBC driver and adds it as a module and as the "mariadb" JDBC driver.
# Required: MARIADB_DRIVER_PATH: where to save the jar
#           MARIADB_DRIVER_URL WILDFLY_APP_HOME
config_mariadb_driver() {
  _require_vars MARIADB_DRIVER_PATH MARIADB_DRIVER_URL WILDFLY_APP_HOME || return
  curl -fsSL -o "${MARIADB_DRIVER_PATH}" "${MARIADB_DRIVER_URL}" || return
  _cli <<EOF
batch
module add --name=org.mariadb.jdbc --resources=${MARIADB_DRIVER_PATH} --dependencies=javax.api,javax.transaction.api
/subsystem=datasources/jdbc-driver=mariadb:add(driver-name=mariadb,driver-module-name=org.mariadb.jdbc)
run-batch
EOF
}

# Turns on the access log, in common log format.
# Required: WILDFLY_APP_HOME
config_access_log() {
  _require_vars WILDFLY_APP_HOME || return
  _cli <<EOF
batch
/subsystem=undertow/server=default-server/host=default-host/setting=access-log:add(pattern="%h %l %u %t \"%r\" %s %b")
run-batch
EOF
}

# Adds a management (admin console) user.
# Required: WILDFLY_ADMIN_USER WILDFLY_ADMIN_PASS WILDFLY_APP_HOME
config_admin_user() {
  _require_vars WILDFLY_ADMIN_PASS WILDFLY_ADMIN_USER WILDFLY_APP_HOME || return
  "${WILDFLY_APP_HOME}/bin/add-user.sh" "${WILDFLY_ADMIN_USER}" "${WILDFLY_ADMIN_PASS}"
}

# Serves HTTPS with a PKCS12 keystore from the configuration dir.
# Required: KEYSTORE_NAME: the keystore's file name in the configuration dir
#           KEYSTORE_PASS WILDFLY_APP_HOME
# Optional: ENABLE_MANAGEMENT_HTTPS: if set, the management interface uses HTTPS with it too
config_ssl() {
  _require_vars KEYSTORE_NAME KEYSTORE_PASS WILDFLY_APP_HOME || return
  _cli <<EOF || return
batch
/subsystem=elytron/key-store=httpsKS:add(path=${KEYSTORE_NAME},relative-to=jboss.server.config.dir,credential-reference={clear-text=${KEYSTORE_PASS}},type=PKCS12)
/subsystem=elytron/key-manager=httpsKM:add(key-store=httpsKS,credential-reference={clear-text=${KEYSTORE_PASS}})
/subsystem=elytron/server-ssl-context=httpsSSC:add(key-manager=httpsKM,protocols=["TLSv1.2"])
/subsystem=undertow/server=default-server/https-listener=https:undefine-attribute(name=security-realm)
/subsystem=undertow/server=default-server/https-listener=https:write-attribute(name=ssl-context,value=httpsSSC)
run-batch
EOF

  if [[ -n "${ENABLE_MANAGEMENT_HTTPS:-}" ]]; then
    _cli <<EOF
batch
/core-service=management/management-interface=http-interface:write-attribute(name=ssl-context,value=httpsSSC)
/core-service=management/management-interface=http-interface:write-attribute(name=secure-socket-binding, value=management-https)
run-batch
EOF
  fi
}

# Trusts X-Forwarded-* headers on the HTTPS listener, for use behind a reverse proxy.
# Required: WILDFLY_APP_HOME
config_proxy() {
  _require_vars WILDFLY_APP_HOME || return
  _cli <<EOF
batch
/subsystem=undertow/server=default-server/https-listener=https:write-attribute(name=proxy-address-forwarding,value=true)
run-batch
EOF
}

# Compresses responses with gzip.
# Required: WILDFLY_APP_HOME
config_gzip() {
  _require_vars WILDFLY_APP_HOME || return
  _cli <<EOF
batch
/subsystem=undertow/configuration=filter/gzip=gzipFilter:add()
/subsystem=undertow/server=default-server/host=default-host/filter-ref=gzipFilter:add()
run-batch
EOF
}

# Sets the SameSite attribute of every app's session cookie (JSESSIONID).
# Required: SAMESITE_COOKIE: Strict, Lax (recommended), or None
#           WILDFLY_APP_HOME
config_samesite_cookie() {
  _require_vars SAMESITE_COOKIE WILDFLY_APP_HOME || return
  case "${SAMESITE_COOKIE}" in
    Strict|Lax|None) ;;
    *) _err "SAMESITE_COOKIE must be Strict, Lax, or None; found ${SAMESITE_COOKIE}"; return 1 ;;
  esac
  _cli <<EOF
batch
/subsystem=undertow/configuration=filter/expression-filter=samesite-cookie:add(expression="samesite-cookie(mode=${SAMESITE_COOKIE}, cookie-pattern=JSESSIONID)")
/subsystem=undertow/server=default-server/host=default-host/filter-ref=samesite-cookie:add()
run-batch
EOF
}

# Adds the java:/mail/jlab mail session, sending through an SMTP server.
# Required: EMAIL_FROM: the default from address
#           EMAIL_HOST EMAIL_PORT WILDFLY_APP_HOME
config_email() {
  _require_vars EMAIL_FROM EMAIL_HOST EMAIL_PORT WILDFLY_APP_HOME || return
  _cli <<EOF
batch
/subsystem=mail/mail-session=jlab:add(from="${EMAIL_FROM}", jndi-name="java:/mail/jlab")
/socket-binding-group=standard-sockets/remote-destination-outbound-socket-binding=mail-smtp-jlab:add(host=${EMAIL_HOST}, port=${EMAIL_PORT})
/subsystem=mail/mail-session=jlab/server=smtp:add(outbound-socket-binding-ref=mail-smtp-jlab)
run-batch
EOF
}

# Keeps HTTP sessions when an app is redeployed.
# Required: WILDFLY_APP_HOME
config_persist_sessions_on_redeploy() {
  _require_vars WILDFLY_APP_HOME || return
  _cli "/subsystem=undertow/servlet-container=default/setting=persistent-sessions:add()"
}

# Sets the most request parameters the HTTP and HTTPS listeners accept.
# Required: MAX_PARAM_COUNT WILDFLY_APP_HOME
config_param_limits() {
  _require_vars MAX_PARAM_COUNT WILDFLY_APP_HOME || return
  _cli <<EOF
batch
/subsystem=undertow/server=default-server/http-listener=default:write-attribute(name=max-parameters,value=${MAX_PARAM_COUNT})
/subsystem=undertow/server=default-server/https-listener=https:write-attribute(name=max-parameters,value=${MAX_PARAM_COUNT})
run-batch
EOF
}

# Downloads jars and adds them as JBoss modules, one per line of ADD_JBOSS_MODULES:
#   scope|module name|comma-separated jar URLs|comma-separated module dependencies
# A scope of global makes the module a global module, which every app sees; local doesn't.
# Required: ADD_JBOSS_MODULES WILDFLY_APP_HOME
add_jboss_modules() {
  _require_vars ADD_JBOSS_MODULES WILDFLY_APP_HOME || return
  local scope name resources deps
  while IFS='|' read -r scope name resources deps; do
    [[ -n "${scope}" ]] || continue
    _log "Adding ${scope} module ${name}"
    _add_module "${name}" "${resources}" "${deps}" || return
    if [[ "${scope}" == global ]]; then
      _set_global_module "${name}" || return
    fi
  done <<< "${ADD_JBOSS_MODULES}"
}

# Makes modules Wildfly already has global, one module name per line of GLOBAL_ENABLE_LIBS. Rarely
# needed: Wildfly adds most of its own libraries to apps implicitly, and an app can add one itself
# with jboss-deployment-structure.xml or its manifest. See https://docs.wildfly.org/26/Developer_Guide.html
# Required: GLOBAL_ENABLE_LIBS WILDFLY_APP_HOME
enable_global_modules() {
  _require_vars GLOBAL_ENABLE_LIBS WILDFLY_APP_HOME || return
  local name
  while read -r name; do
    [[ -n "${name}" ]] || continue
    _set_global_module "${name}" || return
  done <<< "${GLOBAL_ENABLE_LIBS}"
}

# Sets the level of loggers, one per line of LOG_LEVELS: category=LEVEL, such as
#   org.apache.kafka.clients=ERROR
# Adds each logger, or changes its level if Wildfly already has it. LEVEL is one Wildfly knows:
# ALL, TRACE, DEBUG, INFO, WARN, ERROR, FATAL, or OFF, or a java.util.logging level such as FINE.
# Required: LOG_LEVELS WILDFLY_APP_HOME
config_log_levels() {
  _require_vars LOG_LEVELS WILDFLY_APP_HOME || return
  local line category level logger
  while read -r line; do
    [[ -n "${line}" ]] || continue
    category=${line%%=*}
    level=${line#*=}
    if [[ "${line}" != *=* || ! "${category}" =~ ^[[:alnum:]_.$-]+$ || ! "${level}" =~ ^[[:alpha:]]+$ ]]; then
      _err "Each line of LOG_LEVELS must be category=LEVEL; found ${line}"
      return 1
    fi
    _log "Setting logger ${category} to ${level}"
    logger="/subsystem=logging/logger=${category}"
    _cli <<EOF || return
if (outcome != success) of ${logger}:read-resource
  ${logger}:add(level=${level})
else
  ${logger}:write-attribute(name=level,value=${level})
end-if
EOF
  done <<< "${LOG_LEVELS}"
}

#### Configure an app (Wildfly must be running)

# Secures KEYCLOAK_WAR with Keycloak (OIDC), using the values as they are now.
# Required: KEYCLOAK_REALM KEYCLOAK_RESOURCE KEYCLOAK_SECRET KEYCLOAK_SERVER_URL KEYCLOAK_WAR WILDFLY_APP_HOME
config_keycloak_client() {
  _require_vars KEYCLOAK_REALM KEYCLOAK_RESOURCE KEYCLOAK_SECRET KEYCLOAK_SERVER_URL KEYCLOAK_WAR \
    WILDFLY_APP_HOME || return
  _keycloak_client "${KEYCLOAK_REALM}" "${KEYCLOAK_RESOURCE}" "${KEYCLOAK_SECRET}" "${KEYCLOAK_SERVER_URL}"
}

# Like config_keycloak_client, but environment variables of the same names override the values
# when Wildfly runs. For a Wildfly that runs only this app, such as in a container.
# Required: KEYCLOAK_REALM KEYCLOAK_RESOURCE KEYCLOAK_SECRET KEYCLOAK_SERVER_URL KEYCLOAK_WAR WILDFLY_APP_HOME
config_keycloak_client_dynamic() {
  _require_vars KEYCLOAK_REALM KEYCLOAK_RESOURCE KEYCLOAK_SECRET KEYCLOAK_SERVER_URL KEYCLOAK_WAR \
    WILDFLY_APP_HOME || return
  _keycloak_client "\${env.KEYCLOAK_REALM:${KEYCLOAK_REALM}}" "\${env.KEYCLOAK_RESOURCE:${KEYCLOAK_RESOURCE}}" \
    "\${env.KEYCLOAK_SECRET:${KEYCLOAK_SECRET}}" "\${env.KEYCLOAK_SERVER_URL:${KEYCLOAK_SERVER_URL}}"
}

# Adds the Oracle datasource java:/jdbc/ORACLE_DATASOURCE, using the values as they are now.
# Required: ORACLE_DATASOURCE ORACLE_PASS ORACLE_SERVER ORACLE_SERVICE ORACLE_USER WILDFLY_APP_HOME
config_oracle_client() {
  _require_vars ORACLE_DATASOURCE ORACLE_PASS ORACLE_SERVER ORACLE_SERVICE ORACLE_USER WILDFLY_APP_HOME || return
  _datasource "${ORACLE_DATASOURCE}" oracle "jdbc:oracle:thin:@//${ORACLE_SERVER}/${ORACLE_SERVICE}" \
    "${ORACLE_USER}" "${ORACLE_PASS}"
}

# Like config_oracle_client, but environment variables ORACLE_SERVER, ORACLE_SERVICE, ORACLE_USER,
# and ORACLE_PASS override the values when Wildfly runs. For a Wildfly that runs only this app.
# Required: ORACLE_DATASOURCE ORACLE_PASS ORACLE_SERVER ORACLE_SERVICE ORACLE_USER WILDFLY_APP_HOME
config_oracle_client_dynamic() {
  _require_vars ORACLE_DATASOURCE ORACLE_PASS ORACLE_SERVER ORACLE_SERVICE ORACLE_USER WILDFLY_APP_HOME || return
  _datasource "${ORACLE_DATASOURCE}" oracle \
    "jdbc:oracle:thin:@//\${env.ORACLE_SERVER:${ORACLE_SERVER}}/\${env.ORACLE_SERVICE:${ORACLE_SERVICE}}" \
    "\${env.ORACLE_USER:${ORACLE_USER}}" "\${env.ORACLE_PASS:${ORACLE_PASS}}"
}

# Adds the MariaDB datasource java:/jdbc/MARIADB_DATASOURCE.
# Required: MARIADB_DATASOURCE MARIADB_DB_NAME MARIADB_PASS MARIADB_SERVER MARIADB_USER WILDFLY_APP_HOME
config_mariadb_client() {
  _require_vars MARIADB_DATASOURCE MARIADB_DB_NAME MARIADB_PASS MARIADB_SERVER MARIADB_USER \
    WILDFLY_APP_HOME || return
  _datasource "${MARIADB_DATASOURCE}" mariadb "jdbc:mariadb://${MARIADB_SERVER}/${MARIADB_DB_NAME}" \
    "${MARIADB_USER}" "${MARIADB_PASS}"
}

#### Utilities

# Makes a PKCS12 keystore, for config_ssl, from a PEM certificate, its intermediate, and its key.
# Required: KEYSTORE_OUTPUT_PATH KEYSTORE_PASS PEM_CERT_PATH PEM_INTERMEDIATE_CERT_PATH PEM_KEY_PATH
pem_to_keystore() {
  _require_vars KEYSTORE_OUTPUT_PATH KEYSTORE_PASS PEM_CERT_PATH PEM_INTERMEDIATE_CERT_PATH PEM_KEY_PATH \
    || return
  local dir status
  dir=$(mktemp -d) || return
  cat "${PEM_CERT_PATH}" "${PEM_INTERMEDIATE_CERT_PATH}" > "${dir}/combined.pem" \
    && openssl pkcs12 -export -in "${dir}/combined.pem" -inkey "${PEM_KEY_PATH}" -name combined \
         -password "pass:${KEYSTORE_PASS}" > "${dir}/combined.p12" \
    && keytool -importkeystore -srckeystore "${dir}/combined.p12" -destkeystore "${KEYSTORE_OUTPUT_PATH}" \
         -srcstoretype pkcs12 -alias combined -deststorepass "${KEYSTORE_PASS}" -srcstorepass "${KEYSTORE_PASS}"
  status=$?
  rm -rf "${dir}"
  return "${status}"
}

#### Private helpers

_log() {
  echo "$*"
}

_err() {
  echo "ERROR: $*" >&2
}

# Returns non-zero, naming the calling function and each variable, if any of the named variables is
# unset or empty.
_require_vars() {
  local var
  local -a missing=()
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || missing+=("${var}")
  done
  if (( ${#missing[@]} )); then
    _err "${FUNCNAME[1]} needs ${missing[*]}, which $( (( ${#missing[@]} == 1 )) && echo is || echo are ) not set"
    return 1
  fi
}

# Runs jboss-cli.sh connected to the running Wildfly, with the given arguments or, with none, the
# commands on standard input.
_cli() {
  "${WILDFLY_APP_HOME}/bin/jboss-cli.sh" -c "$@"
}

# Arguments: realm, resource, secret, server URL: values or ${env.X:default} expressions.
_keycloak_client() {
  local config="principal-attribute=\"preferred_username\",ssl-required=EXTERNAL,resource=\"$2\",realm=\"$1\",auth-server-url=$4"
  _cli <<EOF
batch
/subsystem=elytron-oidc-client/secure-deployment="${KEYCLOAK_WAR}"/:add(${config})
/subsystem=elytron-oidc-client/secure-deployment="${KEYCLOAK_WAR}"/credential=secret:add(secret="$3")
run-batch
EOF
}

# Arguments: datasource name, JDBC driver name, connection URL, user, password.
_datasource() {
  _cli <<EOF
batch
data-source add --name=jdbc/$1 --driver-name=$2 --jndi-name=java:/jdbc/$1 --connection-url=$3 --user-name=$4 --password=$5 --max-pool-size=3 --min-pool-size=1 --flush-strategy=EntirePool --use-fast-fail=true --blocking-timeout-wait-millis=5000 --query-timeout=30 --idle-timeout-minutes=5 --background-validation=true --background-validation-millis=30000 --validate-on-match=false --check-valid-connection-sql="select 1 from dual" --prepared-statements-cache-size=10 --share-prepared-statements=true
run-batch
EOF
}

# Arguments: module name, comma-separated jar URLs, comma-separated module dependencies.
_add_module() {
  local name=$1 deps=$3 dir url status
  local -a urls jars=()
  IFS=, read -r -a urls <<< "$2"
  dir=$(mktemp -d) || return
  for url in "${urls[@]}"; do
    jars+=("${dir}/${url##*/}")
    curl -fsSL -o "${jars[-1]}" "${url}" || { rm -rf "${dir}"; return 1; }
  done
  _cli <<EOF
module add --name=${name} --resource-delimiter=, --resources=$(IFS=,; echo "${jars[*]}") --dependencies=${deps}
EOF
  status=$?
  rm -rf "${dir}"
  return "${status}"
}

# Arguments: module name.
_set_global_module() {
  _cli "/subsystem=ee/:list-add(name=global-modules,value={\"name\"=>\"$1\",\"slot\"=>\"main\"})"
}

# The public functions: those defined in this file whose names don't start with _.
_public_functions() {
  sed -nE 's/^([a-z][a-z0-9_]*)\(\) \{$/\1/p' "${BASH_SOURCE[0]}"
}

_usage() {
  cat <<EOF
Usage: ${0##*/} [-e ENV_FILE]... FUNCTION...
       . ${0##*/}

Runs each FUNCTION in order, stopping at the first that fails. Each -e ENV_FILE is a file of bash
variable assignments, sourced first. Source this file instead to call the functions from a script.
Each function checks the variables it needs.

Functions:
EOF
  # Print each section heading, and each public function with the comment block above it.
  awk '
    /^#### Private/  { exit }
    /^#### /         { sub(/^#### /, ""); printf "\n  %s\n", $0; doc = ""; next }
    /^#/             { line = $0; sub(/^# ?/, "", line); doc = doc "      " line "\n"; next }
    /^[a-z][a-z0-9_]*\(\) \{$/ { sub(/\(\) \{$/, ""); printf "    %s\n%s", $0, doc; doc = ""; next }
                     { doc = "" }
  ' "${BASH_SOURCE[0]}"
}

_main() {
  set -uo pipefail
  local fn
  local -a fns=()
  while (( $# )); do
    case "$1" in
      -h|--help)
        _usage
        return 0 ;;
      -e|--env)
        if [[ ! -f "${2:-}" ]]; then
          _err "Env file not found: ${2:-}"
          return 2
        fi
        _log "Loading environment $2"
        # shellcheck disable=SC1090
        . "$2"
        shift 2 ;;
      -*)
        _err "Unknown option: $1"
        return 2 ;;
      *)
        fns+=("$1")
        shift ;;
    esac
  done

  if (( ${#fns[@]} == 0 )); then
    _usage >&2
    return 2
  fi
  for fn in "${fns[@]}"; do
    if ! _public_functions | grep -qxF -- "${fn}"; then
      _err "Unknown function: ${fn} (--help lists them)"
      return 2
    fi
  done

  for fn in "${fns[@]}"; do
    _log "------------------------"
    _log "${fn}"
    _log "------------------------"
    if ! "${fn}"; then
      _err "${fn} failed"
      return 1
    fi
  done
}

# Run only when executed, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  _main "$@"
fi
