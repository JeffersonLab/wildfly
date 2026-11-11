# wildfly [![CI](https://github.com/JeffersonLab/wildfly/actions/workflows/ci.yaml/badge.svg)](https://github.com/JeffersonLab/wildfly/actions/workflows/ci.yaml) [![Docker (demo)](https://img.shields.io/docker/v/jeffersonlab/wildfly?sort=semver&label=DockerHub)](https://hub.docker.com/r/jeffersonlab/wildfly)
Configurable [Wildfly](https://www.wildfly.org/) base Docker image and bash setup scripts.

---
 - [Overview](https://github.com/JeffersonLab/wildfly#overview)
 - [Configure](https://github.com/JeffersonLab/wildfly#configure)
 - [Release](https://github.com/JeffersonLab/wildfly#release)
---

## Overview
This Jefferson Lab Wildfly template for Wildfly 37.0.1 assumes apps are authenticated with [Keycloak](https://www.keycloak.org/) and use an Oracle or MariaDB database.  It is generally expected that only one database will be configured at a time.  Optionally an SMTP mail server can be configured.   The full EE Wildfly distribution is used as a starting point and a few libraries are added including:

 - JLog: JLab logbook client
 - Keycloak admin client
 - Apache POI (Excel doc API)
 - Tuckey URL rewrite

## Configure
Wildfly must be configured before the first deployment of an app. [scripts/wildfly-lib.sh](https://github.com/JeffersonLab/wildfly/blob/main/scripts/wildfly-lib.sh) is a library of bash functions that install and configure Wildfly; the image has it at `/wildfly-lib.sh`. Run it with an env file of bash variables and the functions to call, in order. It stops at the first function that fails:

```bash
/wildfly-lib.sh -e /app-setup.env wildfly_start_and_wait config_keycloak_client config_oracle_client \
  config_email wildfly_reload wildfly_stop
```

Or source it and call the functions from your own script:

```bash
. /wildfly-lib.sh
WILDFLY_APP_HOME=/opt/wildfly/current
wildfly_start_and_wait && config_gzip && wildfly_reload && wildfly_stop
```

Each function checks the variables it needs and fails, naming any that are missing. Nothing runs unless you name it: call only the functions your server and app need. `/wildfly-lib.sh --help` lists the functions and their variables. Example env files: the image's [server config](https://github.com/JeffersonLab/wildfly/blob/main/config/docker-server.env) and [install config](https://github.com/JeffersonLab/wildfly/blob/main/config/docker-host.env), and an [app config](https://github.com/JeffersonLab/smoothness/blob/main/container/app/app-setup.env). Bash can be executed on Linux, Windows (WSL2), and Mac with some perseverance.

**Note**: If you are using Windows and WSL2 you may need to run `dos2unix` on .env and .sh files

### Install
For a new Wildfly on a host or in an image. On RHEL 9, as root:

```bash
wildfly-lib.sh -e host.env install_java create_user_and_group download_wildfly unzip_wildfly \
  create_wildfly_symlinks adjust_jvm_options create_systemd_service create_log_file_cleanup_cron
```

| Function                     | Variables                                                                              | Description                                                                         |
|------------------------------|----------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| install_java                 |                                                                                        | Install Java 21 with yum, remove Java 11 and 17                                     |
| create_user_and_group        | WILDFLY_GROUP, WILDFLY_GROUP_ID, WILDFLY_USER, WILDFLY_USER_HOME, WILDFLY_USER_ID      | Create the OS user and group that run Wildfly                                       |
| download_wildfly             | WILDFLY_VERSION                                                                        | Download the release zip to /tmp                                                    |
| unzip_wildfly                | WILDFLY_USER, WILDFLY_USER_HOME, WILDFLY_VERSION, *WILDFLY_GROUP*                      | Unzip it to WILDFLY_USER_HOME/WILDFLY_VERSION, owned by WILDFLY_USER                |
| create_wildfly_symlinks      | WILDFLY_USER_HOME, WILDFLY_VERSION                                                     | Link `current` to the release, and `configuration` and `log` to its standalone dirs |
| adjust_jvm_options           | JDK_HOME, JDK_MAX_HEAP, JDK_MIN_HEAP, WILDFLY_USER_HOME, WILDFLY_VERSION               | Set JAVA_HOME and heap sizes in standalone.conf                                     |
| create_systemd_service       | WILDFLY_BIND_ADDRESS, WILDFLY_HTTPS_PORT, WILDFLY_USER, WILDFLY_USER_HOME              | Create and enable the wildfly service, which reads `configuration/run.env`          |
| create_log_file_cleanup_cron | WILDFLY_USER, WILDFLY_USER_HOME                                                        | Delete logs older than 30 days daily                                                |

### Server Setup
Only needs to be executed once per permanent installation of Wildfly. All but `apply_elytron_patch` need Wildfly running: call `wildfly_start_and_wait` first, and `wildfly_reload` or `wildfly_stop` last. Every function here needs WILDFLY_APP_HOME, the path to Wildfly's home dir (`/opt/wildfly/current` in the image), so the table leaves it out. Optional variables are in italics.

| Function                            | Variables                                         | Description                                                                                                                                 |
|-------------------------------------|---------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| wildfly_start_and_wait              | *WILDFLY_RUN_USER*                                | Start Wildfly, as WILDFLY_RUN_USER if that isn't the current user, and wait until it answers on port 8080                                   |
| wildfly_reload                      |                                                   | Reload Wildfly's configuration                                                                                                              |
| wildfly_stop                        |                                                   | Shut Wildfly down                                                                                                                           |
| apply_elytron_patch                 |                                                   | Replace Elytron 2.6.4's OIDC client with a [patched one](https://github.com/slominskir/wildfly-elytron/releases/tag/v2.6.4.Patch1), checked against its SHA-256, so logging in keeps URL parameters with encoded characters ([dtm#73](https://github.com/JeffersonLab/dtm/issues/73)). Only for Wildfly 37.0.1; skipped if its Elytron jar isn't there. The container image applies it |
| allow_elytron_url_params            |                                                   | Keep the query parameters of the page that started an OIDC login                                                                            |
| config_access_log                   |                                                   | Enable access logging                                                                                                                       |
| config_admin_user                   | WILDFLY_ADMIN_USER, WILDFLY_ADMIN_PASS            | Add a management (admin console) user with this name and password                                                                           |
| config_email                        | EMAIL_FROM, EMAIL_HOST, EMAIL_PORT                | Add the `java:/mail/jlab` mail session: default from address, and SMTP host and port                                                        |
| config_gzip                         |                                                   | Enable gzip                                                                                                                                 |
| config_log_levels                   | LOG_LEVELS                                        | Set logger levels, one `category=LEVEL` per line, such as `org.apache.kafka.clients=ERROR`: adds each logger, or changes its level if it exists |
| config_mariadb_driver               | MARIADB_DRIVER_PATH, MARIADB_DRIVER_URL           | Download the MariaDB driver from the URL to the path and add it                                                                             |
| config_oracle_driver                | ORACLE_DRIVER_PATH, ORACLE_DRIVER_URL             | Download the Oracle driver from the URL to the path and add it                                                                              |
| config_param_limits                 | MAX_PARAM_COUNT                                   | Set the most request parameters the listeners accept                                                                                        |
| config_persist_sessions_on_redeploy |                                                   | Keep HTTP sessions when an app is redeployed                                                                                                |
| config_proxy                        |                                                   | Trust X-Forwarded-* headers on the HTTPS listener                                                                                           |
| config_samesite_cookie              | SAMESITE_COOKIE                                   | Set the SameSite attribute of every app's session cookie (JSESSIONID): Strict, Lax (recommended), or None                                   |
| config_ssl                          | KEYSTORE_NAME, KEYSTORE_PASS, *ENABLE_MANAGEMENT_HTTPS* | Serve HTTPS with this PKCS12 keystore in the configuration dir; if ENABLE_MANAGEMENT_HTTPS is set, the management interface too |
| add_jboss_modules                   | ADD_JBOSS_MODULES                                 | Download jars and add them as JBoss modules, one per line: `scope\|name\|jar URLs\|dependencies`, with scope `global` or `local`            |
| enable_global_modules               | GLOBAL_ENABLE_LIBS                                | Make modules Wildfly already has global, one name per line                                                                                  |

**Note**: The image serves a self-signed `localhost` demo certificate, [config/localhost-demo.crt](https://github.com/JeffersonLab/wildfly/blob/main/config/localhost-demo.crt), from its keystore `server.p12`. Its private key, [config/localhost-demo.key](https://github.com/JeffersonLab/wildfly/blob/main/config/localhost-demo.key), is public: the pair is for local development and tests only and must never be used on a real host. Every build serves the same certificate, so integration tests can pin it and developers can trust it in their browser once (SHA-256 fingerprint `41:01:9E:C4:7F:4F:6B:80:21:E6:49:49:11:0B:39:3F:9E:4E:65:BE:C2:C2:6E:DA:26:91:76:94:6E:11:19:31`). To serve your own certificate, mount a custom PKCS12 keystore file to `/opt/wildfly/current/standalone/configuration/server.p12`. `pem_to_keystore` makes one from PEM files: it needs PEM_CERT_PATH, PEM_INTERMEDIATE_CERT_PATH, PEM_KEY_PATH, KEYSTORE_PASS, and KEYSTORE_OUTPUT_PATH.

### App Setup
Must be executed once per app installed in Wildfly, with Wildfly running. These also need WILDFLY_APP_HOME. Call one database's function, not both.

| Function                       | Variables                                                                                 |
|--------------------------------|-------------------------------------------------------------------------------------------|
| config_keycloak_client         | KEYCLOAK_REALM, KEYCLOAK_RESOURCE, KEYCLOAK_SECRET, KEYCLOAK_SERVER_URL, KEYCLOAK_WAR     |
| config_keycloak_client_dynamic | The same: environment variables of the same names, but KEYCLOAK_WAR, override them when Wildfly runs |
| config_oracle_client           | ORACLE_DATASOURCE, ORACLE_SERVER, ORACLE_SERVICE, ORACLE_USER, ORACLE_PASS                |
| config_oracle_client_dynamic   | The same: environment variables of the same names, but ORACLE_DATASOURCE, override them when Wildfly runs |
| config_mariadb_client          | MARIADB_DATASOURCE, MARIADB_SERVER, MARIADB_DB_NAME, MARIADB_USER, MARIADB_PASS           |

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
| MARIADB_DATASOURCE  | Name of MariaDB datasource (app key)                                     |
| MARIADB_SERVER      | Host name and port of MariaDB server used to connect to DB from Wildfly  |
| MARIADB_DB_NAME     | Name of MariaDB database name to use to connect from Wildfly             |
| MARIADB_USER        | Username to use to connect to DB from Wildfly                            |
| MARIADB_PASS        | Password to use to connect to DB from Wildfly                            |

**Note**: The `_dynamic` functions only make sense for Wildfly instances used for a single app (such as in a Container).  Providing runtime overrides to a multi-app configuration would overwrite all app configs of the same name.

**Note**: As an alternative to the bash scripts The docker image configures Wildfly for use in the compose environment and that's a good starting point to copy from.  Outside a compose environment you may need to tweak the standalone.xml configuration to use different host names and ports (For example Oracle and Keycloak host names would need to be updated to localhost:1521 and localhost:8081 respectively when using the deps.yaml and running Wildfly outside the compose network):

```
docker compose up
docker exec -it demo /opt/jboss/wildfly/bin/jboss-cli.sh --connect -c "undeploy smoothness-demo.war"
docker exec -it demo /opt/jboss/wildfly/bin/jboss-cli.sh --connect -c shutdown
docker cp demo:/opt/jboss/wildfly .
```

### Migrating from the setup scripts
Version 4 replaced the separate setup scripts with `wildfly-lib.sh`:

- `server-setup.sh ENV_FILE FUNCTION...` and `app-setup.sh ENV_FILE FUNCTION...` still work, but are deprecated; either one runs any function in the library. They no longer run a default list of functions when none is named: name each one, or call `wildfly-lib.sh` as above.
- A function now fails if a variable it needs is missing, where it used to skip silently. For example `config_email` without EMAIL_FROM, or `config_oracle_client` without ORACLE_DATASOURCE, now fails the build: drop the call if you don't need it. Functions no longer read variables that other functions need, so `server-setup.sh` no longer needs WILDFLY_RUN_USER for `config_email`, and `app-setup.sh` no longer needs the KEYCLOAK_* variables for `config_oracle_client`.
- The on/off variables are gone, since calling a function is what turns it on: APPLY_ELYTRON_PATCH, ACCESS_LOG, GZIP, PROXY, PERSISTENT_SESSIONS, WILDFLY_SKIP_START, WILDFLY_SKIP_RELOAD, and WILDFLY_SKIP_STOP.
- Removed scripts, and the functions that replace them: `rhel9-setup.sh` and `devcontainer-setup.sh`: the [Install](#install) functions, with `adjust_java`, `download`, `unzip_and_chmod`, and `create_symbolic_links` renamed `install_java`, `download_wildfly`, `unzip_wildfly`, and `create_wildfly_symlinks`. `provided-setup.sh`: `add_jboss_modules` (was `add_modules` and `config_provided`) and `enable_global_modules` (was `enable_globals`). `pem-to-java-keystore.sh`: `pem_to_keystore`.
- `config_admin_user` reads the admin console user's name and password from WILDFLY_ADMIN_USER and WILDFLY_ADMIN_PASS, not WILDFLY_USER and WILDFLY_PASS. WILDFLY_USER now only means the OS user that owns and runs Wildfly, in the [Install](#install) functions.
- `wildfly_start_and_wait` runs Wildfly as WILDFLY_RUN_USER only when that isn't the current user, so it also works when the build already runs as that user.
- `create_log_file_cleanup_cron` puts its script in WILDFLY_USER_HOME and runs it as WILDFLY_USER, not always in `/opt/wildfly` as `wildfly`.

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
1. Bump the version number in the VERSION file and commit and push to GitHub (using [Semantic Versioning](https://semver.org/)).
2. The [CD](https://github.com/JeffersonLab/wildfly/blob/main/.github/workflows/cd.yaml) GitHub Action should run automatically invoking:
    - The [Create release](https://github.com/JeffersonLab/container-workflows/blob/main/.github/workflows/gh-release.yaml) GitHub Action to tag the source and create release notes summarizing any pull requests.   Edit the release notes to add any missing details.
    - The [Publish docker image](https://github.com/JeffersonLab/container-workflows/blob/main/.github/workflows/docker-publish.yaml) GitHub Action to create a new demo Docker image.
