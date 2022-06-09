ARG PARENT_IMAGE=docker.io/centos:7

#checkov:skip=CKV_DOCKER_7:Base image is not a "latest" tag
FROM $PARENT_IMAGE as builder
COPY APIGateway_Install.run /opt/APIGateway_Install.run
COPY scripts/runInstall.sh /opt/runInstall.sh
RUN chmod u+x /opt/runInstall.sh
RUN /opt/runInstall.sh /opt/APIGateway_Install.run
RUN find /opt/Axway -type d -print0 | xargs -0 chmod g=u
RUN find /opt/Axway/apigateway/ \( -type d -name bin -print0 \) -o \( -type f -name \*.sh -print0 \) -o \( -type f -name \*.py -print0 \) | xargs -0 chmod g=u
RUN chmod g=u /opt/Axway/apigateway/Linux.x86_64/bin/*
RUN chmod g=u /opt/Axway/apigateway/samples/scripts/* /opt/Axway/apigateway/posix/samples/etc/init.d/*

FROM $PARENT_IMAGE
LABEL maintainer="support@axway.com"
RUN chmod a+rx /opt
ARG USER_UID=1000
ARG USER_GID=1000
RUN getent group "$USER_GID" || groupadd -g "$USER_GID" emt
RUN adduser emtuser -l -u "$USER_UID" -g "$USER_GID" -c "EMT User"
COPY --chown=emtuser:0 --from=builder /opt/Axway /opt/Axway

#checkov:skip=CKV_DOCKER_2:This is meant to run in Kubernetes, no HEALTHCHECK defined
#checkov:skip=CKV_DOCKER_3:This is a base image, no user are created
