FROM ruby:2.3-alpine

RUN apk add --no-cache git

ADD . /sneakers

WORKDIR /sneakers

RUN apk --update add --virtual build_deps \
                               build-base \
                               ruby-dev \
                               libc-dev \
                               linux-headers \
                               openssl-dev && \

    bundle --jobs=4 --retry=3 && \

    apk del build_deps

CMD rake test
