FROM ruby:2.3-alpine

RUN apk add --no-cache git
RUN apk --update add --virtual build_deps \
build-base ruby-dev libc-dev linux-headers \
openssl-dev

ADD . /sneakers
WORKDIR /sneakers

RUN bundle --jobs=4 --retry=3

CMD rake test
