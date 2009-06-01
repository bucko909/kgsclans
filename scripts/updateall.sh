#!/bin/bash

(echo -n 'Beginning nightly update: '; date) >> /home/kgs/UPDATE.ERR

cd /home/kgs/public_html
REQUEST_METHOD=GET REMOTE_USER=system QUERY_STRING='mode=all&delay=10' ./update.pl > /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR
cd /home/kgs
mysql < scripts/makegrids.sql >> /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR

# Log clan points history
mysql -se 'INSERT INTO clanpoints_history SELECT UNIX_TIMESTAMP(), id, points FROM clans WHERE period_id = 9;'

# Ensure forum users are associated properly with their clans.
mysql -se 'DELETE FROM forumuser_clans; INSERT IGNORE INTO forumuser_clans SELECT phpbb3_user_group.user_id AS user_id, clans.id AS clan_id, clans.name AS clan_name FROM phpbb3_user_group INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_group_id AND clans.period_id = 9;'

# Nightly backup
dump1=/home/kgs/dbdumps/dbdump-"`date +%y%m%d-%H%M%S`".sql
mysqldump kgs > "$dump1"

# Public dump
mysqldump -t kgs games kgs_usernames members teams team_members team_matches team_match_players team_match_teams team_match_seats clans clanperiods content options | gzip > /home/kgs/public_html/db/data.sql.gz
mysqldump -d kgs games kgs_usernames members teams team_members team_seats team_matches team_match_players team_match_teams team_match_seats clans clanperiods content options forumuser_clans clangrid clanpoints_history hits log log_params | gzip > /home/kgs/public_html/db/structure.sql.gz
chmod 600 "$dump1"
