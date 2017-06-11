FROM quay.io/ntppool/base-os:v2.1

ENV HULK /usr/bin/hulk
USER ntppool
ADD . /ntppool

USER root
ENV CBCONFIG=

RUN perl Makefile.PL && \
  make templates && \
  CBCONFIG=docker/combust.build.conf bin/setup && \
  mkdir -p tmp logs && \
  chown -R ntppool tmp logs

USER ntppool

WORKDIR /ntppool
EXPOSE 8299

CMD ./docker-run
