FROM registry.access.redhat.com/ubi8/ubi-minimal:8.0

# Builds a composite docker service that the "owner" needs to run. Specifically it contains the following services:
#   Intel SDO development/test rendezvous service
#   Intel SDO to0scheduler service
#   Intel SDO OPS (Owner Protocol Service)
#   Intel SDO OCS (Owner Companion Service)
#   Open-horizon ocs-api (OCS REST API)

# Building a UBI image:
#   https://access.redhat.com/articles/4238681
#   https://playbook.cloudpaklab.ibm.com/ubi-faq/#Q_Can_I_addenable_additional_package_repositories_for_UBI_images

# docker build requirements:
#   The build must be done in the top dir of the SDO-support git repo
#   Untar the SDO distribution tar file to sdo_sdk_binaries_linux_x64 in the top dir (can not be a sym link)

# docker run requirements (see run-sdo-owner-services.sh):
#   Mount a named docker volume at WORKDIR/ocs/config/db
#   Pass in the env vars required by start-sdo-owner-services.sh
#   Expose the ports in the EXPOSE ports below

# Image size reduction todos (0.9.3 is 1.03GB):
# Following https://docs.docker.com/develop/dev-best-practices/ and others, e.g. https://www.ardanlabs.com/blog/2020/02/docker-images-part1-reducing-image-size.html
# (done) reduce layers by combining steps (originally 36 steps, now 20)
# (done) use microdnf --nodocs as much as possible (0.9.5 712 MB)
# (waiting on intel response) install jre instead of jdk
# (waiting on intel info) run all sdo services in same tomcat instance

# WORKDIR: the working dir for the 2nd half of this file, and what all of the services will run from, SDO_OCS_DB_PATH: the ocs service read this. OCS_API_PORT and VERBOSE can be overridden on docker run.
ENV WORKDIR=/home/sdouser
ENV SDO_OCS_DB_PATH=$WORKDIR/ocs/config/db   OCS_API_PORT=9008   VERBOSE=true

# Working during during the installations
WORKDIR /root

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

# Install openjdk-11. The tar.gz file is 193 MB, unpacked is 297 MB
#RUN curl -sS -o openjdk-11_linux-x64_bin.tar.gz https://download.java.net/java/ga/jdk11/openjdk-11_linux-x64_bin.tar.gz && \
#    sha256sum openjdk-11_linux-x64_bin.tar.gz && \
#    tar xzvf openjdk-11_linux-x64_bin.tar.gz && \
#    rm openjdk-11_linux-x64_bin.tar.gz && \
#    mkdir /usr/lib/jvm && \
#    mv jdk-11 /usr/lib/jvm/openjdk-11-manual-installation/ && \
#    update-alternatives --install /usr/bin/java java /usr/lib/jvm/openjdk-11-manual-installation/bin/java 1 && \
#    update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/openjdk-11-manual-installation/bin/javac 1

# Install openjdk-11-jre. The tar.gz file is 43 MB, unpacked is 124 MB
# Note: with SDO 1.7, it is necessary to use java 11.0.4 or earlier, because there is an issue with the SDO bouncycastle version and 11.0.5 and above
RUN curl -sS -o openjre-11_linux-x64_bin.tar.gz https://cdn.azul.com/zulu/bin/zulu11.33.15-ca-jre11.0.4-linux_x64.tar.gz && \
    sha256sum openjre-11_linux-x64_bin.tar.gz && \
    tar xzvf openjre-11_linux-x64_bin.tar.gz && \
    rm openjre-11_linux-x64_bin.tar.gz && \
    mkdir -p /usr/lib/jvm && \
    mv zulu11.*-linux_x64 /usr/lib/jvm/openjre-11-manual-installation && \
    update-alternatives --install /usr/bin/java java /usr/lib/jvm/openjre-11-manual-installation/bin/java 1

# this doesn't work here, because docker writes /etc/hosts when it starts the container
#RUN echo "127.0.0.1 RVSDO OwnerSDO" >> /etc/hosts

USER sdouser
WORKDIR $WORKDIR

# Get the license file
COPY LICENSE.txt /licenses/

# Get rendezvous files. The rv subdir will be created automatically by COPY
# Note: need to use uid and gid to be able to build on non-linux hosts
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/demo/rendezvous/application.properties  sdo_sdk_binaries_linux_x64/demo/rendezvous/logback-spring.xml  sdo_sdk_binaries_linux_x64/demo/rendezvous/rendezvous  sdo_sdk_binaries_linux_x64/cri/rendezvous-1.7.0.war  $WORKDIR/rv/

# Get to0scheduler files
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/SDOIotPlatformSDK/to0scheduler $WORKDIR/to0scheduler/

# Get OCS files
# Note: we don't want the contents of ocs/config/db, that is excluded in the .dockerignore file
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/SDOIotPlatformSDK/ocs $WORKDIR/ocs/
# This is only the default owner private key. It will be moved into ocs/config/db/v1/creds by start-sdo-owner-servic es.sh if they don't specify their own key in run-sdo-owner-services.sh
COPY --chown=1000:1000 keys/sample-owner-keystore.p12 $WORKDIR/ocs/config/sample-owner-keystore.p12

# This sed is for dev/test/demo and makes the to0scheduler respond to changes more quickly, and let us use the same voucher over again
# SDO_OCS_DB_PATH is where the named volume will get mounted to. Create the subdirs, and make sure we own everything
RUN sed -i -e 's/^to0.scheduler.interval=.*$/to0.scheduler.interval=5/' -e 's/^to2.credential-reuse.enabled=.*$/to2.credential-reuse.enabled=true/' $WORKDIR/ocs/config/application.properties
RUN mkdir -p $SDO_OCS_DB_PATH/v1/{creds,devices,values} && chown -R 1000:1000 $SDO_OCS_DB_PATH

# Get OPS files
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/SDOIotPlatformSDK/ops $WORKDIR/ops/

# Get our ocs-api binary and startup script
COPY --chown=1000:1000 ocs-api/linux/ocs-api docker/start-sdo-owner-services.sh $WORKDIR/

# Note: these don't actually expose the port, they just serve as documentation about the -p flags docker run should use
# RV: 8040, to0scheduler: 8049, OPS: 8042, Our ocs-api: 9008
# Note: the OCS traffic is all internal to this container, so don't need to expose 9009
EXPOSE 8040  8049  8042  9008

# Pass db path and ocs-api port in as env vars, so they can be set via docker run if desired
CMD $WORKDIR/start-sdo-owner-services.sh
#CMD ["bash"]
