ARG BUILD_IMAGE=gradle:7.4-jdk17
ARG RUN_IMAGE=quay.io/wildfly/wildfly:26.1.3.Final-jdk17
ARG ORACLE_DRIVER_PATH=/ojdbc11-21.7.0.0.jar

################## Stage 0
FROM ${BUILD_IMAGE} as builder
ARG CUSTOM_CRT_URL
USER root
WORKDIR /
RUN if [ -z "${CUSTOM_CRT_URL}" ] ; then echo "No custom cert needed"; else \
       wget -O /usr/local/share/ca-certificates/customcert.crt $CUSTOM_CRT_URL \
       && update-ca-certificates \
       && keytool -import -alias custom -file /usr/local/share/ca-certificates/customcert.crt -cacerts -storepass changeit -noprompt \
       && export OPTIONAL_CERT_ARG=--cert=/etc/ssl/certs/ca-certificates.crt \
    ; fi
COPY . /app

## Let's minimize layers in final-product by organizing files into a single copy structure
RUN mkdir /unicopy \
    && cp /app/config/docker-server.env /unicopy \
    && cp /app/scripts/TestOracleConnection.java /unicopy \
    && cp /app/scripts/docker-entrypoint.sh /unicopy \
    && cp /app/scripts/server-setup.sh /unicopy \
    && cp /app/scripts/provided-setup.sh /unicopy \
    && cp /app/scripts/app-setup.sh /unicopy

################## Stage 1
FROM ${RUN_IMAGE} as runner
ARG CUSTOM_CRT_URL
ARG INCLUDE_SMOOTH_LIB
ARG RUN_USER=jboss:jboss
ARG ORACLE_DRIVER_PATH
USER root
COPY --from=builder /unicopy /
RUN if [ -z "${CUSTOM_CRT_URL}" ] ; then echo "No custom cert needed"; else \
       curl -sS -o /etc/pki/ca-trust/source/anchors/customcert.crt $CUSTOM_CRT_URL \
       && update-ca-trust \
       && keytool -import -alias custom -file /etc/pki/ca-trust/source/anchors/customcert.crt -cacerts -storepass changeit -noprompt \
    ; fi \
    && yum install -y wget \
    && chsh -s /bin/bash jboss \
    && /server-setup.sh /docker-server.env \
    && rm -rf /opt/jboss/wildfly/standalone/configuration/standalone_xml_history
ENTRYPOINT ["/docker-entrypoint.sh"]
ENV ORACLE_DRIVER_PATH=$ORACLE_DRIVER_PATH
USER ${RUN_USER}