#!/bin/bash

cd /home/kgs/public_html
REQUEST_METHOD=GET REMOTE_USER=bucko QUERY_STRING='mode=all&delay=10' ./update.pl > /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR
cd /home/kgs
mysql < scripts/makegrids.sql >> /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR

#The following should no longer be needed. update.pl /should/ sort it all out.
#mysql < update.sql >> /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR

#This is done in update.pl now.
#J=`mysql -se 'SELECT value-1 FROM options WHERE name = "BRAWLGAMES" AND clanperiod = (SELECT MAX(id) FROM clanperiods)'`
#mysql -se 'SELECT id FROM clans WHERE clanperiod = (SELECT MAX(id) FROM clanperiods)'|while read I; do mysql -se 'SELECT time FROM games LEFT OUTER JOIN members mb ON mb.id = black_id LEFT OUTER JOIN members mw ON mw.id = white_id WHERE mw.clan_id = '$I' OR mb.clan_id = '$I' ORDER BY time LIMIT '$J',1'|sed s/$/\ $I/; done|(while read I J; do echo "UPDATE clans SET got100time = $I WHERE id = $J;"; done)|mysql

# Log clan points history
mysql -se 'INSERT INTO clanpoints_history SELECT UNIX_TIMESTAMP(), id, points FROM clans WHERE clanperiod = 5;'

# Ensure forum users are associated properly with their clans.
mysql -se 'DELETE FROM forumuser_clans; INSERT INTO forumuser_clans SELECT phpbb3_user_group.user_id AS user_id, clans.id AS clan_id, clans.name AS clan_name FROM phpbb3_user_group INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_group_id AND clans.clanperiod = 6;'

# Nightly backup
dump1=/home/kgs/dbdumps/dbdump-"`date +%y%m%d-%H%M%S`".sql
mysqldump kgs > "$dump1"

# Public dump
mysqldump -t kgs games aliases members brawl_teams brawl_team_members brawldraw brawldraw_results clans clanperiods content options | gzip > /home/kgs/public_html/db/data.sql.gz
mysqldump -d kgs games aliases members brawl brawl_teams brawl_team_members brawldraw brawldraw_results clans clanperiods content options forumuser_clans clangrid clanpoints_history hits log log_params | gzip > /home/kgs/public_html/db/structure.sql.gz
chmod 600 "$dump1"
