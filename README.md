# wildfly [![CI](https://github.com/JeffersonLab/wildfly/actions/workflows/ci.yml/badge.svg)](https://github.com/JeffersonLab/wildfly/actions/workflows/ci.yml) [![Docker (demo)](https://img.shields.io/docker/v/jeffersonlab/wildfly?sort=semver&label=DockerHub)](https://hub.docker.com/r/jeffersonlab/wildfly)
Configurable [Wildfly](https://www.wildfly.org/) base Docker image and bash setup scripts.

---
 - [Overview](https://github.com/JeffersonLab/wildfly#overview)
 - [Configure](https://github.com/JeffersonLab/wildfly#configure)
 - [Release](https://github.com/JeffersonLab/wildfly#release)
---

## Overview
This Jefferson Lab Wildfly template assumes apps are authenticated with [Keycloak](https://www.keycloak.org/) and use an Oracle or MariaDB database.  It is generally expected that only one database will be configured at a time.  Optionally an SMTP mail server can be configured.   The full EE Wildfly distribution is used as a starting point and a few libraries are added including:

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

| Name               | Description                                                                                          |
|--------------------|------------------------------------------------------------------------------------------------------|
| ACCESS_LOG         | If defined, enable access logging                                                                    |
| ADD_JBOSS_MODULES  | JBoss Modules to install, if any                                                                     |
| APPLY_ELTRON_PATCH | If defined, apply [patch](https://github.com/slominskir/wildfly-elytron/releases/tag/v1.19.1.Patch1) |
| EMAIL_FROM         | Default from address for the mail/jlab resource                                                      |
| EMAIL_HOST         | Host for the mail/jlab resource                                                                      |
| EMAIL_PORT         | Port for the mail/jlab resource                                                                      |
| GZIP               | If defined, enable gzip                                                                              |
| KEYSTORE_NAME      | If defined, set TLS keystore name (file must be inside configuration dir and of type PKS12)          |
| KEYSTORE_PASS      | Keystore password                                                                                    |
| ORACLE_DRIVER_URL  | Path to ORACLE Driver for Wildfly to use                                                             |
| MARIADB_DRIVER_URL | Path to MariaDB Driver for Wildfly to use                                                            |
| WILDFLY_HOME       | Path to Wildfly home dir                                                                             | 
| WILDFLY_PASS       | Admin password (if empty no admin user is created)                                                   |
| WILDFLY_RUN_USER   | User for running Wildfly                                                                             | 
| WILDFLY_USER       | Admin username (if empty no admin user is created)                                                   |

**Note**: There is a self-signed test certificate installed, but you can override with your own cert by mounting a custom PKS12 keystore file to `/opt/jboss/wildfly/standalone/configuration/server.p12`  

### App Setup 
Must be executed once per app installed in Wildfly.

| Name                | Description                                                              | Runtime Overridable |
|---------------------|--------------------------------------------------------------------------|---------------------|
| KEYCLOAK_REALM      | Keycloak realm to configure                                              | YES                 |           
| KEYCLOAK_RESOURCE   | Keycloak resource to configure                                           | YES                 |
| KEYCLOAK_SECRET     | Keycloak Secret                                                          | YES                 |
| KEYCLOAK_SERVER_URL | Scheme, host name, and port of Keycloak authentication server            | YES                 |
| KEYCLOAK_WAR        | Name of war file to secure with Keycloak (app key)                       | NO                  |
| ORACLE_DATASOURCE   | Name of Oracle datasource (app key)                                      | NO                  |
| ORACLE_SERVER       | Host name and port of Oracle server to use to connect to DB from Wildfly | NO                  |
| ORACLE_SERVICE      | Oracle Service name to use to connect to DB from Wildfly                 | NO                  |
| ORACLE_USER         | Username to use to connect to DB from Wildfly                            | NO                  |
| ORACLE_PASS         | Password to use to connect to DB from Wildfly                            | NO                  |
| MARIADB_DATASOURCE  | Name of MariaDB datasource (app key)                                     | NO                  |
| MARIADB_SERVER      | Host name and port of MariaDB server used to connect to DB from Wildfly  | NO                  |
| MARIADB_DB_NAME     | Name of MariaDB database name to use to connect from Wildfly             | NO                  |
| MARIADB_USER        | Username to use to connect to DB from Wildfly                            | NO                  |
| MARIADB_PASS        | Password to use to connect to DB from Wildfly                            | NO                  |
| WILDFLY_HOME        | Path to Wildfly home dir                                                 | NO                  |
| WILDFLY_RUN_USER    | User for running Wildfly                                                 | NO                  |

**Note**: Runtime Overridable parameters only make sense for Wildfly instances used for a single app (such as in a Container).  Providing runtime overrides to a multi-app configuration would overrwrite all app configs of the same name.  See https://github.com/JeffersonLab/wildfly/blob/86df35a1357b5ad863ecc53be94676bf96ef8489/scripts/app-setup.sh#L69

**Note**: As an alternative to the bash scripts The docker image configures Wildfly for use in the compose environment and that's a good starting point to copy from.  Outside of a compose environment you may need to tweak the standalone.xml configuration to use different host names and ports (For example Oracle and Keycloak host names would need to be updated to localhost:1521 and localhost:8081 respectively when using the deps.yml and running Wildfly outside the compose network):

```
docker compose up
docker exec -it demo /opt/jboss/wildfly/bin/jboss-cli.sh --connect -c "undeploy smoothness-demo.war"
docker exec -it demo /opt/jboss/wildfly/bin/jboss-cli.sh --connect -c shutdown
docker cp demo:/opt/jboss/wildfly .
```
### Docker Runtime

These environment variables are Docker specific and are used by the [docker-entrypoint.sh](https://github.com/JeffersonLab/wildfly/blob/main/scripts/docker-entrypoint.sh) script to wait on the Oracle database to start.

| Name               | Description                                                                                   |
|--------------------|-----------------------------------------------------------------------------------------------|
| ORACLE_DATASOURCE  | Oracle Datasource name to use to connect to DB from TestOracleConnection utility              |
| ORACLE_SERVER      | Host name and port of Oracle server to use to connect to DB from TestOracleConnection utility |
| ORACLE_USER        | Username to use to connect to DB from TestOracleConnection utility                            |
| ORACLE_PASS        | Password to use to connect to DB from TestOracleConnection utility                            |
| ORACLE_SERVICE     | Oracle Service name to use to connect to DB from TestOracleConnection utility                 |           
| MARIADB_DATASOURCE | MariaDB datasource name to use to connect to DB from TestMariaDBConnection utility            |
| MARIADB_SERVER     | Host name and port of MariaDB server used to connect to DB from TestMariaDBConnection utility |
| MARIADB_USER       | Username to use to connect to DB from TestMariaDBConnection utility                           |
| MARIADB_PASS       | Password to use to connect to DB from TestMariaDBConnection utility                           |
| MARIADB_DB_NANE    | MariaDB Service name to use to connect to DB from TestMariaDBConnection utility               |           

**Note**: The entrypoint script waits for either an Oracle or a MariaDB database to start but not both.  Oracle takes precedence.

## Release
1. Create a new release on the GitHub Releases page.  The release should enumerate changes and link issues.
2. Build and publish a new Docker image [from the GitHub tag](https://gist.github.com/slominskir/a7da801e8259f5974c978f9c3091d52c#8-build-an-image-based-of-github-tag). GitHub is configured to do this automatically on git push of semver tag (typically part of GitHub release) or the [Publish to DockerHub](https://github.com/JeffersonLab/wildfly/actions/workflows/docker-publish.yml) action can be manually triggered after selecting a tag.
