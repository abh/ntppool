FROM quay.io/ntppool/app-base

ADD . /ntppool

WORKDIR /ntppool
EXPOSE 8299

CMD ./docker-run

