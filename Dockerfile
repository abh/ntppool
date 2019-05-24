FROM quay.io/ntppool/base-os:v3.9.1

USER root

RUN apk --no-cache upgrade

ENV CBCONFIG=
ENV HULK /usr/bin/hulk

WORKDIR /ntppool
VOLUME /ntppool/data

ADD . /ntppool

RUN mkdir /var/ntppool && chown ntppool data /var/ntppool
RUN rm -fr docs/ntppool/_syndicate && \
    mkdir -p data/syndicate && \
    ln -s /ntppool/data/syndicate docs/ntppool/_syndicate && \
    chown ntppool data/syndicate

#RUN ls -al docs/ntppool; mkdir docs/ntppool/_syndicate; chown ntppool docs/ntppool/_syndicate

# because quay.io sets timestamps to 1980 for some reason ...
RUN find ./docs -type f -print0 | xargs -0 touch

RUN perl Makefile.PL && \
  make templates && \
  CBCONFIG=docker/combust.build.conf bin/setup && \
  mkdir -p tmp logs && \
  chown -R ntppool tmp logs

RUN bash -c "ls -la docs/shared/static{,/.g,/css}"

EXPOSE 8299
ENTRYPOINT ["./docker/entrypoint"]
CMD ["./docker-run"]

USER ntppool
