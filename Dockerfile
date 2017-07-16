FROM quay.io/ntppool/base-os:v2.1

USER root
ENV CBCONFIG=
ENV HULK /usr/bin/hulk

WORKDIR /ntppool
VOLUME /ntppool/data

EXPOSE 8299
CMD ./docker-run

ADD . /ntppool

RUN chown ntppool data
RUN rm -fr docs/ntppool/_syndicate; ln -s /ntppool/data/syndicate docs/ntppool/_syndicate

#RUN ls -al docs/ntppool; mkdir docs/ntppool/_syndicate; chown ntppool docs/ntppool/_syndicate

# because quay.io sets timestamps to 1980 for some reason ...
RUN find ./docs -type f -print0 | xargs -0 touch

RUN perl Makefile.PL && \
  make templates && \
  CBCONFIG=docker/combust.build.conf bin/setup && \
  mkdir -p tmp logs && \
  chown -R ntppool tmp logs

RUN bash -c "ls -la docs/shared/static{,/.g,/css}"

USER ntppool

