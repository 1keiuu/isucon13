#!/usr/bin/env bash

set -ue -o pipefail

rsync -av ./Makefile isuconapp:~
rsync -av ./systemd/pprotein.service ./systemd/pprotein-agent-httplog.service isuconapp:/etc/systemd/system/
ssh isuconapp 'make pprotein/setup-app'

rsync -av ./Makefile isucondb:~
rsync -av ./systemd/pprotein-agent.service isucondb:/etc/systemd/system/
rsync -av ./mysql/allow-remote.sql isucondb:/etc/mysql/
