#!/usr/bin/env bash

set -eux
cd $(dirname $0)

if test -f /home/isucon/env.sh; then
	. /home/isucon/env.sh
fi

ISUCON_DB_HOST=${ISUCON13_MYSQL_DIALCONFIG_ADDRESS:-192.168.139.51}
ISUCON_DB_PORT=${ISUCON13_MYSQL_DIALCONFIG_PORT:-3306}
ISUCON_DB_USER=${ISUCON13_MYSQL_DIALCONFIG_USER:-isucon}
ISUCON_DB_PASSWORD=${ISUCON13_MYSQL_DIALCONFIG_PASSWORD:-isucon}
ISUCON_DB_NAME=${ISUCON13_MYSQL_DIALCONFIG_DATABASE:-isupipe}

mysql_args=(
	-u"$ISUCON_DB_USER"
	-p"$ISUCON_DB_PASSWORD"
	--host "$ISUCON_DB_HOST"
	--port "$ISUCON_DB_PORT"
)

# long_query_time=0 のとき、大量 INSERT を slow log に書くと initialize がタイムアウトする
mysql "${mysql_args[@]}" -e "SET GLOBAL slow_query_log = OFF" || true

# 1 セッションにまとめてリモート DB への往復を減らす
cat init.sql \
	initial_users.sql \
	initial_livestreams.sql \
	initial_tags.sql \
	initial_livestream_tags.sql \
	initial_reservation_slots.sql \
	initial_reactions.sql \
	initial_ngwords.sql \
	initial_livecomments.sql \
	| mysql "${mysql_args[@]}" "$ISUCON_DB_NAME"

mysql "${mysql_args[@]}" -e "SET GLOBAL slow_query_log = ON" || true

bash ../pdns/init_zone.sh
