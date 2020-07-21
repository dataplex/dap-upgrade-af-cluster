#!/usr/bin/env bash

. config.sh

queryAllNodes ".[] | { IP: .ip, hostname: .info.configuration.conjur.hostname }"
