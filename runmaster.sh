#!/usr/bin/env bash
VER=$1

docker run --name dap \
    -d --restart=unless-stopped \
    --log-driver=journald \
    --security-opt seccomp:unconfined \
    -v /var/log/conjur:/var/log/conjur \
    -v /opt/conjur/backup:/opt/conjur/backup \
    -p 443:443 \
    -p 1999:1999 \
    -p 5432:5432 \
    registry.tld/conjur-appliance:$VER
