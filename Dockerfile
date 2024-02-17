FROM harbor.ntppool.org/ntppool/base-os:3.19.0-1
#FROM harbor.ntppool.org/ntppool/base-os@sha256:0e2e854c256547417439128e6754c82d4b32a06a4298b3c585c1dbfb62b300fc
USER root

ENV BUILD 20231202

RUN apk -U --no-cache upgrade --ignore alpine-baselayout
RUN cpanm Net::Async::HTTP::Server Plack::Handler::Net::Async::HTTP::Server Plack::Middleware::Headers
RUN cpanm OpenTelemetry OpenTelemetry::SDK OpenTelemetry::Exporter::OTLP Plack::Middleware::OpenTelemetry
RUN cpanm https://tmp.askask.com/2024/01/Plack-Middleware-OpenTelemetry-0.240030.tar.gz
RUN cpanm https://tmp.askask.com/2024/02/Net-Async-HTTP-Server-0.14bis2.tar.gz

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

RUN git config --global --add safe.directory /ntppool
