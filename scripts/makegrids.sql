CREATE TEMPORARY TABLE clangridb_won SELECT c1.id AS x, c2.id AS y, COUNT(gb.id) AS count FROM clans c1 INNER JOIN clans c2 INNER JOIN members m1 ON m1.clan_id=c1.id INNER JOIN members m2 ON m2.clan_id=c2.id LEFT OUTER JOIN games gb ON gb.black_id = m1.id AND gb.white_id = m2.id AND gb.result = 1  WHERE c1.period_id = 9 AND c2.period_id = 9 GROUP BY c1.id, c2.id;
CREATE TEMPORARY TABLE clangridw_won SELECT c1.id AS x, c2.id AS y, COUNT(gw.id) AS count FROM clans c1 INNER JOIN clans c2 INNER JOIN members m1 ON m1.clan_id=c1.id INNER JOIN members m2 ON m2.clan_id=c2.id LEFT OUTER JOIN games gw ON gw.black_id = m2.id AND gw.white_id = m1.id AND gw.result = -1 WHERE c1.period_id = 9 AND c2.period_id = 9 GROUP BY c1.id, c2.id;
CREATE TEMPORARY TABLE clangridb SELECT c1.id AS x, c2.id AS y, COUNT(gb.id) AS count FROM clans c1 INNER JOIN clans c2 INNER JOIN members m1 ON m1.clan_id=c1.id INNER JOIN members m2 ON m2.clan_id=c2.id LEFT OUTER JOIN games gb ON gb.black_id = m1.id AND gb.white_id = m2.id WHERE c1.period_id = 9 AND c2.period_id = 9 GROUP BY c1.id, c2.id;
CREATE TEMPORARY TABLE clangridw SELECT c1.id AS x, c2.id AS y, COUNT(gw.id) AS count FROM clans c1 INNER JOIN clans c2 INNER JOIN members m1 ON m1.clan_id=c1.id INNER JOIN members m2 ON m2.clan_id=c2.id LEFT OUTER JOIN games gw ON gw.black_id = m2.id AND gw.white_id = m1.id WHERE c1.period_id = 9 AND c2.period_id = 9 GROUP BY c1.id, c2.id;
DROP TABLE IF EXISTS clangrid;
CREATE TABLE clangrid SELECT clangridw.x AS x, clangridw.y AS y, clangridw.count + clangridb.count AS played, clangridw_won.count + clangridb_won.count AS won FROM clangridw INNER JOIN clangridb USING(x, y) INNER JOIN clangridw_won USING(x, y) INNER JOIN clangridb_won USING(x, y);
