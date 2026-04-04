# Using Ubuntu 20.04 (modernized from 16.04)
FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

ARG CLM_FQDN
ARG CLM_PORT

ARG ORACLE_FQDN
ARG ORACLE_PORT
ARG ORACLE_USER
ARG ORACLE_PASSWORD
ARG ORACLE_PDB

ARG LDAP_FQDN
ARG LDAP_PORT
ARG LDAP_BASE_DN
ARG LDAP_BIND_DN
ARG LDAP_BIND_PASSWORD
ARG JAS_ADMIN_USER
ARG JAS_ADMIN_PASSWORD
ARG JAS_HTTP_PORT
ARG JAS_HTTPS_PORT

ARG JAZZ_USER
ARG JAZZ_ADMIN_PASSWORD

ARG JAZZ_DISTRO_URL
ARG JAZZ_JAS_URL
ARG JAZZ_IFIX_URL
ARG DM_DISTRO_URL
ARG IBMWEBINSTALLER_DISTRO_URL

# Validate passwords early — before any heavy downloads
COPY validate-passwords.sh /tmp/
RUN chmod +x /tmp/validate-passwords.sh && /tmp/validate-passwords.sh "${JAZZ_ADMIN_PASSWORD}" "${ORACLE_PASSWORD}"

RUN dpkg --add-architecture i386 && apt-get update

RUN apt-get -y install rpm binutils libaio1 libx32stdc++6 \
libpam0g:i386 libnuma1 file vim rsyslog software-properties-common wget unzip openssl rsync sudo less openssh-server sshpass \
python3 python3-pip ldap-utils

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

RUN sed -i 's/create_xconsole$/# create_xconsole/g' /etc/init.d/rsyslog
RUN touch /var/log/syslog && chmod a+r /var/log/syslog
RUN service rsyslog start

# get pyratemp so we can do some Template-file replacements ... easily
# and wait-for-it to manage race conditions
RUN python -m pip install pyratemp pyyaml wait-for-it oracledb

# Create user ID for Jazz Administration
RUN useradd -U -G sudo -d /home/${JAZZ_USER} -m -s /bin/bash -p $(openssl passwd -1 "${JAZZ_ADMIN_PASSWORD}") ${JAZZ_USER}
RUN echo "${JAZZ_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set security and pam limits for the jazz_admin user
COPY jazz_limits.conf /etc/security/limits.d/

# provide the URL to retrieve CLM
RUN mkdir /opt/jazz-medium

RUN echo "#!/bin/bash" > /opt/jazz-medium/fetch_bundles.sh
RUN chmod a+x /opt/jazz-medium/fetch_bundles.sh
RUN echo "wget --show-progress --progress=bar:force -q -O /opt/jazz-medium/clm.zip ${JAZZ_DISTRO_URL}" >> /opt/jazz-medium/fetch_bundles.sh
ADD ${JAZZ_DISTRO_URL} /opt/jazz-medium/clm.zip

# retrieve the Jazz Authentication Server bundle
RUN echo "wget --show-progress --progress=bar:force -q -O /opt/jazz-medium/jas.zip ${JAZZ_JAS_URL}" >> /opt/jazz-medium/fetch_bundles.sh
ADD ${JAZZ_JAS_URL} /opt/jazz-medium/jas.zip

# retrieve ELM iFix (applied after base install via IBM Installation Manager)
ADD ${JAZZ_IFIX_URL} /opt/jazz-medium/ifix.zip

# retrieve Oracle JDBC driver directly from Maven Central
RUN wget -q -O /opt/jazz-medium/ojdbc8.jar https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/19.3.0.0/ojdbc8-19.3.0.0.jar

# retrieve IBM's "web installer"
RUN echo "wget --show-progress --progress=bar:force -q -O /opt/jazz-medium/installer.zip ${IBMWEBINSTALLER_DISTRO_URL}" >> /opt/jazz-medium/fetch_bundles.sh
ADD ${IBMWEBINSTALLER_DISTRO_URL} /opt/jazz-medium/installer.zip

# provide the XML config that will point to the repo just composed from downloads
RUN mkdir -p /opt/jazz-medium/templates
ADD templates/silent-install-server2.xml.pt /opt/jazz-medium/templates
ADD templates/silent-install-jas2.xml.pt /opt/jazz-medium/templates

# provide the parameters.properties file that provides additional setup responses
ADD templates/parameters.properties.pt /opt/jazz-medium/templates

# provide the Jazz Authorization Server config files
ADD templates/appConfig.xml.pt /opt/jazz-medium/templates
ADD templates/ldapUserRegistry.xml.pt /opt/jazz-medium/templates

# provide the systemd template to automate running of JTS after install
ADD templates/systemd_jts.pt /opt/jazz-medium/templates


# provide the jazz silent installation and tweak script (which will be called on entry)
ADD getItBuildItRunIt.sh /opt/jazz-medium
RUN chmod a+x /opt/jazz-medium/getItBuildItRunIt.sh

RUN echo "JAZZ_USER=${JAZZ_USER}" > /opt/jazz-medium/env
RUN echo "JAZZ_ADMIN_PASSWORD=${JAZZ_ADMIN_PASSWORD}" >> /opt/jazz-medium/env
RUN echo "ORACLE_USER=${ORACLE_USER}" >> /opt/jazz-medium/env
RUN echo "ORACLE_PASSWORD=${ORACLE_PASSWORD}" >> /opt/jazz-medium/env
RUN echo "ORACLE_FQDN=${ORACLE_FQDN}" >> /opt/jazz-medium/env
RUN echo "ORACLE_PORT=${ORACLE_PORT}" >> /opt/jazz-medium/env
RUN echo "ORACLE_PDB=${ORACLE_PDB}" >> /opt/jazz-medium/env
RUN echo "CLM_FQDN=${CLM_FQDN}" >> /opt/jazz-medium/env
RUN echo "CLM_PORT=${CLM_PORT}" >> /opt/jazz-medium/env
RUN echo "LDAP_FQDN=${LDAP_FQDN}" >> /opt/jazz-medium/env
RUN echo "LDAP_PORT=${LDAP_PORT}" >> /opt/jazz-medium/env
RUN echo "LDAP_BASE_DN=${LDAP_BASE_DN}" >> /opt/jazz-medium/env
RUN echo "LDAP_BIND_DN=${LDAP_BIND_DN}" >> /opt/jazz-medium/env
RUN echo "LDAP_BIND_PASSWORD=${LDAP_BIND_PASSWORD}" >> /opt/jazz-medium/env
RUN echo "JAS_ADMIN_USER=${JAS_ADMIN_USER}" >> /opt/jazz-medium/env
RUN echo "JAS_ADMIN_PASSWORD=${JAS_ADMIN_PASSWORD}" >> /opt/jazz-medium/env
RUN echo "JAS_HTTPS_PORT=${JAS_HTTPS_PORT}" >> /opt/jazz-medium/env
RUN echo "JAS_HTTP_PORT=${JAS_HTTP_PORT}" >> /opt/jazz-medium/env

ENTRYPOINT []
