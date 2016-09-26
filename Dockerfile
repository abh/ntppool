FROM quay.io/ntppool/app-base:latest

ADD . /ntppool

WORKDIR /ntppool
EXPOSE 8299

CMD ./docker-run

