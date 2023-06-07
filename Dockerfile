ARG BUILD_IMAGE=gradle:7.4-jdk17
ARG RUN_IMAGE=quay.io/wildfly/wildfly:26.1.3.Final-jdk17
ARG ORACLE_DRIVER_PATH=/ojdbc11-21.7.0.0.jar
ARG CUSTOM_CRT_URL="https://ace.jlab.org/acc-ca.crt http://pki.jlab.org/JLabCA.crt"

################## Stage 0
FROM ${BUILD_IMAGE} as builder
ARG CUSTOM_CRT_URL
USER root
WORKDIR /
COPY . /app
RUN /app/scripts/update-certs-builder.sh ${CUSTOM_CRT_URL}

## Let's minimize layers in final-product by organizing files into a single copy structure
RUN mkdir /unicopy \
    && cp /app/config/docker-server.env /unicopy \
    && cp /app/scripts/TestOracleConnection.java /unicopy \
    && cp /app/scripts/docker-entrypoint.sh /unicopy \
    && cp /app/scripts/server-setup.sh /unicopy \
    && cp /app/scripts/provided-setup.sh /unicopy \
    && cp /app/scripts/app-setup.sh /unicopy \
    && cp /app/scripts/update-certs-runner.sh /unicopy

################## Stage 1
FROM ${RUN_IMAGE} as runner
ARG CUSTOM_CRT_URL
ARG RUN_USER=jboss:jboss
ARG ORACLE_DRIVER_PATH
USER root
COPY --from=builder /unicopy /
RUN /update-certs-runner.sh ${CUSTOM_CRT_URL} \
    && chsh -s /bin/bash jboss \
    && /server-setup.sh /docker-server.env \
    && rm -rf /opt/jboss/wildfly/standalone/configuration/standalone_xml_history
ENTRYPOINT ["/docker-entrypoint.sh"]
ENV ORACLE_DRIVER_PATH=$ORACLE_DRIVER_PATH
USER ${RUN_USER}