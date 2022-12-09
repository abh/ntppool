FROM harbor.ntppool.org/ntppool/base-os:3.17.0
USER root

RUN apk -U --no-cache upgrade --ignore alpine-baselayout

ENV CBCONFIG=
ENV HULK /usr/local/bin/hulk

WORKDIR /ntppool
VOLUME /ntppool/data

ADD . /ntppool

RUN mkdir /var/ntppool && chown ntppool data /var/ntppool
RUN rm -fr docs/ntppool/_syndicate && \
  mkdir -p data/syndicate && \
  ln -s /ntppool/data/syndicate docs/ntppool/_syndicate && \
  chown ntppool data/syndicate

# because quay.io sets timestamps to 1980 for some reason ...
RUN find ./docs -type f -print0 | xargs -0 touch

RUN perl Makefile.PL && \
  make templates && \
  CBCONFIG=docker/combust.build.conf bin/setup && \
  mkdir -p tmp logs && \
  chown -R ntppool tmp logs

#RUN bash -c "ls -la docs/shared/static{,/.g,/css}"

EXPOSE 8299
ENTRYPOINT ["./docker/entrypoint"]
CMD ["./docker-run"]

USER ntppool
