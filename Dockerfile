# syntax=docker/dockerfile:1
ARG BUILD_IMAGE=gradle:7.4-jdk17
ARG RUN_IMAGE=quay.io/wildfly/wildfly:36.0.1.Final-jdk17
ARG ORACLE_DRIVER_PATH=/ojdbc11-21.7.0.0.jar
ARG MARIADB_DRIVER_PATH=/mariadb-java-client-3.3.3.jar
ARG CUSTOM_CRT_URL="https://ace.jlab.org/acc-ca.crt http://pki.jlab.org/JLabCA.crt"

################## Stage 0
FROM ${BUILD_IMAGE} AS builder
ARG CUSTOM_CRT_URL
USER root
WORKDIR /
COPY . /app
RUN /app/scripts/update-certs-builder.sh ${CUSTOM_CRT_URL}

RUN cd /tmp \
    ##&&  apk add openssl \
    && openssl genrsa -out localhost.key 2048 \
    && openssl req -key localhost.key -new -out localhost.csr -subj "/C=US/ST=Virginia/O=localhost dev/OU=IT Department/CN=localhost" \
    && openssl x509 -signkey localhost.key -in localhost.csr -req -days 99999 -out localhost.crt \
    && openssl pkcs12 -export -in localhost.crt -inkey localhost.key -name localhost -password pass:changeit > localhost.p12 \
    && keytool -importkeystore -srckeystore localhost.p12 -destkeystore server.p12 -srcstoretype pkcs12 -alias localhost -deststorepass changeit -srcstorepass changeit


## Let's minimize layers in final-product by organizing files into a single copy structure
RUN mkdir /unicopy \
    && cp /app/config/docker-server.env /unicopy \
    && cp /app/scripts/TestOracleConnection.java /unicopy \
    && cp /app/scripts/TestMariadbConnection.java /unicopy \
    && cp /app/scripts/container-entrypoint.sh /unicopy \
    && cp /app/scripts/container-healthcheck.sh /unicopy \
    && cp /app/scripts/server-setup.sh /unicopy \
    && cp /app/scripts/provided-setup.sh /unicopy \
    && cp /app/scripts/app-setup.sh /unicopy \
    && cp /app/scripts/update-certs-runner.sh /unicopy

################## Stage 1
FROM ${RUN_IMAGE} AS runner
ARG CUSTOM_CRT_URL
ARG RUN_USER=jboss
ARG ORACLE_DRIVER_PATH
ARG MARIADB_DRIVER_PATH
USER root
COPY --from=builder /unicopy /
COPY --from=builder /tmp/server.p12 /opt/jboss/wildfly/standalone/configuration
RUN /update-certs-runner.sh ${CUSTOM_CRT_URL} \
    && /server-setup.sh /docker-server.env \
    && rm -rf /opt/jboss/wildfly/standalone/configuration/standalone_xml_history
ENTRYPOINT ["/container-entrypoint.sh"]
ENV ORACLE_DRIVER_PATH=$ORACLE_DRIVER_PATH
ENV MARIADB_DRIVER_PATH=$MARIADB_DRIVER_PATH
USER ${RUN_USER}
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --start-interval=5s --retries=5 CMD /container-healthcheck.sh