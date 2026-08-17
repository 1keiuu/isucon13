-- 既存の isupipe DB に icons.icon_hash カラムを追加する（一度だけ実行する）
--
--   mysql -uisucon -pisucon --host <DB_HOST> isupipe < alter_icon_hash.sql
--
-- initdb.d/10_schema.sql は DB の初期構築時にしか実行されないため、
-- 既に稼働している DB にはこのファイルを手で流す必要がある。
-- init.sql は TRUNCATE のみなので、一度追加すれば /initialize では消えない。
--
-- 注意: このファイルは add_index.sql とは別ファイルにしてある。
-- add_index.sql は既に本番DBに適用済みの可能性があり、mysqlクライアントは
-- 標準入力を最初のエラーで読み止める(以降のSQLは実行されない)ため、
-- add_index.sql に追記すると「重複INDEXエラーで後続のALTER TABLEが
-- 実行されずカラムが追加されない」事故が起きる。そのため本カラム追加は
-- 単独のファイル・単独の実行として扱う。
--
-- 注意: ADD COLUMN 中はテーブルがロックされうるので、負荷走行中に流さないこと。

USE `isupipe`;

-- icons: 画像のSHA256(hex)を書き込み時に保存し、読み取り側でLONGBLOBを
-- 読まずに済むようにする(#11)。
ALTER TABLE `icons` ADD COLUMN `icon_hash` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '';
