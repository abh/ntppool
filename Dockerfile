#FROM harbor.ntppool.org/ntppool/base-os:3.17.3
FROM harbor.ntppool.org/ntppool/base-os@sha256:14b36683bbdf8c03429b9b338dba0c1d405fc72857a3a495c5500190d7904697
USER root

ENV BUILD 20231202

RUN apk -U --no-cache upgrade --ignore alpine-baselayout
RUN cpanm Net::Async::HTTP::Server Plack::Handler::Net::Async::HTTP::Server Plack::Middleware::Headers
RUN cpanm OpenTelemetry OpenTelemetry::SDK OpenTelemetry::Exporter::OTLP Plack::Middleware::OpenTelemetry
#RUN cpanm https://tmp.askask.com/2023/12/Plack-Middleware-OpenTelemetry-0.233370-TRIAL.tar.gz
RUN cpanm https://tmp.askask.com/2023/12/Net-Async-HTTP-Server-0.14.tar.gz

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
