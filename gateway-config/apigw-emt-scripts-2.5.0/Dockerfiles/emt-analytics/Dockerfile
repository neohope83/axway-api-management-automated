ARG PARENT_IMAGE=apigw-base:nocache
#checkov:skip=CKV_DOCKER_7:Base image is built skipping the cache
FROM $PARENT_IMAGE as builder

ARG DOCKER_IMAGE_ID
ARG ANALYTICS_PORT
ARG ANALYTICS_USERNAME
ARG METRICS_DB_URL
ARG METRICS_DB_USERNAME
ARG REPORTS_DIR
ARG EMAIL_REPORTS
ARG EMAIL_TO
ARG EMAIL_FROM
ARG SMTP_CONN_TYPE
ARG SMTP_HOST
ARG SMTP_PORT
ARG SMTP_USERNAME
ARG CLEANUP_REPORT
ARG USER_UID
ARG USER_GID

COPY APIGateway_Install.run /opt/APIGateway_Install.run
COPY scripts/runInstall.sh /opt/runInstall.sh
RUN chmod u+x /opt/runInstall.sh && umask 002 && opt/runInstall.sh /opt/APIGateway_Install.run

COPY opt/emt_resources /tmp/emt
COPY scripts/* /opt/Axway/analytics/posix/bin/


RUN yum install -y libXext && \
    yum install -y libXrender && \
    yum install -y xorg-x11-fonts-Type1 && \
    yum install -y xorg-x11-fonts-75dpi

RUN cp /tmp/emt/lic.lic /opt/Axway/analytics/conf/licenses && \
    cd /opt/Axway/analytics/posix/bin && \
    umask 002 && \
    ./setup-emt-analytics \
        --props /tmp/emt/config.props \
        --fed /tmp/emt/fed.fed \
        --merge-dir /tmp/emt/analytics \
        --docker-image-id "$DOCKER_IMAGE_ID" \
        --analytics-port "$ANALYTICS_PORT" \
        --analytics-username "$ANALYTICS_USERNAME" \
        --metrics-db-url "$METRICS_DB_URL" \
        --metrics-db-username "$METRICS_DB_USERNAME" \
        --reports-dir "$REPORTS_DIR" \
        --email-reports "$EMAIL_REPORTS" \
        --email-to "$EMAIL_TO" \
        --email-from "$EMAIL_FROM" \
        --smtp-conn-type "$SMTP_CONN_TYPE" \
        --smtp-host "$SMTP_HOST" \
        --smtp-port "$SMTP_PORT" \
        --smtp-username "$SMTP_USERNAME" \
        --cleanup-report "$CLEANUP_REPORT"
RUN mkdir -p /opt/Axway/analytics/conf/tmp
RUN chmod g=u /opt/Axway/analytics /opt/Axway/analytics/* /opt/Axway/analytics/conf/* /opt/Axway/analytics/conf/fed/* /opt/Axway/analytics/conf/emc/analytics
RUN find /opt/Axway/analytics/ \( -type d -name bin -print0 \) -o \( -type d -name scripts -print0 \) -o \( -type d -name init.d -print0 \) -o \( -type f -name \*.sh -print0 \) -o \( -type f -name \*.py -print0 \) | xargs -0 chmod g=u -R
RUN chmod g=u /opt/Axway/analytics/system/lib/jython

RUN rm -rf /tmp/emt


FROM $PARENT_IMAGE
LABEL maintainer="support@axway.com"

ARG USER_UID
ARG USER_GID

RUN chmod a+rx /opt && getent group "$USER_GID" || groupadd -g "$USER_GID" emt && adduser emtuser -l -u "$USER_UID" -g "$USER_GID" -c "EMT User"
COPY --chown=emtuser:0 --from=builder /opt/Axway /opt/Axway

USER emtuser:emt
CMD ["/opt/Axway/analytics/posix/bin/start-emt-analytics"]
#checkov:skip=CKV_DOCKER_2:This is meant to run in Kubernetes, no HEALTHCHECK defined
