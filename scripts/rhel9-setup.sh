#!/bin/bash

FUNCTIONS=(adjust_java
           create_user_and_group
           download
           unzip_and_chmod
           create_symbolic_links
           adjust_jvm_options
           create_systemd_service
           create_log_file_cleanup_cron)

VARIABLES=(WILDFLY_BIND_ADDRESS
           WILDFLY_GROUP
           WILDFLY_GROUP_ID
           WILDFLY_HTTPS_PORT
           WILDFLY_USER
           WILDFLY_USER_HOME
           WILDFLY_USER_ID
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

adjust_java() {
yum install java-21-openjdk -y
yum remove java-11-openjdk-headless -y
yum remove java-17-openjdk-headless -y
}

create_user_and_group() {
groupadd -r -g ${WILDFLY_GROUP_ID} ${WILDFLY_GROUP}
useradd -r -m -u ${WILDFLY_USER_ID} -g ${WILDFLY_GROUP_ID} -d ${WILDFLY_USER_HOME} -s /bin/bash ${WILDFLY_USER}
}

download() {
cd /tmp
wget https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.zip
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

create_systemd_service() {
if (( ${WILDFLY_HTTPS_PORT} < 1024 ))
then
  sysctl -w net.ipv4.ip_unprivileged_port_start=${WILDFLY_HTTPS_PORT} >> /etc/sysctl.conf
fi

cat > /etc/systemd/system/wildfly.service << EOF
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

create_log_file_cleanup_cron() {
cat > /opt/wildfly/delete-old-wildfly-logs.sh << EOF
#!/bin/sh
if [ -d ${WILDFLY_USER_HOME}/log ] ; then
 /usr/bin/find ${WILDFLY_USER_HOME}/log/ -mtime +30 -exec /usr/bin/rm {} \;
fi
EOF
chmod +x /opt/wildfly/delete-old-wildfly-logs.sh
cat > /etc/cron.d/delete-old-wildfly-logs.cron << EOF
0 0 * * * wildfly /opt/wildfly/delete-old-wildfly-logs.sh >/dev/null 2>&1
EOF
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
