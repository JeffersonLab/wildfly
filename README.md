# wildfly [![Docker (demo)](https://img.shields.io/docker/v/jeffersonlab/wildfly?sort=semver&label=DockerHub)](https://hub.docker.com/r/jeffersonlab/wildfly)
Configurable [Wildfly](https://www.wildfly.org/) base Docker image 

## Overview
This Jefferson Lab Wildfly template assumes apps are authenticated with [Keycloak](https://www.keycloak.org/) and use an Oracle database.  Optionally an SMTP mail server can be configured.   The full EE Wildfly distribution is used as a starting point and a few libraries are added including:

 - JLog: JLab logbook client
 - Keycloak admin client
 - Apache POI (Excel doc API)
 - Tuckey URL rewrite

## Configure
Wildfly must be pre-configured before the first deployment of an app.  The bash scripts located in the `scripts` directory are used with the following environment variables:

Create a `.env` file for your environment and call the bash scripts [server-setup.sh](https://github.com/JeffersonLab/wildfly/blob/main/scripts/server-setup.sh) (example: [docker config](https://github.com/JeffersonLab/wildfly/blob/main/config/docker-server.env)) and [app-setup.sh](https://github.com/JeffersonLab/wildfly/blob/main/scripts/app-setup.sh) (example: [demo docker config](https://github.com/JeffersonLab/smoothness/blob/main/docker/demo/smoothness-demo-setup.env)) to do the initial Wildfly configuration.   Bash can be executed on Linux, Windows (WSL2), and Mac with some perseverance.  See [bash setup scripts](https://github.com/JeffersonLab/wildfly/tree/main/scripts).

**Note**: If you are using Windows and WSL2 you may need to run dos2unix on .env and .sh files

### Server Setup 
Only needs to be executed once per permanent installation of Wildfly.

| Name                | Description                                                  |
|---------------------|--------------------------------------------------------------|
| EMAIL_FROM          | Default from address for the mail/jlab resource              |
| EMAIL_HOST          | Host for the mail/jlab resource                              |
| EMAIL_PORT          | Port for the mail/jlab resource                              |
| ORACLE_DRIVER_PATH  | Path to ORACLE Driver (see Dockerfile-weblib for docker env) |
| WILDFLY_HOME        | Path to Wildfly home dir                                     | 
| WILDFLY_PASS        | Admin password (if empty no admin user is created)           |
| WILDFLY_USER        | Admin username (if empty no admin user is created)           |


### App Setup 
Must be executed once per app installed in Wildfly.

| Name                | Description                                                              |
|---------------------|--------------------------------------------------------------------------|
| KEYCLOAK_REALM      | Keycloak realm to configure                                              |
| KEYCLOAK_RESOURCE   | Keycloak resource to configure                                           |
| KEYCLOAK_SECRET     | Keycloak Secret                                                          |
| KEYCLOAK_SERVER_URL | Scheme, host name, and port of Keycloak authentication server            |
| KEYCLOAK_WAR        | Name of war file to secure with Keycloak (app key)                       |
| ORACLE_DATASOURCE   | Name of Oracle datasource (app key)                                      |
| ORACLE_SERVER       | Host name and port of Oracle server to use to connect to DB from Wildfly |
| ORACLE_SERVICE      | Oracle Service name to use to connect to DB from Wildfly                 |
| ORACLE_USER         | Username to use to connect to DB from Wildfly                            |
| ORACLE_PASS         | Password to use to connect to DB from Wildfly                            |
| WILDFLY_HOME        | Path to Wildfly home dir                                                 | 

**Note**: As an alternative to the bash scripts The docker image configures Wildfly for use in the compose environment and that's a good starting point to copy from.  Outside of a compose environment you may need to tweak the standalone.xml configuration to use different host names and ports (For example Oracle and Keycloak host names would need to be updated to localhost:1521 and localhost:8081 respectively when using the deps.yml and running Wildfly outside the compose network):

```
docker compose up
docker exec -it demo /opt/jboss/wildfly/bin/jboss-cli.sh --connect -c "undeploy smoothness-demo.war"
docker exec -it demo /opt/jboss/wildfly/bin/jboss-cli.sh --connect -c shutdown
docker cp demo:/opt/jboss/wildfly .
```
### Docker Runtime

These environment variables are Docker specific and are used by the [docker-entrypoint.sh](https://github.com/JeffersonLab/wildfly/blob/main/scripts/docker-entrypoint.sh) script to wait on the Oracle database to start.

| Name                | Description                                                                                     |
|---------------------|-------------------------------------------------------------------------------------------------|
| ORACLE_DATASOURCE   | Oracle Datasource name to use to connect to DB from TestOracleConnection utility                |
| ORACLE_SERVER       | Host name and port of Oracle server to use to connect to DB from TestOracleConnection utility   |
| ORACLE_USER         | Username to use to connect to DB from TestOracleConnection utility                              |
| ORACLE_PASS         | Password to use to connect to DB from TestOracleConnection utility                              |
| ORACLE_SERVICE      | Oracle Service name to use to connect to DB from TestOracleConnection utility                   |           

