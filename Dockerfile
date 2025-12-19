###########################################################################################################
#
# How to build:
#
# docker build -t arkcase/alfresco-ce-content:7.3.1 .
#
# How to run: (Docker)
# docker compose -f docker-compose.yml up -d
#
#
###########################################################################################################

ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG ARCH="amd64"
ARG OS="linux"
ARG VER="7.3.1"
ARG JAVA="11"
ARG PKG="alfresco-content"
ARG APP_USER="alfresco"
ARG APP_UID="33000"
ARG APP_GROUP="${APP_USER}"
ARG APP_GID="1000"

ARG MARIADB_DRIVER="3.1.2"
ARG MARIADB_DRIVER_SRC="org.mariadb.jdbc:mariadb-java-client:${MARIADB_DRIVER}"
ARG MSSQL_DRIVER="9.2.1.jre11"
ARG MSSQL_DRIVER_SRC="com.microsoft.sqlserver:mssql-jdbc:${MSSQL_DRIVER}"
ARG MYSQL_DRIVER="8.0.27"
ARG MYSQL_DRIVER_SRC="mysql:mysql-connector-java:${MYSQL_DRIVER}"
ARG ORACLE_DRIVER="19.11.0.0"
ARG ORACLE_DRIVER_SRC="com.oracle.database.jdbc:ojdbc8:${ORACLE_DRIVER}"
ARG POSTGRES_DRIVER="42.3.2"
ARG POSTGRES_DRIVER_SRC="org.postgresql:postgresql:${POSTGRES_DRIVER}"
ARG ALFRESCO_PASSWORD_RESET="1.0.1"
ARG ALFRESCO_PASSWORD_RESET_SRC="com.armedia:alfresco-password-reset:${ALFRESCO_PASSWORD_RESET}:jar"

ARG ALFRESCO_EDITION="community"
ARG ALFRESCO_REPO="docker.io/alfresco/alfresco-content-repository-community"
ARG ALFRESCO_IMG="${ALFRESCO_REPO}:${VER}"

ARG ARKCASE_MVN_REPO="https://nexus.armedia.com/repository/arkcase/"

ARG BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG BASE_REPO="arkcase/base-java"
ARG BASE_VER="22.04"
ARG BASE_VER_PFX=""
ARG BASE_IMG="${BASE_REGISTRY}/${BASE_REPO}:${BASE_VER_PFX}${BASE_VER}"

ARG BASE_TOMCAT_REGISTRY="${BASE_REGISTRY}"
ARG BASE_TOMCAT_REPO="arkcase/base-tomcat"
ARG BASE_TOMCAT_VER="9"
ARG BASE_TOMCAT_IMG="${BASE_TOMCAT_REGISTRY}/${BASE_TOMCAT_REPO}:${BASE_VER_PFX}${BASE_TOMCAT_VER}"

ARG RM_REPO="arkcase/alfresco-ce-rm"
ARG RM_VER="${VER}"
ARG RM_IMG="${PUBLIC_REGISTRY}/${RM_REPO}:${RM_VER}"

# Used to copy artifacts
FROM "${ALFRESCO_IMG}" AS alfresco-src

ARG RM_IMG

FROM "${RM_IMG}" AS rm-src

ARG BASE_TOMCAT_IMG

FROM "${BASE_TOMCAT_IMG}" AS tomcat-src

# Final Image
ARG BASE_IMG

FROM "${BASE_IMG}"

ARG ARCH
ARG OS
ARG VER
ARG JAVA
ARG PKG
ARG APP_USER
ARG APP_UID
ARG APP_GROUP
ARG APP_GID
ARG MARIADB_DRIVER_SRC
ARG MSSQL_DRIVER_SRC
ARG MYSQL_DRIVER_SRC
ARG ORACLE_DRIVER_SRC
ARG POSTGRES_DRIVER_SRC
ARG ALFRESCO_EDITION
ARG ALFRESCO_PASSWORD_RESET_SRC
ARG ARKCASE_MVN_REPO

LABEL ORG="ArkCase LLC" \
      MAINTAINER="Armedia Devops Team <devops@armedia.com>" \
      APP="Alfresco Content Server" \
      VERSION="${VER}"

ENV JAVA_MAJOR="${JAVA}"
ENV CATALINA_HOME="/usr/local/tomcat"
ENV TOMCAT_NATIVE_LIBDIR="${CATALINA_HOME}/native-jni-lib"
ENV LD_LIBRARY_PATH="${TOMCAT_NATIVE_LIBDIR}"
ENV PATH="${CATALINA_HOME}/bin:${PATH}"
ENV HOME_DIR="/home/alfresco"

RUN set-java "${JAVA}" && \
    apt-get -y install \
        fontconfig \
        fonts-dejavu \
        language-pack-en \
        libapr1 \
        libfreetype6 \
        libpng-tools \
        python3 \
        python3-bcrypt \
      && \
    apt-get clean && \
    mkdir -p "${CATALINA_HOME}" && \
    mkdir -p "${TOMCAT_NATIVE_LIBDIR}" && \
    groupadd -g "${APP_GID}" "${APP_GROUP}" && \
    useradd -u "${APP_UID}" -g "${APP_GROUP}" -G "${ACM_GROUP}" -d "${HOME_DIR}" -m "${APP_USER}"

WORKDIR "${CATALINA_HOME}"
ARG RM_AMP="/alfresco-governance-services-${ALFRESCO_EDITION}-repo.amp"
COPY --from=alfresco-src --chown="${APP_USER}:${APP_GROUP}" "${CATALINA_HOME}" "${CATALINA_HOME}"
COPY --from=alfresco-src --chown="${APP_USER}:${APP_GROUP}" /licenses /licenses
COPY --from=tomcat-src --chown="${APP_USER}:${APP_GROUP}" --chmod="0755" "/app/tomcat/lib/native/${JAVA_MAJOR}" "${TOMCAT_NATIVE_LIBDIR}.new"
COPY --from=rm-src /alfresco-governance-services-${ALFRESCO_EDITION}-repo-*.amp "${RM_AMP}"

COPY --chown=root:root --chmod=0755 entrypoint /
COPY --chown=root:root --chmod=0755 md4 bcrypt10 sha256 /usr/local/bin

RUN rm -rf "${TOMCAT_NATIVE_LIBDIR}" && \
    mv -vf "${TOMCAT_NATIVE_LIBDIR}.new" "${TOMCAT_NATIVE_LIBDIR}" && \
    chown "${APP_USER}:${APP_GROUP}" "${CATALINA_HOME}"

USER "${APP_USER}"
ENV TOMCAT_DIR="${CATALINA_HOME}" \
    LIB_DIR="${CATALINA_HOME}/webapps/alfresco/WEB-INF/lib"

RUN mvn-get "${MARIADB_DRIVER_SRC}" "${LIB_DIR}" && \
    mvn-get "${MSSQL_DRIVER_SRC}" "${LIB_DIR}" && \
    mvn-get "${MYSQL_DRIVER_SRC}" "${LIB_DIR}" && \
    mvn-get "${ORACLE_DRIVER_SRC}" "${LIB_DIR}" && \
    mvn-get "${POSTGRES_DRIVER_SRC}" "${LIB_DIR}"
COPY --chown="${APP_USER}:${APP_GROUP}" "server.xml" "${TOMCAT_DIR}/conf/server.xml"

ENV RM_AMP="${RM_AMP}"
RUN java -jar "${TOMCAT_DIR}/alfresco-mmt"/alfresco-mmt*.jar \
        install "${RM_AMP}" \
        "${TOMCAT_DIR}/webapps/alfresco" -nobackup && \
    java -jar "${TOMCAT_DIR}/alfresco-mmt"/alfresco-mmt*.jar list  "${TOMCAT_DIR}/webapps/alfresco" && \
    ( catalina.sh configtest 2>&1 | grep -q 'Loaded Apache Tomcat Native library' )

ARG ALFRESCO_PASSWORD_RESET_TGT="${TOMCAT_DIR}/alfresco-password-reset.jar"
RUN mvn-get "${ALFRESCO_PASSWORD_RESET_SRC}" "${ARKCASE_MVN_REPO}" "${ALFRESCO_PASSWORD_RESET_TGT}"

RUN mkdir -p "${HOME_DIR}/.postgresql" && ln -svf "${CA_TRUSTS_PEM}" "${HOME_DIR}/.postgresql/root.crt"

EXPOSE 8000 8080 10001
VOLUME [ "/usr/local/tomcat/alf_data" ]
ENTRYPOINT [ "/entrypoint" ]
