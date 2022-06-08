FROM registry.access.redhat.com/ubi8/ubi-minimal:8.0

# Builds a composite docker service that the "owner" needs to run. Specifically it contains the following services:
#   Intel FDO development/test rendezvous service
#   Intel FDO Manufacturer service
#   Intel FDO Owner services

# Building a UBI image:
#   https://access.redhat.com/articles/4238681
#   https://playbook.cloudpaklab.ibm.com/ubi-faq/#Q_Can_I_addenable_additional_package_repositories_for_UBI_images

# docker build requirements:
#   Follow the Developer's section of the top-level README.md to download the necessary FDO tar files and build this docker image

# docker run requirements (see run-sdo-owner-services.sh):
#   Pass in the env vars required by start-sdo-owner-services.sh
#   Expose the ports in the EXPOSE ports below

# Image size reduction todos (0.9.3 is 1.03GB):
# Following https://docs.docker.com/develop/dev-best-practices/ and others, e.g. https://www.ardanlabs.com/blog/2020/02/docker-images-part1-reducing-image-size.html
# (future) run all sdo services in same tomcat instance

# Note: if ENV variables are used in this Dockerfile, they can not effectively be overridden by docker run
# WORKDIR: the working dir for the 2nd half of this file, and what all of the services will run from, SDO_OCS_DB_PATH: the ocs service read this. SDO_OCS_API_PORT and VERBOSE can be overridden on docker run.
ENV WORKDIR=/home/fdouser
ENV FDO_OWNER_SERVICES_DB=$WORKDIR/owner/app_data/
# These env vars are only used at runtime (by start-sdo-owner-services.sh), so can be overridden by docker run
ENV FDO_RV_PORT=8040   FDO_OWNER_PORT=8042     FDO_MANUFACT_PORT=8039    VERBOSE=true 
# Owner database port may be replacing OCS API Port = 8051. Not exposed
ENV FDO_OWNER_EXTERNAL_PORT=$FDO_OWNER_PORT

# Working during during the installations
WORKDIR /root

# Ubuntu 20.04 / RHEL 8.4.
# Maven 3.6.3.
# Java 11.
# Haveged.
# Docker engine (minimum version 18.09, Supported till version 20.10.7) / Podman engine (For RHEL)
# Docker-compose (minimum version 1.21.2) / Podman-compose (For RHEL)

# The haveged rpm (needed by RV) is in EPEL, so add that repo: https://fedoraproject.org/wiki/EPEL
# To see the available EPEL pkgs: http://mirror.nodesdirect.com/epel/8/Everything/x86_64/Packages/
# Note: supposedly we could get this from the RHEL repo, if we go thru the right paperwork: https://developers.redhat.com/blog/2020/02/26/red-hat-simplifies-container-dev-and-redistribution-rhel-packages/
# To search for rpms (or for what rpms provides a command): http://www.rpm-find.net/linux/RPM/
# Note: libssl-dev is is required by all the sdo services on ubuntu. I think the equivalent rpm is openssl-devel
# Note: due to a bug in microdnf, using the --nodocs option causes an exit code of 141: https://github.com/rpm-software-management/microdnf/issues/50
RUN curl -sS -o epel-release-latest-8.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    rpm -i /root/epel-release-latest-8.noarch.rpm && \
    microdnf update -y && \
    microdnf install --nodocs -y openssl ca-certificates tar findutils shadow-utils procps openssl-devel haveged && \
    microdnf clean all && \
    groupadd -g 1000 sdouser && adduser -u 1000 -g sdouser sdouser

# Install openjdk-11-jre. The tar.gz file is 43 MB, unpacked is 124 MB
# Note: with SDO 1.7, it is necessary to use java 11.0.4 or earlier, because there is an issue with the SDO bouncycastle version and 11.0.5 and above
#RUN curl -sS -o openjre-11_linux-x64_bin.tar.gz https://cdn.azul.com/zulu/bin/zulu11.33.15-ca-jre11.0.4-linux_x64.tar.gz && \
#RUN curl -sS -o openjre-11_linux-x64_bin.tar.gz https://cdn.azul.com/zulu/bin/zulu11.43.55-ca-jre11.0.9.1-linux_x64.tar.gz && \
#    mv zulu11.*-linux_x64 /usr/lib/jvm/openjre-11-manual-installation && \
RUN curl -sSL -o openjre-11_linux-x64_bin.tar.gz https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.10%2B9/OpenJDK11U-jre_x64_linux_hotspot_11.0.10_9.tar.gz && \
    sha256sum openjre-11_linux-x64_bin.tar.gz && \
    tar xzf openjre-11_linux-x64_bin.tar.gz && \
    rm openjre-11_linux-x64_bin.tar.gz && \
    mkdir -p /usr/lib/jvm && \
    mv jdk-11.0.10+9-jre /usr/lib/jvm/openjre-11-manual-installation && \
    update-alternatives --install /usr/bin/java java /usr/lib/jvm/openjre-11-manual-installation/bin/java 1 

# this doesn't work here, because docker writes /etc/hosts when it starts the container
#RUN echo "127.0.0.1 RVSDO OwnerSDO" >> /etc/hosts

USER sdouser
WORKDIR $WORKDIR

# Get the license file
COPY LICENSE.txt /licenses/
COPY fdo/NOTICES-v1.1.0/pri-fidoiot/* /licenses/FDOIotPlatformSDK/

# Get rendezvous files. The rv subdir will be created automatically by COPY
# Note: need to use uid and gid to be able to build on non-linux hosts
COPY --chown=1000:1000 fdo/pri-fidoiot-v1.1.0/rv/* $WORKDIR/rv/

# Get Owner services files
COPY --chown=1000:1000 fdo/pri-fidoiot-v1.1.0/owner/* $WORKDIR/owner/

# Get Manufacturer service files
COPY --chown=1000:1000 fdo/pri-fidoiot-v1.1.0/manufacturer/* $WORKDIR/manufacturer/

# Get FDO Scripts
COPY --chown=1000:1000 fdo/pri-fidoiot-v1.1.0/scripts/* $WORKDIR/scripts/

# Get AIO
COPY --chown=1000:1000 fdo/pri-fidoiot-v1.1.0/aio/* $WORKDIR/aio/

# Get Reseller
COPY --chown=1000:1000 fdo/pri-fidoiot-v1.1.0/reseller/* $WORKDIR/reseller/


# # This is only the default owner private key. It will be moved into ocs/config/db/v1/creds by start-sdo-owner-servic es.sh if they don't specify their own key in run-sdo-owner-services.sh
# COPY --chown=1000:1000 keys/sample-owner-keystore.p12 $WORKDIR/ocs/config/sample-owner-keystore.p12
# #This command gives `USER sdouser` the correct permissions for mounting this key inside the container
# RUN touch ocs/config/owner-keystore.p12 && chown sdouser:sdouser ocs/config/owner-keystore.p12
# # SDO_OCS_DB_PATH is where the named volume will get mounted to. Create the subdirs, and make sure we own everything
# RUN mkdir -p $SDO_OCS_DB_PATH/v1/{creds,devices,values} ocs-api-dir/keys && chown -R 1000:1000 $SDO_OCS_DB_PATH ocs-api-dir

# Get our ocs-api binary, startup script, agent-install-wrapper.sh, and keystore scripts
COPY --chown=1000:1000 docker/start-fdo.sh $WORKDIR/

# Note: the EXPOSE stmt doesn't actually expose the port, it just serves as documentation about the -p flags docker run should use. We may override these values, so just let docker run set them.
#EXPOSE 8040  8042  8051
# RV: 8040, OPS: 8042, 8051
# Note: the OCS and to0scheduler traffic is all internal to this container, so don't need to expose 9009 and 8049, respectively

# Pass db path and ocs-api port in as env vars, so they can be set via docker run if desired
CMD $WORKDIR/start-fdo.sh
#CMD ["bash"]
