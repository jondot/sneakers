FROM ruby:2.3.7-alpine3.7

RUN apk add --no-cache git

RUN apk --update add --virtual build_deps \
                               build-base \
                               ruby-dev \
                               libc-dev \
                               linux-headers \
                               openssl-dev

WORKDIR /sneakers

COPY lib/sneakers/version.rb lib/sneakers/version.rb

COPY sneakers.gemspec .

COPY Gemfile* ./

RUN bundle install --retry=3

COPY . .

CMD rake test
