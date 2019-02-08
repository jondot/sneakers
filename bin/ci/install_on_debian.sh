#!/bin/sh

sudo apt-get install -y wget
wget -O - "https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc" | sudo apt-key add -

sudo tee /etc/apt/sources.list.d/bintray.rabbitmq.list <<EOF
deb https://dl.bintray.com/rabbitmq-erlang/debian xenial erlang
deb https://dl.bintray.com/rabbitmq/debian xenial main
EOF

sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y rabbitmq-server

sudo service rabbitmq-server start

until sudo lsof -i:5672; do echo "Waiting for RabbitMQ to start..."; sleep 1; done
