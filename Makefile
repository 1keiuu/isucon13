SHELL:=/bin/bash -e -o pipefail

MYSQL_SLOW_LOG_PATH:=/var/log/mysql/mysql-slow.log
NGINX_ACCESS_LOG_PATH:=/var/log/nginx/access.log
PPROTEIN_VERSION:=1.2.4
ALP_VERSION:=1.0.21
SLP_VERSION:=0.2.1

## [App] Restart server
app/restart:
	systemctl daemon-reload
	systemctl restart isupipe-go.service

## [App] Build
app/build:
	cd webapp/go && GOOS=linux GOARCH=amd64 go build -o isupipe

## [MySQL] Restart server
mysql/restart:
	systemctl restart mysql

## [MySQL] Rotate log file
mysql/rotate-log:
	-rm ${MYSQL_SLOW_LOG_PATH}
	# ファイルが更新されていることをMySQLに伝える
	systemctl restart mysql

## [MySQL] Install pt-query-digest
mysql/install-pt-query-digest:
	apt-get update
	apt-get install -y percona-toolkit

## [MySQL] Run pt-query-digest
mysql/pt-query-digest:
	pt-query-digest ${MYSQL_SLOW_LOG_PATH} > pt_query_digest_analysis.txt

## [MySQL] Run mysqldumpslow
mysql/mysqldumpslow:
	mysqldumpslow ${MYSQL_SLOW_LOG_PATH} > mysqldumpslow_analysis.txt

## [MySQL] Add missing indexes to the existing DB (run on app host; connects to the DB host). Do not run during a benchmark run.
mysql/add-index:
	mysql \
		-u"$${ISUCON13_MYSQL_DIALCONFIG_USER:-isucon}" \
		-p"$${ISUCON13_MYSQL_DIALCONFIG_PASSWORD:-isucon}" \
		--host "$${ISUCON13_MYSQL_DIALCONFIG_ADDRESS:-192.168.139.51}" \
		--port "$${ISUCON13_MYSQL_DIALCONFIG_PORT:-3306}" \
		"$${ISUCON13_MYSQL_DIALCONFIG_DATABASE:-isupipe}" \
		< webapp/sql/add_index.sql

## [MySQL] Add icons.icon_hash column to the existing DB (run on app host; connects to the DB host). Do not run during a benchmark run.
mysql/alter-icon-hash:
	mysql \
		-u"$${ISUCON13_MYSQL_DIALCONFIG_USER:-isucon}" \
		-p"$${ISUCON13_MYSQL_DIALCONFIG_PASSWORD:-isucon}" \
		--host "$${ISUCON13_MYSQL_DIALCONFIG_ADDRESS:-192.168.139.51}" \
		--port "$${ISUCON13_MYSQL_DIALCONFIG_PORT:-3306}" \
		"$${ISUCON13_MYSQL_DIALCONFIG_DATABASE:-isupipe}" \
		< webapp/sql/alter_icon_hash.sql

## [Nginx] Restart server
nginx/restart:
	nginx -t
	systemctl reload nginx

## [Nginx] Rotate log file
nginx/rotate-log:
	# 実行時点の日時を付与したファイル名にローテートする
	-mv ${NGINX_ACCESS_LOG_PATH} ${NGINX_ACCESS_LOG_PATH}.$(date +%Y%m%d-%H%M%S)
	# nginxにログファイルを開き直すシグナルを送信する
	nginx -s reopen

## [Nginx] Install alp
nginx/install-alp:
	apt install unzip
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.9/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo install ./alp /usr/local/bin

## [Nginx] Run alp
nginx/alp:
	alp ltsv --sort=avg --file ${NGINX_ACCESS_LOG_PATH} -m "/api/livestream/[0-9]+,/api/livestream/[0-9]+/livecomment,/api/livestream/[0-9]+/reaction,/api/user/[^/]+" -r -o count,method,uri,min,avg,max,sum > alp_analysis.txt

## [pprotein] First-time setup (app host)
pprotein/setup-app: pprotein/install-app
	mkdir -p /opt/pprotein
	systemctl daemon-reload
	systemctl enable --now pprotein.service pprotein-agent-httplog.service

pprotein/install-app:
	wget -q https://github.com/kaz/pprotein/releases/download/v$(PPROTEIN_VERSION)/pprotein_$(PPROTEIN_VERSION)_linux_amd64.tar.gz
	tar -xzf pprotein_$(PPROTEIN_VERSION)_linux_amd64.tar.gz
	install ./pprotein ./pprotein-agent /usr/local/bin/
	apt-get update
	apt-get install -y graphviz unzip
	wget -q https://github.com/tkuchiki/alp/releases/download/v$(ALP_VERSION)/alp_linux_amd64.zip
	unzip -o alp_linux_amd64.zip
	install ./alp /usr/local/bin/
	wget -q https://github.com/tkuchiki/slp/releases/download/v$(SLP_VERSION)/slp_linux_amd64.tar.gz
	tar -xzf slp_linux_amd64.tar.gz
	install ./slp /usr/local/bin/

## [pprotein] First-time setup (DB host)
pprotein/setup-db: pprotein/install-agent
	systemctl daemon-reload
	systemctl enable --now pprotein-agent.service

pprotein/install-agent:
	wget -q https://github.com/kaz/pprotein/releases/download/v$(PPROTEIN_VERSION)/pprotein_$(PPROTEIN_VERSION)_linux_amd64.tar.gz
	tar -xzf pprotein_$(PPROTEIN_VERSION)_linux_amd64.tar.gz
	install ./pprotein-agent /usr/local/bin/

