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

# docker run requirements:
#   Mount the ocs db (ocs/config/db) at WORKDIR/ocs-db
#   Pass in the env vars required by start-sdo-owner-services.sh
#   Expose the ports in the EXPOSE ports below

# This is the working dir for the 2nd half of this file, and what all of the services will run from
ENV WORKDIR=/home/sdouser
# Note: the ocs service needs this to be here
ENV SDO_OCS_DB_PATH=$WORKDIR/ocs/config/db
# These can be overridden on the docker run cmd with: -e "<var>=<value>"
ENV OCS_API_PORT=9008
ENV VERBOSE=true

# This is temporary, will be changed further down in this file
WORKDIR /root

# The haveged rpm (needed by RV) is in EPEL, so add that repo: https://fedoraproject.org/wiki/EPEL
# Note: supposedly we could get this from the RHEL repo, if we go thru the right paperwork: https://developers.redhat.com/blog/2020/02/26/red-hat-simplifies-container-dev-and-redistribution-rhel-packages/
RUN curl -sS -o epel-release-latest-8.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    rpm -i /root/epel-release-latest-8.noarch.rpm

# To search for rpms (or for what rpms provides a command): http://www.rpm-find.net/linux/RPM/
# Note: libssl-dev is is required by all the sdo services on ubuntu. I think the equivalent rpm is openssl-devel
# Note: due to a bug in microdnf, using the --nodocs option causes an exit code of 141: https://github.com/rpm-software-management/microdnf/issues/50
RUN microdnf update -y && microdnf install -y openssl ca-certificates tar findutils shadow-utils procps openssl-devel haveged && microdnf clean all

# Install openjdk-11
RUN curl -sS -o openjdk-11_linux-x64_bin.tar.gz https://download.java.net/java/ga/jdk11/openjdk-11_linux-x64_bin.tar.gz && \
    sha256sum openjdk-11_linux-x64_bin.tar.gz && \
    tar xzvf openjdk-11_linux-x64_bin.tar.gz && \
    rm openjdk-11_linux-x64_bin.tar.gz
RUN mkdir /usr/lib/jvm && \
    mv jdk-11 /usr/lib/jvm/openjdk-11-manual-installation/ && \
    update-alternatives --install /usr/bin/java java /usr/lib/jvm/openjdk-11-manual-installation/bin/java 1 && \
    update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/openjdk-11-manual-installation/bin/javac 1

# this doesn't work here, because docker writes /etc/hosts when it starts the container
#RUN echo "127.0.0.1 RVSDO OwnerSDO" >> /etc/hosts

RUN groupadd -g 1000 sdouser && adduser -u 1000 -g sdouser sdouser
USER sdouser
WORKDIR $WORKDIR

# Get the license file
COPY LICENSE.txt /licenses/

# Get rendezvous files. The rv subdir will be created automatically by COPY
# Note: need to use uid and gid to be able to build on non-linux hosts
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/demo/rendezvous/application.properties $WORKDIR/rv/
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/demo/rendezvous/logback-spring.xml $WORKDIR/rv/
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/demo/rendezvous/rendezvous $WORKDIR/rv/
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/cri/rendezvous-1.7.0.war $WORKDIR/rv/

# Get to0scheduler files
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/SDOIotPlatformSDK/to0scheduler $WORKDIR/to0scheduler/
# Moved to start-sdo-owner-services.sh so the value can be passed in at run time. So to0scheduler will point RV (and by extension, the device) to the correct OPS host.
#RUN sed -i -e 's/^com.intel.sdo.to0.ownersign.to1d.bo.dns1=.*$/com.intel.sdo.to0.ownersign.to1d.bo.dns1=OwnerSDO/' $WORKDIR/to0scheduler/config/application.properties

# Get OCS files
# Note: we don't want the contents of $WORKDIR/ocs/config/db. We will remove it below
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/SDOIotPlatformSDK/ocs $WORKDIR/ocs/
# This is only the default owner private key. It will be moved into ocs/config/db/v1/creds by start-sdo-owner-servic es.sh if they don't specify their own key in run-sdo-owner-services.sh
COPY --chown=1000:1000 keys/sample-owner-keystore.p12 $WORKDIR/ocs/config/sample-owner-keystore.p12
# This mod for dev/test/demo makes the to0scheduler respond to changes more quickly, and let us use the same voucher over again
RUN sed -i -e 's/^to0.scheduler.interval=.*$/to0.scheduler.interval=5/' -e 's/^to2.credential-reuse.enabled=.*$/to2.credential-reuse.enabled=true/' $WORKDIR/ocs/config/application.properties
# This is where the named volume will get mounted to. Clean it from the copy above, create the subdirs, and make sure we own everything
RUN rm -rf $SDO_OCS_DB_PATH/v1 && mkdir -p $SDO_OCS_DB_PATH/v1/{creds,devices,values} && chown -R 1000:1000 $SDO_OCS_DB_PATH

# Get OPS files
COPY --chown=1000:1000 sdo_sdk_binaries_linux_x64/SDOIotPlatformSDK/ops $WORKDIR/ops/

# Get our ocs-api binary and startup script
COPY --chown=1000:1000 ocs-api/linux/ocs-api docker/start-sdo-owner-services.sh $WORKDIR/

# Note: these don't actually expose the port, they just serve as documentation about the -p flags docker run should use
# RV
EXPOSE 8040
# to0scheduler
EXPOSE 8049
# OCS - the traffic to this is all internal to this container, so don't need to expose
#EXPOSE 9009
# OPS
EXPOSE 8042
# Our ocs-api
EXPOSE 9008

# Pass db path and ocs-api port in as env vars, so they can be set via docker run if desired
CMD $WORKDIR/start-sdo-owner-services.sh
#CMD ["bash"]
