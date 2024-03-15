#!/bin/bash

echo "----------------------------------------------------"
echo "| Step 1: Waiting for Database to start listening  |"
echo "----------------------------------------------------"
if [[ -n ${ORACLE_USER} && -n ${ORACLE_PASS} && -n ${ORACLE_SERVER} && -n ${ORACLE_SERVICE} && -n ${ORACLE_DRIVER_PATH} ]]; then
  echo "Detected Oracle config.  Attempting to connect."
  until java -cp "/:${ORACLE_DRIVER_PATH}" \
        /TestOracleConnection.java "jdbc:oracle:thin:${ORACLE_USER}/${ORACLE_PASS}@${ORACLE_SERVER}/${ORACLE_SERVICE}" "${DB_DEBUG}"
  do
    echo $(date) " Still waiting for Oracle to start..."
    sleep 5
  done

  echo $(date) " Oracle connection successful!"

elif [[ -n ${MARIADB_USER} && -n ${MARIADB_PASS} && -n ${MARIADB_SERVER} && -n ${MARIADB_DB_NAME} && -n ${MARIADB_DRIVER_PATH} ]]; then
  echo "Detected MariaDB config.  Attempting to connect."
  until java -cp "/:${MARIADB_DRIVER_PATH}" \
        /TestMariadbConnection.java "jdbc:mariadb://${MARIADB_SERVER}/${MARIADB_DB_NAME}?user=${MARIADB_USER}&password=${MARIADB_PASS}" "${DB_DEBUG}"
  do
    echo $(date) " Still waiting for MariaDB to start..."
    sleep 5
  done

  echo $(date) " MariaDB connection successful!"

else
  echo $(date) " Skipping DB Wait"
fi

echo "----------------------------"
echo "| Step 2: Starting Wildfly |"
echo "----------------------------"

/opt/jboss/wildfly/bin/standalone.sh -b 0.0.0.0 -bmanagement 0.0.0.0 &

until curl http://localhost:8080 -sf -o /dev/null;
do
  echo $(date) " Still waiting for Wildfly to start..."
  sleep 5
done

echo $(date) " Wildfly started!"

sleep infinity