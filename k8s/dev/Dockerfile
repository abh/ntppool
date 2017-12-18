FROM quay.io/ntppool/base-os:v3.2.1
USER root
VOLUME /ntppool
VOLUME /ntppool/data
WORKDIR /ntppool

RUN mkdir /var/ntppool && chown ntppool data /var/ntppool

ENTRYPOINT ["./docker/entrypoint"]
