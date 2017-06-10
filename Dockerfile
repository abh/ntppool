FROM quay.io/ntppool/base-os:latest

ADD . /ntppool

WORKDIR /ntppool
EXPOSE 8299

CMD ./docker-run

