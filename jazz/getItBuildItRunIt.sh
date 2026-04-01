#!/bin/bash
[[ -z "$TERM" ]] && export TERM=linux
red=$(tput -T linux setaf 1)
green=$(tput -T linux setaf 2)

# read environment passed along from the Docker Compose Build phase
mediaPath=/opt/jazz-medium
templatePath="${mediaPath}/templates"
webInstallerDir=/opt/web_installer
unzippedClmPath=/opt/jazz-unzipped
installerPath="${webInstallerDir}/im/linux.gtk.x86_64"
jtsIbmJazzPath='IBM/JazzTeamServer'
jasIbmJazzPath='IBM/JazzAuthServer'
jtsPath="/opt/${jtsIbmJazzPath}"
jasPath="/opt/${jasIbmJazzPath}"
ibmPath=$(dirname ${jtsPath})

[[ ! -d ${unzippedClmPath} ]] && mkdir -p ${unzippedClmPath}
[[ ! -d ${installerPath} ]] && mkdir -p ${installerPath}
[[ ! -d ${jtsPath} ]] && mkdir -p ${jtsPath}

if [[ ! -r "${mediaPath}/env" ]]
then

    tput -T linux bold; echo "${red}Docker build failed to provide a readable ${mediaPath}/env file."; tput -T linux sgr0

    exit 66

fi

# shellcheck disable=SC1090
source "${mediaPath}/env"

jazzAdmin=${JAZZ_USER:-jazz_admin}
jazzAdminPassword=${JAZZ_ADMIN_PASSWORD:-jazz_admin}
oracleUser=${ORACLE_USER:-jazz_dba}
oraclePassword=${ORACLE_PASSWORD:-Ora19Jazz!}
oracleFqdn=${ORACLE_FQDN:-database.local}
oraclePort=${ORACLE_PORT:-1521}
oraclePdb=${ORACLE_PDB:-JAZZPDB}
clmFqdn=${CLM_FQDN:-localhost}
clmPort=${CLM_PORT:-9443}
clmScheme="https"
ldapFqdn=${LDAP_FQDN:-localhost}
ldapPort=${LDAP_PORT:-389}
ldapBaseDn=${LDAP_BASE_DN:-dc=example,dc=com}
jasHttpsPort=${JAS_HTTPS_PORT:-9643}
jasHttpPort=${JAS_HTTP_PORT:-9280}

jtsStagedPath="/home/${jazzAdmin}/${jtsIbmJazzPath}"
jasStagedPath="/home/${jazzAdmin}/${jasIbmJazzPath}"

# skip the installation and the setup if Jazz Admin thinks everything is set up
until [[ -f "/home/${jazzAdmin}/jazzIsSetup" ]]
do

tput -T linux bold; echo "${green}No Jazz Setup timestamp /home/${jazzAdmin}/jazzIsSetup file so setting up Jazz now..."; tput -T linux sgr0

# fetch the large bundles
tput -T linux bold; echo "${green}Fetching the Jazz Installation bundles..."; tput -T linux sgr0

# unzip the JTS bundle
tput -T linux bold; echo "${green}Unzipping the fetched Jazz Installation bundles..."; tput -T linux sgr0

unzip -o -q ${mediaPath}/clm.zip -d "${unzippedClmPath}"
chown -R "${jazzAdmin}":"${jazzAdmin}" "${unzippedClmPath}"

unzip -o -q ${mediaPath}/jas.zip -d "${unzippedClmPath}"
chown -R "${jazzAdmin}":"${jazzAdmin}" "${unzippedClmPath}"

# unzip the CLM Web Installer (zip already contains im/linux.gtk.x86_64/ structure)
unzip -o -q ${mediaPath}/installer.zip -d ${webInstallerDir}

# modify the XML config to point to the repo just composed from downloads
timestamp=$(date)

replacements=$(mktemp --tmpdir=${mediaPath} --suffix=.json)
cat <<-JSON > "${replacements}"
    {
      "timestamp": "${timestamp}",
      "unzippedAllDir": "${unzippedClmPath}",
      "unzippedImDir": "${installerPath}",
      "dmRepoDir": "${installerPath}/RhapsodyDM_Server/disk1"
    }
JSON
pyratemp_tool.py -f "${replacements}" "${templatePath}/silent-install-server2.xml.pt" > "/home/${jazzAdmin}/silent-install-server2.xml"
chown "${jazzAdmin}:${jazzAdmin}" "/home/${jazzAdmin}/silent-install-server2.xml"

pyratemp_tool.py -f "${replacements}" "${templatePath}/silent-install-jas2.xml.pt" > "/home/${jazzAdmin}/silent-install-jas2.xml"
chown "${jazzAdmin}:${jazzAdmin}" "/home/${jazzAdmin}/silent-install-jas2.xml"

# run IBM's silent installation as Jazz Admin
su - "${jazzAdmin}" <<-SCRIPT

    [[ -z "\$TERM" ]] && export TERM=linux

    cd "${installerPath}"

    tput -T linux bold; echo "${green}As ${jazzAdmin} in ${installerPath}, starting the Jazz userinstc Installation..."; tput -T linux sgr0

    ./userinstc -acceptLicense -input /home/${jazzAdmin}/silent-install-server2.xml --launcher.ini user-silent-install.ini > /home/${jazzAdmin}/installation.log 2>&1

    errorCount=\$(grep -i error ~/installation.log | wc -l)

    if [[ \$errorCount -ne 0 ]]
    then

        tput -T linux bold; echo "${red}Installation failed. Here are the last 50 lines of the failed installation."; tput -T linux sgr0

        tail -50 ~/installation.log

        exit 1

    fi

    tput -T linux bold; echo "${green}As ${jazzAdmin} in ${installerPath}, starting the Jazz Authentication Server userinstc Installation..."; tput -T linux sgr0

    ./userinstc -acceptLicense -input /home/${jazzAdmin}/silent-install-jas2.xml --launcher.ini user-silent-install.ini > /home/${jazzAdmin}/jas-installation.log 2>&1

    errorCount=\$(grep -i error ~/jas-installation.log | wc -l)

    if [[ \$errorCount -ne 0 ]]
    then

        tput -T linux bold; echo "${red}Installation of Jazz Authentication Server failed. Here are the last 50 lines of the failed installation."; tput -T linux sgr0

        tail -50 ~/jas-installation.log

        exit 1

    fi

    exit 0

SCRIPT

status=$?

if [[ $status -ne 0 ]]
then

    tput -T linux bold; echo "${red}Failed to silently install Jazz. Aborting"; tput -T linux sgr0

    exit $status

fi

# Verify the base install actually produced output
if [[ ! -d "/home/${jazzAdmin}/${jtsIbmJazzPath}" ]]
then

    tput -T linux bold; echo "${red}Base install did not produce /home/${jazzAdmin}/${jtsIbmJazzPath}. Dumping installation logs:"; tput -T linux sgr0
    echo "=== installation.log (last 80 lines) ==="
    tail -80 "/home/${jazzAdmin}/installation.log" 2>/dev/null
    echo "=== jas-installation.log (last 80 lines) ==="
    tail -80 "/home/${jazzAdmin}/jas-installation.log" 2>/dev/null

    exit 66

fi

# Apply iFix if present (as root for filesystem access, then as jazz_admin for IM)
if [[ -f ${mediaPath}/ifix.zip ]]
then

    tput -T linux bold; echo "${green}Applying ELM iFix..."; tput -T linux sgr0

    ifixDir=/opt/jazz-ifix
    mkdir -p ${ifixDir}
    unzip -o -q ${mediaPath}/ifix.zip -d ${ifixDir}
    chown -R "${jazzAdmin}":"${jazzAdmin}" ${ifixDir}

    su - "${jazzAdmin}" <<-IFIX_SCRIPT

        # Use the *installed* Installation Manager's imcl, not the web installer's userinstc
        installedImcl="/home/${jazzAdmin}/IBM/InstallationManager/eclipse/tools/imcl"

        if [[ ! -x "\${installedImcl}" ]]
        then
            tput -T linux bold; echo "${red}Installed imcl not found at \${installedImcl}. Skipping iFix."; tput -T linux sgr0
            exit 0
        fi

        tput -T linux bold; echo "${green}Applying iFix via installed IM at \${installedImcl}..."; tput -T linux sgr0

        \${installedImcl} updateAll -acceptLicense -repositories ${ifixDir} -installFixes recommended -log /home/${jazzAdmin}/ifix-installation.log 2>&1

        if [[ -f ~/ifix-installation.log ]]
        then
            errorCount=\$(grep -ic "^ERROR" ~/ifix-installation.log)

            if [[ \$errorCount -ne 0 ]]
            then
                tput -T linux bold; echo "${red}iFix installation had errors. Here are the last 50 lines:"; tput -T linux sgr0
                tail -50 ~/ifix-installation.log
            else
                tput -T linux bold; echo "${green}iFix applied successfully."; tput -T linux sgr0
            fi
        else
            tput -T linux bold; echo "${green}iFix completed (no log file produced — likely no updates needed)."; tput -T linux sgr0
        fi

IFIX_SCRIPT

fi

# now built, move the entire Jazz world to its runtime location
tput -T linux bold; echo "${green}Relocating the installed Jazz userinstc Installation..."; tput -T linux sgr0

rsync -a "${jtsStagedPath}" "${ibmPath}/"
rsync -a "${jasStagedPath}" "${ibmPath}/"
chown -R "${jazzAdmin}":"${jazzAdmin}" "${ibmPath}"

replacements=$(mktemp --tmpdir=${mediaPath} --suffix=.json)
cat <<-JSON > "${replacements}"
    {
        "timestamp": "${timestamp}",
        "jtsUserId": "${jazzAdmin}",
        "jtsUserPassword": "${jazzAdminPassword}",
        "jtsUserEmail": "${jazzAdmin}@digitalthread.us",
        "jtsUserName": "${jazzAdmin}",
        "jtsEmailAddress": "${jazzAdmin}@digitalthread.us",
        "jtsSmtpServer": "smtp.digitalthread.us",
        "jtsSmtpPassword": "${jazzAdmin}@digitalthread.us",
        "jtsPath": "${jtsPath}",
        "jtsUrlAndPort": "${clmScheme}\\\\://${clmFqdn}\\\\:${clmPort}",
        "oracleServerFqdn": "${oracleFqdn}",
        "oracleServerPort": "${oraclePort}",
        "oraclePdb": "${oraclePdb}",
        "oracleUserName": "${oracleUser}",
        "oraclePassword": "${oraclePassword}",
        "ldapFqdn": "${ldapFqdn}",
        "ldapPort": "${ldapPort}",
        "ldapBaseDn": "${ldapBaseDn}",
        "jasHttpsPort": "${jasHttpsPort}",
        "jasHttpPort": "${jasHttpPort}"
    }
JSON

# modify appConfig.xml for the Jazz Authentication Server
pyratemp_tool.py -f "${replacements}" "${templatePath}/parameters.properties.pt" > "/home/${jazzAdmin}/parameters.properties"
chown "${jazzAdmin}":"${jazzAdmin}" "/home/${jazzAdmin}/parameters.properties"

# modify the appConfig.xml for JAS to use Oracle instead of DB2
pyratemp_tool.py -f "${replacements}" "${templatePath}/appConfig.xml.pt" > "${jasPath}/wlp/usr/servers/jazzop/appConfig.xml"
chown "${jazzAdmin}:${jazzAdmin}" "${jasPath}/wlp/usr/servers/jazzop/appConfig.xml"

# disable IBM's HealthCenterMonitor that uses RMI due to NAT/localhost issues
if [[ ! -f ${jtsPath}/server/server.startup ]]
then

    tput -T linux bold; echo "${red}Failed to find ${jtsPath}/server/server.startup. Aborting"; tput -T linux sgr0

    exit 66

fi

    # insert line after
sed -i.bak1 '/export HEALTHCENTER_OPTS="-agentlib:healthcenter -Dcom.ibm.java.diagnostics.healthcenter.agent.port=1972"/a echo "HealthCenter intentionally Disabled due to RMI NAT issues."' "${jtsPath}/server/server.startup"

    # replace line
sed -i.bak2 's/export HEALTHCENTER_OPTS=.*/export HEALTHCENTER_OPTS=""/g' "${jtsPath}/server/server.startup"

# in order to provision Jazz, it will need the Oracle database and the proper HTTPS proxy network in place
LC_ALL=C.UTF-8 wait-for-it \
    --parallel \
    --service "${oracleFqdn}:${oraclePort}" \
    --service traefik:8080 \
    --timeout 600 \
    -- echo "${green}Oracle on ${oraclePort} and Traefik on 8080 are ready"

if [[ $? -ne 0 ]]
then

    tput -T linux bold; echo "${red}Failed to reach peer services. Aborting"; tput -T linux sgr0

    exit

fi

# Jazz will try to save content in /tmp
rm -fr /tmp/contentservice
[[ ! -d "/home/${jazzAdmin}/jts-contentservice" ]] && mkdir "/home/${jazzAdmin}/jts-contentservice"
ln -s "/home/${jazzAdmin}/jts-contentservice" /tmp/contentservice
chown -R "${jazzAdmin}:${jazzAdmin}" "/home/${jazzAdmin}/jts-contentservice"
chmod u+rwx "/home/${jazzAdmin}/jts-contentservice"

# OAuth token expiration during automated setup causes the servlet to error and abort itself
# set the token timeout to a day versus the minutes-long default.
echo "com.ibm.team.repository.oauth.accessToken.timeout=86400" >> "${jtsPath}/server/conf/jts/teamserver.properties"

# install Oracle JDBC driver for Jazz Authentication Server and CLM Liberty server
tput -T linux bold; echo "${green}Installing Oracle JDBC driver for Jazz Authentication Server..."; tput -T linux sgr0
cp ${mediaPath}/ojdbc8.jar "${jasPath}/wlp/usr/shared/config/lib/global/"
chown "${jazzAdmin}":"${jazzAdmin}" "${jasPath}/wlp/usr/shared/config/lib/global/ojdbc8.jar"

# Jazz expects the Oracle JDBC driver at exactly server/oracle/ojdbc8.jar
mkdir -p "${jtsPath}/server/oracle"
cp ${mediaPath}/ojdbc8.jar "${jtsPath}/server/oracle/"
chown "${jazzAdmin}":"${jazzAdmin}" "${jtsPath}/server/oracle/ojdbc8.jar"

su - "${jazzAdmin}" <<-SCRIPT

    cd "${jtsPath}/server"

    # try to start up Jazz and give it Time
    tput -T linux bold; echo "${green}As ${jazzAdmin} in ${jtsPath}/server, starting the repotools setup of the relocated Jazz Installation..."; tput -T linux sgr0

    # use Jazz's own JRE to try to post-config set it up
    export JAVA_HOME="${jtsPath}/server/jre"

    # the Jazz server needs to be running for the following setup
    ./server.startup

    status=\$?

    if [[ \$status -eq 0 ]]
    then

        # it can take a long long time to get up and stabilize
        sleep 45

        # tail the Liberty log in the background so there's visible progress
        libertyLog="${jtsPath}/server/liberty/servers/clm/logs/console.log"
        if [[ -f "\${libertyLog}" ]]; then
            tail -f "\${libertyLog}" 2>/dev/null | while IFS= read -r line; do
                echo "[Liberty] \${line}"
            done &
            tailPid=\$!
        fi

        # repotools limits its JVM to 1.5G by default but will often fail in that case
        echo "Starting repotools -setup (this typically takes 20-40 minutes)..."
        REPOTOOLS_MX_SIZE=8192 ./repotools-jts.sh -setup parametersFile=/home/${jazzAdmin}/parameters.properties adminUserId=ADMIN adminPassword=ADMIN

        # stop the log tailer
        [[ -n "\${tailPid}" ]] && kill "\${tailPid}" 2>/dev/null

        status=\$?

        [[ \$status -eq 0 ]] || exit \$status

        # leave a door open for administration!
        ./repotools-jts.sh -createUser adminUserId=ADMIN adminPassword=ADMIN userid=${jazzAdmin} jazzGroup=JazzAdmins

        # generate the JSA SSO Migration JSON file for each Jazz App
        declare -a apps=("jts" "ccm" "rm" "gc" "qm" "relm" "dcc")

        for app in "\${apps[@]}"
        do
            echo "Preparing \${app} for migration to Jazz Authentication Server Single-Sign-On..."
            ./repotools-\${app}.sh -prepareJsaSsoMigration adminUserId=ADMIN adminPassword=ADMIN repositoryURL=https://${clmFqdn}:${clmPort}/jts
        done

        status=\$?

        if [[ \$status -eq 0 ]]
        then

            tput -T linux bold; echo "${green}Successfully completed Jazz post-install Setup. Now shutting down the server before starting it in its configured role."; tput -T linux sgr0

            ./server.shutdown

            sleep 30

        fi

    fi

    exit \$status

SCRIPT

status=$?

if [[ $status -ne 0 ]]
then

    tput -T linux bold; echo "${red}Failed to configure deployed Jazz. Aborting"; tput -T linux sgr0

    exit $status

fi

# liberty/servers/clm/ files do not exist before the JTS setup, they are here now available

# switch the server configuration to use the LDAP server and the JAS server
pyratemp_tool.py -f "${replacements}" "${templatePath}/ldapUserRegistry.xml.pt" > "${jasPath}/wlp/usr/servers/jazzop/ldapUserRegistry.xml"
chown "${jazzAdmin}":"${jazzAdmin}" "${jasPath}/wlp/usr/servers/jazzop/ldapUserRegistry.xml"

# also enables SCIM in the JAS server
cp -f "${jasPath}/wlp/usr/servers/jazzop/ldapUserRegistry.xml" "${jtsPath}/server/liberty/servers/clm/conf"

sed -i.bak1 's/<!--include location="conf\/ldapUserRegistry.xml"\/-->/<include location="conf\/ldapUserRegistry.xml"\/>/g' "${jtsPath}/server/liberty/servers/clm/server.xml"
sed -i.bak2 's/<include location="conf\/basicUserRegistry.xml"\/>/<!--include location="conf\/basicUserRegistry.xml"\/-->/g' "${jtsPath}/server/liberty/servers/clm/server.xml"
chown "${jazzAdmin}":"${jazzAdmin}" "${jtsPath}/server/liberty/servers/clm/server.xml"

su - "${jazzAdmin}" <<-SCRIPT

    cd "${jasPath}"

    # try to start up Jazz Authentication Service
    tput -T linux bold; echo "${green}As ${jazzAdmin} in ${jasPath}, starting the Jazz Authentication Service..."; tput -T linux sgr0

    # correct a sh vs bash oops, by IBM, in their script
    sed -i.bak -e 's!/bin/sh!/bin/bash!g' start-jazz

    ./start-jazz

    cd "${jtsPath}/server"

    tput -T linux bold; echo "${green}As ${jazzAdmin} in ${jtsPath}/server, migrating the Jazz Services..."; tput -T linux sgr0

    # use Jazz's own JRE
    export JAVA_HOME="${jtsPath}/server/jre"

    # generate the JSA SSO Migration JSON file for each Jazz App
    declare -a apps=("jts" "ccm" "rm" "gc" "qm" "relm" "dcc")

    for app in "\${apps[@]}"
    do
        echo "Preparing \${app} for migration to Jazz Authentication Server Single-Sign-On..."
        ./repotools-\${app}.sh -migrateToJsaSso authServerUserId=${jazzAdmin} authServerPassword=${jazzAdminPassword} authServerURL=https://${clmFqdn}:${jasHttpsPort}/oidc/endpoint/jazzop
    done

SCRIPT

    # indicate successful setup and leave the until loop
    echo "${timestamp}" > "/home/${jazzAdmin}/jazzIsSetup"

done

su - "${jazzAdmin}" <<-SCRIPT

    cd "${jasPath}"

    # try to start up Jazz Authentication Service
    tput -T linux bold; echo "${green}As ${jazzAdmin} in ${jasPath}, starting the Jazz Authentication Service..."; tput -T linux sgr0

    ./start-jazz

    cd "${jtsPath}/server"

    # try to start up Jazz
    tput -T linux bold; echo "${green}As ${jazzAdmin} in ${jtsPath}/server, starting the Jazz Services..."; tput -T linux sgr0

    # use Jazz's own JRE
    export JAVA_HOME="${jtsPath}/server/jre"

    ./server.startup

SCRIPT

tput -T linux bold; echo "${green}Done. Leaving the Jazz Services running."; tput -T linux sgr0
