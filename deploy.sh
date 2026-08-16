#!/usr/bin/env bash

set -ue

make app/build

rsync -av ./webapp/ isuconapp:/home/isucon/webapp/
rsync -av ./env.sh isuconapp:/home/isucon/env.sh
rsync -av ./nginx/ isuconapp:/etc/nginx/
rsync -av ./systemd/isupipe-go.service isuconapp:/etc/systemd/system/
rsync -av ./mysql/ isucondb:/etc/mysql/
rsync -av ./Makefile isuconapp:~
rsync -av ./Makefile isucondb:~

ssh isuconapp 'make app/restart'
ssh isuconapp 'make nginx/restart'
ssh isuconapp 'make nginx/rotate-log'

ssh isucondb 'make mysql/restart'
ssh isucondb 'make mysql/rotate-log'
