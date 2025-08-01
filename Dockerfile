FROM harbor.ntppool.org/ntppool/base-os:3.22.1-1
USER root

ENV BUILD 20241215

RUN apk -U --no-cache upgrade --ignore alpine-baselayout
RUN apk --no-cache add gomplate alpine-base perl-file-slurper nodejs npm
RUN cpanm -v https://tmp.askask.com/2024/12/Net-Async-HTTP-Server-0.14bis4.tar.gz

ENV CBCONFIG=

WORKDIR /ntppool
VOLUME /ntppool/data

ADD . /ntppool

RUN mkdir /var/ntppool && chown ntppool data /var/ntppool
RUN rm -fr docs/ntppool/_syndicate && \
  mkdir -p data/syndicate && \
  ln -s /ntppool/data/syndicate docs/ntppool/_syndicate && \
  chown ntppool data/syndicate

# make sure all our assets have recent timestamps
RUN find ./docs -type f -print0 | xargs -0 touch

RUN perl Makefile.PL && \
  make js-build-prod && \
  CBCONFIG=docker/combust.build.conf bin/setup && \
  mkdir -p tmp logs && \
  chown -R ntppool tmp logs

#RUN bash -c "ls -la docs/shared/static{,/.g,/css}"

EXPOSE 8299
ENTRYPOINT ["./docker/entrypoint"]
CMD ["./docker-run"]

USER ntppool

RUN git config --global --add safe.directory /ntppool
