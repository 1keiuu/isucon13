-- 既存の isupipe DB に INDEX を追加する（一度だけ実行する）
--
--   mysql -uisucon -pisucon --host <DB_HOST> isupipe < add_index.sql
--
-- initdb.d/10_schema.sql は DB の初期構築時にしか実行されないため、
-- 既に稼働している DB にはこのファイルを手で流す必要がある。
-- init.sql は TRUNCATE のみなので、一度追加すれば /initialize では消えない。
--
-- 注意: ADD INDEX 中はテーブルがロックされうるので、負荷走行中に流さないこと。

USE `isupipe`;

-- livecomments: WHERE livestream_id = ? ORDER BY created_at DESC を1本でカバーする
ALTER TABLE `livecomments` ADD INDEX `idx_livecomments_livestream_created` (`livestream_id`, `created_at` DESC);
ALTER TABLE `livecomments` ADD INDEX `idx_livecomments_user` (`user_id`);

-- reactions: WHERE livestream_id = ? ORDER BY created_at DESC
ALTER TABLE `reactions` ADD INDEX `idx_reactions_livestream_created` (`livestream_id`, `created_at` DESC);
ALTER TABLE `reactions` ADD INDEX `idx_reactions_user` (`user_id`);

-- livestreams: WHERE user_id = ?
ALTER TABLE `livestreams` ADD INDEX `idx_livestreams_user` (`user_id`);

-- icons / themes: 1ユーザ1行なので UNIQUE
ALTER TABLE `icons` ADD UNIQUE INDEX `uniq_icons_user` (`user_id`);
ALTER TABLE `themes` ADD UNIQUE INDEX `uniq_themes_user` (`user_id`);

-- livestream_tags: WHERE livestream_id = ? / WHERE tag_id IN (?) ORDER BY livestream_id DESC
ALTER TABLE `livestream_tags` ADD INDEX `idx_livestream_tags_livestream` (`livestream_id`);
ALTER TABLE `livestream_tags` ADD INDEX `idx_livestream_tags_tag` (`tag_id`, `livestream_id`);

-- livecomment_reports: WHERE livestream_id = ?
ALTER TABLE `livecomment_reports` ADD INDEX `idx_livecomment_reports_livestream` (`livestream_id`);

-- livestream_viewers_history: COUNT(*) WHERE livestream_id = ? / DELETE WHERE user_id = ? AND livestream_id = ?
ALTER TABLE `livestream_viewers_history` ADD INDEX `idx_viewers_livestream` (`livestream_id`);
ALTER TABLE `livestream_viewers_history` ADD INDEX `idx_viewers_user_livestream` (`user_id`, `livestream_id`);

-- ng_words: 投げ銭 POST のスパム判定（初期データ 14337 行のフルスキャンを消す）
ALTER TABLE `ng_words` ADD INDEX `idx_ng_words_user_livestream` (`user_id`, `livestream_id`);
ALTER TABLE `ng_words` ADD INDEX `idx_ng_words_livestream` (`livestream_id`);

-- reservation_slots: WHERE start_at >= ? AND end_at <= ? FOR UPDATE
ALTER TABLE `reservation_slots` ADD INDEX `idx_reservation_slots_range` (`start_at`, `end_at`);
