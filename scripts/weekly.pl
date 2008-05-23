#!/usr/bin/perl

use strict;
use warnings;
use Clans;
use Time::Local;
use Carp;
use POSIX qw/strftime/;

$SIG{__DIE__} = sub { no warnings; undef $SIG{__DIE__}; confess $_[0] };
$SIG{__WARN__} = sub { local $SIG{__WARN__}; Carp::cluck $_[0]};

our $c = Clans->new;

our $post_time = time();

our $dryrun = 0;

my @t = gmtime();
our $now_time = timegm(@t);
$t[0] = 0;
$t[1] = 0;
$t[2] = 0;
our $end_time = timegm(@t);
our $start_time = $end_time - 60*60*24*7;

# Get forum activity. This needs to be done bang on midnight.
our $period_info = $c->period_info;

my $lastvisit_results = $c->db_select("SELECT MAX(phpbb3_users.user_last_pageview), clans.id FROM phpbb3_users INNER JOIN phpbb3_user_group USING(user_id) INNER JOIN phpbb3_groups ON phpbb3_groups.group_id = phpbb3_user_group.group_id RIGHT OUTER JOIN clans ON clans.forum_leader_group_id = phpbb3_groups.group_id WHERE clanperiod = ? GROUP BY clans.id;", {}, $period_info->{id});
# Includes ban on Wu Tang's forum
#my $lastpost_results = $c->db_select("SELECT MAX(phpbb3_posts.post_time), clans.id FROM phpbb3_posts INNER JOIN phpbb3_users ON phpbb3_users.user_id = phpbb3_posts.poster_id NATURAL JOIN phpbb3_user_group NATURAL JOIN phpbb3_groups RIGHT OUTER JOIN clans ON clans.forum_group_id = phpbb3_groups.group_id WHERE clanperiod = ? AND phpbb3_posts.forum_id != 27 GROUP BY clans.id;", {}, $period_info->{id});
my $lastpost_results = $c->db_select("SELECT MAX(phpbb3_posts.post_time), clans.id FROM phpbb3_posts INNER JOIN phpbb3_users ON phpbb3_users.user_id = phpbb3_posts.poster_id INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN phpbb3_groups ON phpbb3_groups.group_id = phpbb3_user_group.group_id RIGHT OUTER JOIN clans ON clans.forum_group_id = phpbb3_groups.group_id WHERE clanperiod = ? GROUP BY clans.id;", {}, $period_info->{id});

my $group_duplicates = $c->db_select(qq|SELECT phpbb3_users.user_id, phpbb3_users.username, COUNT(phpbb3_user_group.group_id) AS total, GROUP_CONCAT(CONCAT(clans.name,"(",clans.id,")")) AS clans FROM phpbb3_users INNER JOIN phpbb3_user_group USING(user_id) INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_group_id AND clans.clanperiod = ? GROUP BY phpbb3_users.user_id HAVING total > 1|, {}, $period_info->{id});
our %clan_duplicates;
foreach my $dup (@$group_duplicates) {
	foreach my $clan (split /,/, $dup->[3]) {
		if ($clan =~ /\((\d*)\)$/) {
			$clan_duplicates{$1} ||= [];
			push @{$clan_duplicates{$1}}, $dup;
		}
	}
}

our %lastvisit = map { $_->[1] => $_->[0] } @$lastvisit_results;
our %lastpost = map { $_->[1] => $_->[0] } @$lastpost_results;

# Run the nightly update

if ($dryrun) {
	print "Skipping system update.\n";
} else {
	system("/home/kgs/scripts/updateall.sh");
}

our $u = "00000000"; # UUID for forum posts

our $debugpost = '';

sub forum_activity {
	my ($clan_id) = @_;
	my $forum_activity = "";
	if (!$lastvisit{$clan_id} || $lastvisit{$clan_id} < $start_time) {
		$forum_activity .= "None of the clan leaders signed onto the forum in the last week, so the clan gets a 2 point penalty.\n\n";
		#$forum_activity .= "None of the clan leaders signed onto the forum in the last week, so the clan would get a 2 point penalty - but this is disabled for the first update.\n\n";
		$debugpost .= "$clan_id got a penalty for not signing on. ";
		if ($lastvisit{$clan_id}) {
			$debugpost .= "Last visit was $lastvisit{$clan_id} vs. start time of $start_time.\n\n";
		} else {
			$debugpost .= "No last visit recorded.\n\n";
		}
		if ($dryrun) {
			print "Removing 2 points from $clan_id.\n";
		} else {
			$c->db_do("UPDATE clans SET points = points - 2 WHERE id = ?", {}, $clan_id);
		}
	}
	if ($lastpost{$clan_id} && $lastpost{$clan_id} > $start_time) {
		$forum_activity .= "A member of the clan posted to the forum, so the clan gets 2 points.\n\n";
		$debugpost .= "$clan_id got a bonus for posting. ";
		$debugpost .= "Last post was $lastpost{$clan_id} vs. start time of $start_time.\n\n";
		if ($dryrun) {
			print "Adding 2 points to $clan_id.\n";
		} else {
			$c->db_do("UPDATE clans SET points = points + 2 WHERE id = ?", {}, $clan_id);
		}
	} else {
		$debugpost .= "$clan_id did not get a bonus for posting. ";
		if ($lastpost{$clan_id}) {
			$debugpost .= "Last visit was $lastpost{$clan_id} vs. start time of $start_time.\n\n";
		} else {
			$debugpost .= "No last post recorded.\n\n";
		}
	}
	return $forum_activity;
}

# Find inactive new members
sub inactive_new_members {
	my ($clan_id) = @_;
	# Inactive for one week; give warning
	my $warn = $c->db_select("SELECT members.id, members.name, members.rank, MAX(activity) AS maxactivity FROM aliases INNER JOIN members ON members.id = aliases.member_id WHERE members.played = 0 AND members.clan_id = ? GROUP BY members.id HAVING maxactivity >= ? AND maxactivity < ?;", {}, $clan_id, $end_time - 60*60*24*7*2, $end_time - 60*60*24*7*1);
	# Inactive for two weeks or more; delete
	my $delete = $c->db_select("SELECT members.id, members.name, members.rank, MAX(activity) AS maxactivity FROM aliases INNER JOIN members ON members.id = aliases.member_id WHERE members.played = 0 AND members.clan_id = ? GROUP BY members.id HAVING maxactivity < ?", {}, $clan_id, $end_time - 60*60*24*7*2);

	my $inactivity = '';
	if (@$warn) {
		$inactivity .= "The following members joined last week and have played no games yet, so will be automatically removed if they do not play in the next week:[list:$u]\n";
		for(@$warn) {
			$inactivity .= "[*:$u]".$c->render_member($_->[0], $_->[1], $_->[2]).".[/*:m:$u]\n";
		}
		$inactivity .= "[/list:u:$u]\n\n";
	}
	if (@$delete) {
		$inactivity .= "The following members joined over 2 weeks ago and played no games, so they have been automatically removed from the system.[list:$u]\n";
		for(@$delete) {
			$inactivity .= "[*:$u]".$c->render_member($_->[0], $_->[1], $_->[2]).".[/*:m:$u]\n";
			if ($dryrun) {
				print "Would delete member $_->[0].\n";
			} else {
				$c->db_do("DELETE FROM aliases WHERE member_id = ?", {}, $_->[0]);
				$c->db_do("DELETE FROM members WHERE id = ?", {}, $_->[0]);
			}
		}
		$inactivity .= "[/list:u:$u]\n\n";
	}
	return $inactivity;
}

sub game_summary {
	my ($clan_id) = @_;
	my $played = $c->db_select('SELECT members.id, members.name, members.rank, COUNT(games.id) AS gamecount, SUM(IF(members.id = white_id, black_id IS NOT NULL, white_id IS NOT NULL)), SUM(IF(members.id = white_id, result = -1, result = 1)), SUM(IF(members.id = white_id, black_id IS NOT NULL AND result = -1, white_id IS NOT NULL AND result = 1)) FROM games INNER JOIN members ON games.black_id = members.id OR games.white_id = members.id WHERE time > ? AND time <= ? AND clan_id = ? GROUP BY members.id HAVING gamecount > 0 ORDER BY gamecount DESC', {}, $start_time, $end_time, $clan_id);
#	my $inactive = $c->db_select('SELECT members.id, members.name, members.rank, COUNT(games.id) AS gamecount FROM members LEFT OUTER JOIN games ON games.black_id = members.id OR games.white_id = members.id WHERE time > ? AND time <= ? AND clan_id = ? GROUP BY members.id HAVING gamecount = 0', {}, $start_time, $end_time, $clan_id);
	my $inactive = $c->db_select('SELECT members.id, members.name, members.rank, MAX(time) AS maxtime FROM members LEFT OUTER JOIN games ON (games.black_id = members.id OR games.white_id = members.id) AND time > ? AND time <= ? WHERE members.clan_id = ? GROUP BY members.id HAVING maxtime IS NULL', {}, $start_time, $end_time, $clan_id);
	my $summary = '';
	if (@$played) {
		$summary = "Members who played games:[list:$u]\n";
		for(@$played) {
			$summary .= "[*:$u]".$c->render_member($_->[0], $_->[1], $_->[2])." played $_->[3] and won $_->[5]; in pure games only, they played $_->[4] and won $_->[6].[/*:m:$u]\n";
		}
		$summary .= "[/list:u:$u]\n\n";
		if (@$inactive) {
			$summary .= "The following members were too lazy to play any games at all: ";
			$summary .= join(', ', map { $c->render_member($_->[0], $_->[1], $_->[2]) } @$inactive).".\n\n";
		}
	} else {
		$summary .= "No members of the clan played any games, so the clan incurred a penalty of 2 points.\n\n";
		if ($dryrun) {
			print "Removing two points from $clan_id.\n\n";
		} else {
			$c->db_do("UPDATE clans SET points = points - 2 WHERE id = ?", {}, $clan_id);
		}
	}
	return $summary;
}

sub check_groups {
	my ($clan_id) = @_;
	my @duplicates = @{$clan_duplicates{$clan_id} || []};
	my $group_check = '';
	foreach my $dup (@duplicates) {
		my @clanlist = map { /(.*)\((\d*)\)/; $c->render_clan($2, $1) } split /,/, $dup->[3];
		$group_check .= qq|<a href="/forum/profile.php?mode=viewprofile&amp;u=$dup->[0]">$dup->[1]</a> is in multiple clans: |.join(", ", @clanlist)."\n\n";
	}
	return $group_check;
}

my ($results) = $c->db_select('SELECT id, name, forum_id FROM clans WHERE forum_id IS NOT NULL AND clanperiod = ?', {}, $period_info->{id});
for(@$results) {
	my $summary = "Summary for ".$c->render_clan($_->[0], $_->[1])." for the period ".strftime("%d/%m/%y", gmtime $start_time)." to ".strftime("%d/%m/%y", gmtime $end_time).":\n\n".game_summary($_->[0]).inactive_new_members($_->[0]).forum_activity($_->[0]).check_groups($_->[0]);
	forum_post_or_reply($c, $_->[2], "Clan Game Summary", "Clan Game Summary, ".strftime("%d/%m/%y", gmtime $end_time), $summary, $u);
}

my ($clanresults) = $c->db_select("SELECT clans.id, clans.name, SUM(active.total) AS total FROM clans LEFT OUTER JOIN (SELECT DISTINCT mw.clan_id AS clan_id, COUNT(games.id) AS total FROM games INNER JOIN members mw ON white_id = mw.id WHERE time > ? AND time <= ? GROUP BY mw.clan_id UNION ALL SELECT mb.clan_id AS clan_id, COUNT(games.id) AS total FROM games INNER JOIN members mb ON black_id = mb.id WHERE time > ? AND time <= ? GROUP BY mb.clan_id) active ON clans.id = active.clan_id WHERE clanperiod = ? GROUP BY clans.id ORDER BY total DESC, clans.tag;", {}, $start_time, $end_time, $start_time, $end_time, $period_info->{id});

my $clansummary = "";
my $ispositive = 0;
for(@$clanresults) {
	if ($_->[2]) {
		if (!$ispositive) {
			$ispositive = 1;
			$clansummary .= "Game summary for all clans for the period ".strftime("%d/%m/%y", gmtime $start_time)." to ".strftime("%d/%m/%y", gmtime $end_time).":[list:$u]\n\n";
		} 
		$clansummary .= "[*:$u] ".$c->render_clan($_->[0], $_->[1])." played ".($_->[2] == 1 ? "[b:$u]1[/b:$u] game" : "[b:$u]".$_->[2]."[/b:$u] games").".[/*:m:$u]\n";
	} else {
		if ($ispositive) {
			$ispositive = 0;
			$clansummary .= "[/list:u:$u]\n\nThe following clans played no games: ";
		}
		$clansummary .= $c->render_clan($_->[0], $_->[1]).($_->[0] == $clanresults->[$#$clanresults][0] ? ".\n" : ", ");
	}
}
$clansummary .= "[/list:u:$u]\n" if $ispositive;

# Expire inactive clans.
# Seems like it'll be too much effort for now.

#my $clans_warn = $c->db_do("SELECT clans.id, clans.name, MAX(activity) AS lastactive FROM clans LEFT OUTER JOIN aliases ON clans.leader_id = aliases.member_id WHERE clanperiod = ? AND points = 0 GROUP BY clans.id HAVING MAX(activity) < ? AND MAX(activity) >= ?", $c->getperiod, $end_time - 60*60*24*7*1, $endtime - 60*60*24*7*2);
#my $clans_delete = $c->db_do("SELECT clans.id, clans.name, MAX(activity) AS lastactive, clans.forum_id, clans.forum_private_id, clans.forum_group_id, clans.forum_leader_group_id FROM clans LEFT OUTER JOIN aliases ON clans_leader_id = aliases.member_id WHERE clanperiod = ? AND points = 0 GROUP BY clans.id HAVING MAX(activity) IS NULL OR MAX(activity) < ?", $c->getperiod, $end_time - 60*60*24*7*2);

#my $clan_inactivity = '';
#if (@$clans_warn) {
#	$clan_inactivity .= "The following clans have accrued no points and have been around over a week; they will be automatically removed if they get no points in the next week:[list:$u]\n";
#	for(@$clans_warn) {
#		$clan_inactivity .= "[*:$u]".$c->render_clan($_->[0], $_->[1]).".\n";
#	}
#	$clan_inactivity .= "[/list:u:$u]\n\n";
#}
#if (@$clans_delete) {
#	$clan_inactivity .= "The following clans joined over 2 weeks ago or had their leader removed as well as having no points, so they have been automatically removed from the system.[list:$u]\n";
#	for(@$delete) {
#		$clan_inactivity .= "[*:$u]".$c->render_clan($_->[0], $_->[1]).".\n";
#		print "DELETE FROM phpbb3_groups WHERE group_id = ? OR group_id = ?, $_->[5], $_->[6]";
#		print "DELETE FROM phpbb3_user_group WHERE group_id = ? OR group_id = ?, $_->[5], $_->[6]";
#		print "DELETE FROM phpbb3_forums WHERE forum_id = ? OR forum_id = ?, $_->[3], $_->[4]";
#		# There will be no posts, since a post on the forum accrues one point!
#		print "DELETE FROM aliases WHERE member_id = ?, $_->[0]\n";
#		print "DELETE FROM members WHERE id = ?, $_->[0]\n";
#	}
#	$clan_inactivity .= "[/list:u:$u]\n\n";
#}

forum_post_or_reply($c, 1, "Clan Game Summary", "Clan Game Summary, ".strftime("%d/%m/%y", gmtime $end_time), $clansummary, $u);

forum_post_or_reply($c, 21, "Clan Game Debug", "Clan Game Debug, ".strftime("%d/%m/%y", gmtime $end_time), $debugpost, $u);

sub forum_post_or_reply {
	my ($c, $forum, $topic_title, $title, $content, $uuid) = @_;
	$content =~ s/<a href="(http.*?)">(.*?)<\/a>/\[url=$1\]$2\[\/url\]/g;
	$content =~ s/<a href="(.*?)">(.*?)<\/a>/\[url=http:\/\/www.kgsclans.co.uk\/$1:$u\]$2\[\/url:$u\]/g;
	my $topic = $c->db_selectone("SELECT topic_id FROM phpbb3_topics WHERE forum_id = ? AND topic_poster = 53", {}, $forum);
	my $new;
	if (!$topic) {
		$topic = forum_new_thread($c, $forum, $topic_title);
		$new = 1;
	}
	if ($dryrun) {
		print "Posting to forum $forum, topic $topic\n";
		print $content;
		return;
	}
	$c->db_do("INSERT INTO phpbb3_posts SET topic_id = ?, forum_id = ?, poster_id = ?, post_time = ?, enable_smilies = 0, post_subject = ?, post_text = ?, bbcode_uid = ?, bbcode_bitfield = ?", {}, $topic, $forum, 53, $post_time, $title, $content, $uuid, "UEA=") or die;
	my $post_id = $c->lastid;
	if ($new) {
		$c->db_do("UPDATE phpbb3_topics SET topic_first_post_id = ?, topic_first_poster_name = ? WHERE topic_id = ?", {}, $post_id, "Clans System", $topic) or die;
	}
	$c->db_do("UPDATE phpbb3_topics SET topic_last_post_id = ?, topic_last_post_time = ?, topic_last_post_subject = ?, topic_last_poster_id = ?, topic_last_poster_name = ?, topic_replies_real = topic_replies_real + 1, topic_replies = topic_replies + 1 WHERE topic_id = ?", {}, $post_id, $post_time, $title, 53, "Clans System", $topic) or die;
	$c->db_do("UPDATE phpbb3_forums SET forum_last_post_id = ?, forum_last_post_time = ?, forum_last_post_subject = ?, forum_last_poster_id = ?, forum_last_poster_name = ? WHERE forum_id = ?", {}, $post_id, $post_time, $topic_title, 53, "Clans System", $forum) or die;
}

sub forum_new_thread {
	my ($c, $forum, $title) = @_;
	if ($dryrun) {
		print "Asked to add a thread!\n";
		return 0;
	}
	$c->db_do("INSERT INTO phpbb3_topics SET forum_id = ?, topic_title = ?, topic_poster = ?, topic_time = ?", {}, $forum, $title, 53, $post_time) or die;
	return $c->lastid;
}

__DATA__
#!/bin/bash

cd /home/kgs/public_html
REQUEST_METHOD=GET REMOTE_USER=bucko QUERY_STRING='mode=all&delay=10' ./update.pl > /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR
cd /home/kgs
mysql < makegrids.sql >> /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR
mysql < update.sql >> /home/kgs/UPDATE.OUT 2>> /home/kgs/UPDATE.ERR
J=`mysql -se 'SELECT value-1 FROM options WHERE name = "BRAWLGAMES" AND clanperiod = (SELECT MAX(id) FROM clanperiods)'`
mysql -se 'SELECT id FROM clans WHERE clanperiod = (SELECT MAX(id) FROM clanperiods)'|while read I; do mysql -se 'SELECT MIN(time) FROM games LEFT OUTER JOIN members mb ON mb.id = black_id LEFT OUTER JOIN members mw ON mw.id = white_id WHERE mw.clan_id = '$I' OR mb.clan_id = '$I''|sed s/$/\ $I/; done|(while read I J; do echo "UPDATE clans SET got100time = $I WHERE id = $J;"; done)|mysql
if [ $(date +%w) -eq 1 ]; then # Sunday night's run; do summary
	perl summary.pl
#	mysql -se 'SELECT clans.id, clans.email FROM clans WHERE clanperiod = (SELECT MAX(id) FROM clanperiods) AND email IS NOT NULL'|\
	#while read I J; do
#		(
#			echo The following KGS usernames in your clan have not played games in
#			echo over two weeks! Please spur them on! Note that there may be two
#			echo or more user names from one player. This is normal.
#			echo
#			echo Usernames which do not play for 4 weeks will be removed. This is to
#			echo keep the update process from putting too much load on KGS\'s server.
#			echo You will receive an email letting you know when this happens.
#			echo
#			echo -
#			echo
#			mysql -se 'SELECT CONCAT(members.name, ": ", aliases.nick) FROM aliases INNER JOIN members ON members.id = aliases.member_id WHERE activity < UNIX_TIMESTAMP() - 60*60*24*7 AND members.clan_id = '$I';'|perl -pe 's/\n/ /'
#			echo
#			echo -
#			echo
#			echo The following have also yet to play a game within a week of being
#			echo added. Usernames which have played no games within 2 weeks of being
#			echo added will be automatically removed, and if the member has no games,
#			echo he will be completely removed from your clan. You will receive an
#			echo email letting you know if this happens.
#			echo
#			echo -
#			echo
#			mysql -se 'SELECT CONCAT(members.name, ": ", aliases.nick) FROM aliases INNER JOIN members ON members.id = aliases.member_id WHERE activity < UNIX_TIMESTAMP() - 60*60*24*7 AND members.clan_id = '$I' AND members.played = 0;'|perl -pe 's/\n/ /'
#			echo
#			echo -
#			echo
#		) | mail -s 'Inactive clan members' "$J"
#		$REMOVED
#	done
fi
dump1=/home/kgs/dbdump-"`date +%y%m%d-%H%M%S`".sql
mysqldump kgs > "$dump1"
mysqldump kgs aliases brawl clanperiods clans games members | gzip > /home/kgs/public_html/all.sql.gz
chmod 600 "$dump1"
