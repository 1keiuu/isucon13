-- app サーバーなど外部ホストからの接続を許可する（DB サーバーで実行）
CREATE USER IF NOT EXISTS 'isucon'@'%' IDENTIFIED BY 'isucon';
GRANT ALL PRIVILEGES ON isupipe.* TO 'isucon'@'%';
FLUSH PRIVILEGES;
