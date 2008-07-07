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
our $match_too_old_time = $start_time - 60*60*24*7;

# Get forum activity. This needs to be done bang on midnight.
our $period_info = $c->period_info();

my $lastvisit_results = $c->db_select("SELECT MAX(phpbb3_users.user_last_pageview), clans.id FROM phpbb3_users INNER JOIN phpbb3_user_group USING(user_id) INNER JOIN phpbb3_groups ON phpbb3_groups.group_id = phpbb3_user_group.group_id RIGHT OUTER JOIN clans ON clans.forum_leader_group_id = phpbb3_groups.group_id WHERE period_id = ? GROUP BY clans.id;", {}, $period_info->{id});
# Includes ban on Wu Tang's forum
#my $lastpost_results = $c->db_select("SELECT MAX(phpbb3_posts.post_time), clans.id FROM phpbb3_posts INNER JOIN phpbb3_users ON phpbb3_users.user_id = phpbb3_posts.poster_id NATURAL JOIN phpbb3_user_group NATURAL JOIN phpbb3_groups RIGHT OUTER JOIN clans ON clans.forum_group_id = phpbb3_groups.group_id WHERE period_id = ? AND phpbb3_posts.forum_id != 27 GROUP BY clans.id;", {}, $period_info->{id});
my $lastpost_results = $c->db_select("SELECT MAX(phpbb3_posts.post_time), clans.id FROM phpbb3_posts INNER JOIN phpbb3_users ON phpbb3_users.user_id = phpbb3_posts.poster_id INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN phpbb3_groups ON phpbb3_groups.group_id = phpbb3_user_group.group_id RIGHT OUTER JOIN clans ON clans.forum_group_id = phpbb3_groups.group_id WHERE period_id = ? GROUP BY clans.id;", {}, $period_info->{id});

my $group_duplicates = $c->db_select(qq|SELECT phpbb3_users.user_id, phpbb3_users.username, COUNT(phpbb3_user_group.group_id) AS total, GROUP_CONCAT(CONCAT(clans.name,"(",clans.id,")")) AS clans FROM phpbb3_users INNER JOIN phpbb3_user_group USING(user_id) INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_group_id AND clans.period_id = ? GROUP BY phpbb3_users.user_id HAVING total > 1|, {}, $period_info->{id});
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
	my $warn = $c->db_select("SELECT members.id, members.name, members.rank, MAX(activity) AS maxactivity FROM kgs_usernames INNER JOIN members ON members.id = kgs_usernames.member_id WHERE members.played = 0 AND members.clan_id = ? GROUP BY members.id HAVING maxactivity >= ? AND maxactivity < ?;", {}, $clan_id, $end_time - 60*60*24*7*2, $end_time - 60*60*24*7*1);
	# Inactive for two weeks or more; delete
	my $delete = $c->db_select("SELECT members.id, members.name, members.rank, MAX(activity) AS maxactivity FROM kgs_usernames INNER JOIN members ON members.id = kgs_usernames.member_id WHERE members.played = 0 AND members.clan_id = ? GROUP BY members.id HAVING maxactivity < ?", {}, $clan_id, $end_time - 60*60*24*7*2);

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
				$c->db_do("DELETE FROM kgs_usernames WHERE member_id = ?", {}, $_->[0]);
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

our %match_results;

sub match_summary {
	my ($clan_id) = @_;

	my $summary = '';

	my $challenges_too_old = $c->db_select("SELECT challenges.id, teams.name, clans.id, clans.name FROM challenges INNER JOIN teams ON challenger_team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE challenged_clan_id = ? AND challenge_date < ?", {}, $clan_id, $match_too_old_time);

	# Gets all unannounced matches. Calculates the winner in the SQL...
	my $match_results = $c->db_select("SELECT m.id, t1.name, t2.name, c2.id, c2.name, mt1.team_no, IF(SUM(s.winner=1)>SUM(s.winner=2),1,IF(SUM(s.winner=1)<SUM(s.winner=2),2,IF(MIN(s.seat_no+s.winner*0.5)%1=0.5,1,2))), m.winner, SUM(IF(s.winner IS NOT NULL,1,0)), start_date FROM team_matches m INNER JOIN team_match_seats s ON m.id = s.team_match_id LEFT OUTER JOIN brawl_prelim bp ON bp.team_match_id = m.id LEFT OUTER JOIN brawl b ON b.team_match_id = m.id INNER JOIN team_match_teams mt1 ON mt1.team_match_id = m.id INNER JOIN team_match_teams mt2 ON mt2.team_match_id = m.id AND mt2.team_id != mt1.team_id INNER JOIN teams t1 ON t1.id = mt1.team_id INNER JOIN teams t2 ON t2.id = mt2.team_id INNER JOIN clans c2 ON c2.id = t2.clan_id WHERE b.round IS NULL AND bp.for_position IS NULL AND t1.clan_id = ? GROUP BY m.id", {}, $clan_id);
	# Saves using a HAVING. Pull out only expired or otherwise finished matches.
	@$match_results = grep { $_->[8] == 5 || $_->[9] < $match_too_old_time } @$match_results;

	for(@$challenges_too_old) {
		$summary .= "A challenge from [i:$u]$_->[1]\[/i:$u] (".$c->render_clan($_->[2], $_->[3]).") was not answered within two weekly updates, so has expired with a penalty of 5 points.\n\n";
		if ($dryrun) {
			print "Removing five points from $clan_id.\n\n";
		} else {
			$c->db_do("UPDATE clans SET points = points - 5 WHERE id = ?", {}, $clan_id);
			$c->db_do("DELETE FROM challenges WHERE id = ?", {}, $_->[0]);
		}
	}
	
	for(@$match_results) {
		if (!$_->[6]) {
			$debugpost .= "Match $_->[0] has null result!?\n\n";
			next;
		} elsif ($_->[7] && $_->[6] != $_->[7]) {
			$debugpost .= "Match $_->[0] has uninferrable result!?\n\n";
			next;
		}
		my $res = $_->[6] == $_->[5] ? 'beat' : 'did not beat';
		$summary .= "The clan's team [i:$u]$_->[1]\[/i:$u] $res [i:$u]$_->[2]\[/i:$u] (".$c->render_clan($_->[3], $_->[4])."). ";
		$match_results{$_->[0]} = $_->[6];
		if ($_->[8] == 5) {
			$summary .= "Since this match was finished, the clan gets a 10 point bonus.\n\n";
			if ($dryrun) {
				print "Adding ten points to $clan_id.\n\n";
			} else {
				$c->db_do("UPDATE clans SET points = points + 10 WHERE id = ?", {}, $clan_id);
			}
		} else {
			$summary .= "Since this match was not finished, the clan gets a 5 point penalty.\n\n";
			if ($dryrun) {
				print "Removing five points from $clan_id.\n\n";
			} else {
				$c->db_do("UPDATE clans SET points = points - 5 WHERE id = ?", {}, $clan_id);
			}
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

my ($results) = $c->db_select('SELECT id, name, forum_id FROM clans WHERE forum_id IS NOT NULL AND period_id = ?', {}, $period_info->{id});
for(@$results) {
	my $summary = "Summary for ".$c->render_clan($_->[0], $_->[1])." for the period ".strftime("%d/%m/%y", gmtime $start_time)." to ".strftime("%d/%m/%y", gmtime $end_time).":\n\n".game_summary($_->[0]).inactive_new_members($_->[0]).forum_activity($_->[0]).match_summary($_->[0]).check_groups($_->[0]);
	if ($dryrun) {
		print qq|Posting to "Clan Game Summary" with message:\n\n$summary\n\n|;
	} else {
		$c->forum_post_or_reply($_->[2], "Clan Game Summary", "Clan Game Summary, ".strftime("%d/%m/%y", gmtime $end_time), $summary, $u, $post_time);
	}
}

for my $match_id (keys %match_results) {
	my $result = $match_results{$match_id};
	$c->db_do("UPDATE team_matches SET winner=?, result_announced=1 WHERE id=?", {}, $result, $match_id);
}

my ($clanresults) = $c->db_select("SELECT clans.id, clans.name, SUM(active.total) AS total FROM clans LEFT OUTER JOIN (SELECT DISTINCT mw.clan_id AS clan_id, COUNT(games.id) AS total FROM games INNER JOIN members mw ON white_id = mw.id WHERE time > ? AND time <= ? GROUP BY mw.clan_id UNION ALL SELECT mb.clan_id AS clan_id, COUNT(games.id) AS total FROM games INNER JOIN members mb ON black_id = mb.id WHERE time > ? AND time <= ? GROUP BY mb.clan_id) active ON clans.id = active.clan_id WHERE period_id = ? GROUP BY clans.id ORDER BY total DESC, clans.tag;", {}, $start_time, $end_time, $start_time, $end_time, $period_info->{id});

my $clansummary = "";
my $ispositive;
for(@$clanresults) {
	if ($_->[2]) {
		if (!defined $ispositive) {
			$clansummary .= "Game summary for all clans for the period ".strftime("%d/%m/%y", gmtime $start_time)." to ".strftime("%d/%m/%y", gmtime $end_time).":[list:$u]\n\n";
		} 
		$ispositive = 1;
		$clansummary .= "[*:$u] ".$c->render_clan($_->[0], $_->[1])." played ".($_->[2] == 1 ? "[b:$u]1[/b:$u] game" : "[b:$u]".$_->[2]."[/b:$u] games").".[/*:m:$u]\n";
	} else {
		if ($ispositive) {
			$clansummary .= "[/list:u:$u]\n\n";
		}
		if (!defined $ispositive) {
			$clansummary .= "The following clans played no games: ";
		}
		$ispositive = 0;
		$clansummary .= $c->render_clan($_->[0], $_->[1]).($_->[0] == $clanresults->[$#$clanresults][0] ? ".\n" : ", ");
	}
}
$clansummary .= "[/list:u:$u]\n" if $ispositive;

if ($dryrun) {
	print qq|Posting to public "Clan Game Summary" with message:\n\n$clansummary\n\n|;
	print qq|Posting to "Clan Game Debug" with message:\n\n$debugpost\n\n|;
} else {
	$c->forum_post_or_reply(1, "Clan Game Summary", "Clan Game Summary, ".strftime("%d/%m/%y", gmtime $end_time), $clansummary, $u);
	$c->forum_post_or_reply(21, "Clan Game Debug", "Clan Game Debug, ".strftime("%d/%m/%y", gmtime $end_time), $debugpost, $u);
}
