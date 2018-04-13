FROM ruby:2.3-alpine

RUN apk add --no-cache git

RUN apk --update add --virtual build_deps \
                               build-base \
                               ruby-dev \
                               libc-dev \
                               linux-headers \
                               openssl-dev

RUN mkdir /myapp

WORKDIR /sneakers

COPY lib/sneakers/version.rb /sneakers/lib/sneakers/version.rb

COPY sneakers.gemspec /sneakers/sneakers.gemspec

COPY Gemfile /sneakers/Gemfile

COPY Gemfile.lock /sneakers/Gemfile.lock

RUN bundle --jobs=4 --retry=3

COPY . /sneakers

CMD rake test
