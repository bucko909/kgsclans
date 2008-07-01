#!/usr/bin/perl
use strict;
use warnings;
use Time::Local;
use POSIX qw/strftime/;
use LWP::UserAgent;
use Clans;

$ENV{HOME} = "/home/kgs";

our $c = Clans->new;
$c->header("Updater");

our $delay = $c->param('delay');
$delay = 10 if !$delay || $delay < 10;

our ($lwp_response, $page_fail);

$|=1; # Turn off output buffering.

my $period_info = $c->period_info;
our ($periodid, $starttime, $endtime) = ($period_info->{id}, $period_info->{startdate}, $period_info->{enddate});
our ($csec, $cmin, $chr, $cday, $cmon, $cyear) = gmtime();
$cyear += 1900;

our $reqpoints = $c->get_option('BRAWLPOINTS');
our $reqgames = $c->get_option('BRAWLGAMES');
our $reqpure = $c->get_option('BRAWLPURE');

if (!defined $reqpoints) {
	print "Unknown number of points required...\n";
	$reqpoints = 2500;
} elsif ($reqpoints == 0) {
	print "No points required...\n";
}

if (!defined $reqgames) {
	print "Unknown number of games required...\n";
	$reqgames = 1000;
} elsif ($reqpoints == 0) {
	print "No games required...\n";
}

if (!defined $reqpure) {
	print "Unknown number of pure games required...\n";
	$reqpure = 500;
} elsif ($reqpure == 0) {
	print "No pure games required...\n";
}

# Assume every new alias started playing games at the start of the
# clan period
our $deftime = $starttime;

# ======================
# Decide what to update!
# ======================

my $mode = $c->param('mode') || "all";

my @games;
our ($uclan, $umember, $uall) = (0, 0, undef);
if ($mode eq 'all') {
	$delay = $delay || 10;
	if ($ENV{REMOTE_USER} ne 'bucko') {
		print $c->p("Sorry, only an administrator (ie. bucko) can do that!\n");
		print $c->footer;
		exit;
	}
	@games = allgames();
	$uall = 1;
} elsif ($mode eq 'clan') {
	$delay = $delay || 10;
	if ($ENV{REMOTE_USER} ne 'bucko') {
		print $c->p("Sorry, only an administrator (ie. bucko) can do that!\n");
		print $c->footer;
		exit;
	}
	my $clan = $c->db_selectrow("SELECT id, name, regex FROM clans WHERE id = ? AND period_id = ?", {}, $c->param('id'), $periodid);
	$uclan = $clan->[0];
	if ($clan) {
		@games = clangames($clan);
	} else {
		print $c->p("Invalid clan ID: ".$c->param('id'));
	}
} elsif ($mode eq 'member') {
	my $member = $c->db_selectrow("SELECT members.id, members.name FROM members INNER JOIN clans ON clans.id = members.clan_id WHERE members.id = ? AND period_id = ?", {}, $c->param('id'), $periodid);
	$umember = $member->[0];
	if ($member) {
		@games = membergames($member);
	} else {
		print $c->p("Invalid member ID: ".$c->param('id'));
	}
} elsif ($mode eq 'game') {
	my $game = $c->db_selectrow("SELECT url, time, id, white_id, black_id FROM games WHERE id = ? AND time >= ? AND time < ?", {}, $c->param('id'), $starttime, $endtime);
	if ($game) {
		@games = ($game);
	} else {
		print $c->p("Invalid game ID: ".$c->param('id'));
	}
}

@games = sort { $a->[1] <=> $b->[1] } @games;
print $c->p("I have ".scalar(@games)." game(s) to investigate.\n");

# For each potentially new game, run the game parser on it.
foreach my $game (@games) {
	parsegame(@$game);
}

$c->footer;


# =================================================
# Helper routines to bulk update many KGS Usernames
# =================================================

sub allgames {
	my $kgs_usernames = $c->db_select("SELECT id, nick, lastgame, lastupdate FROM kgs_usernames WHERE period_id = ? ORDER BY lastupdate ASC", {}, $periodid);
	my @update;
	foreach my $alias (@$kgs_usernames) {
		push @update, aliasgames($alias);
	}
	return @update;
	#my $clans = $c->db_select("SELECT id, name, regex FROM clans WHERE period_id = ?", {}, $periodid);
	#my @update;
	#foreach my $clan (@$clans) {
	#	push @update, clangames($clan);
	#}
	#return @update;
}

sub clangames {
	my $clan = $_[0];
	print $c->p("Updating clan $clan->[1] ($clan->[0]).\n");
	my $members = $c->db_select("SELECT id, name FROM members WHERE clan_id = ?", {}, $clan->[0]);
	my @update;
	foreach my $member (@$members) {
		push @update, membergames($member);
	}
	return @update;
}

sub membergames {
	my $member = $_[0];
	print $c->p("Updating member $member->[1] ($member->[0]).\n");
	my $kgs_usernames = $c->db_select("SELECT id, nick, lastgame, lastupdate FROM kgs_usernames WHERE member_id = ? AND period_id = ?", {}, $member->[0], $periodid);
	my @update;
	foreach my $alias (@$kgs_usernames) {
		push @update, aliasgames($alias);
	}
	return @update;
}

# =================================
# Update an individual KGS Username
# =================================

sub aliasgames {
	my $alias = $_[0];
	print $c->p("Updating KGS user name $alias->[1].\n");
	my $rank;

	# Has the user been updated recently?
	my $time = $alias->[2] || $deftime;
	if (time() - ($alias->[3] || 0) < 3600 && $ENV{REMOTE_USER} ne 'bucko') {
		print $c->p("Alias $alias->[1] was updated too recently; skipping.\n");
		return;
	}

	# Convert time to a format we can plug into the archives.
	my ($sec,$min,$hr,$day,$mon,$year) = gmtime $time;
	$year += 1900;

	# Now get a list of all games spanning all months since the last update.
	# We go back 5 hours before the last game in case we missed an ongoing
	# game.
	undef $page_fail;
	my @games;
	while(($year < $cyear) || ($year == $cyear && $mon <= $cmon)) {
		push @games, getnewgames($year, $mon + 1, $alias->[1], $time - 3600 * 5, \$rank);
		# In case a game was playing during prev update, subtract 5 hours.
		$mon++;
		if ($mon>11) {
			$mon = 0;
			$year++;
		}
	}
	# Finally, use the rank we found from the system to update the alias.
	if ($page_fail) {
		$c->db_do("UPDATE kgs_usernames SET lastupdate = ? WHERE id = ?", {}, time(), $alias->[0]);
	} else {
		$c->db_do("UPDATE kgs_usernames SET rank = ?, lastupdate = ? WHERE id = ?", {}, $rank, time(), $alias->[0]);
	}
	
	return @games;
}

# ====================================================================
# Get a list of games from the KGS Archives page of a given user/month
# ====================================================================

# $time is the time of the oldest game to include. $rankref will be updated
# with the most recent rank.

sub getnewgames {
	my ($year, $month, $user, $time, $rankref) = @_;
	print $c->p("Getting page http://www.gokgs.com/gameArchives.jsp?user=$user&year=$year&month=$month...\n");
	$_ = get("http://www.gokgs.com/gameArchives.jsp?user=$user&year=$year&month=$month");
	if (!$_) {
		print $c->p("Failed to get page: ".$lwp_response->status_line);
		$page_fail = 1;
		sleep($delay) if $delay;
		return;
	}
	sleep($delay) if $delay;
	my @games;
	my $first = 1;
	while (
		m#<tr><td><a href="([^"]*)">Yes</a></td><td><a[^>]*>(\S+(?:\s+\[\S+\])?)(?:</a><br/?><a[^>]*>(\S+(?:\s+\[\S+\])?))?</a></td><td><a[^>]*>(\S+(?:\s+\[\S+\])?)(?:</a><br/?><a[^>]*>(\S+(?:\s+\[\S+\])?))?</a></td><td>19[^<]*19[^<]*</td><td>(\d+)/(\d+)/(\d+)\s+(\d+):(\d+)\s+([AP])M</td><td>(?:Free|Ranked|Simul|Rengo)</td><td>([BW])\+[^<]*?</td></tr>#gs) {
		# Order:
		# URL
		# W player 1
		# (W player 2)
		# B player 1
		# (B player 2)
		# D
		# M
		# Y
		# H
		# M
		# AM/PM
		# Winner
		#print $c->p("Test: $1 $2 $3 $4 $5 $6 $7 $8 $9 $10\n");
		my $ctime = timeval($6,$7,$8,$9,$10,$11);

		my $url = $1;
		my $quser = quotemeta $user;
		my ($white, $black);
		if ($3 && ($3 =~ /$quser/i || $5 =~ /$quser/i)) {
			($white, $black) = ($3, $5);
			$url .= '?rengo2';
		} else {
			($white, $black) = ($2, $4);
			$url .= '?rengo1' if $3;
		}
		my $won = $12;
		my ($wrank, $brank);
		$wrank = rank($1) if $white =~ s/\s+\[(.*)\]//;
		$brank = rank($1) if $black =~ s/\s+\[(.*)\]//;

		$$rankref = lc $user eq lc $white ? $wrank : $brank if $first;
		undef $first;

		if ($ctime < $time) {
			print $c->p("Discarding $url (and anything after) since it's dated before update threshold (".strftime("%H:%M %d/%m/%Y", gmtime $time).").\n");
			last;
		}

		if ($ctime < $starttime) {
			print $c->p("Discarding $url (and anything after) since it's dated before the clan period starts (".strftime("%H:%M %d/%m/%Y", gmtime $starttime).").\n");
			last;
		}

		if ($ctime > $endtime) {
			print $c->p("Discarding $url since it's dated after the clan period ends (".strftime("%H:%M %d/%m/%Y", gmtime $endtime).").\n");
			next;
		}

		push @games, [ $url, $ctime ];

		my $a = $games[$#games];

		print $c->p("Potential new clan game: $url - ".strftime("%H:%M %d/%m/%Y", gmtime $ctime)."\n");
	}
	return @games;
}

# Convert kyu / dan into decimal rank.
sub rank {
	return $1 if $_[0] =~ /(\d+)k/i;
	return 1 - $1 if $_[0] =~ /(\d+)d/i;
	return;
}

# =========================================================================
# Investigate a game found in the archives to establish if it's a clan game
# =========================================================================

sub parsegame {
	my ($url, $time, $gameid, $old_whiteid, $old_blackid) = @_;

	print $c->p("Investigating game: $url\n");

	# If we are without a game ID, we are adding a new game, so we don't want
	# the game to be in the database.
	my $newid;
	if (!$gameid) {
		# Only check if the game isn't being /re/ parsed...
		my $result = $c->db_selectone("SELECT id FROM games WHERE url = ?", {}, $url);
		if ($result) {
			# Error message not really an error.
			print $c->p("I've already seen this game...\n");
			return;
		} else {
			# We should immediately insert a placeholder
			if (!$c->db_do("INSERT INTO games VALUES(NULL, ?, ?, '', '', NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL)", {}, $url, $time)) {
				print $c->p("<b>Error adding game placeholder: ".DBI->errstr."</b>\n");
				return;
			}
			$newid = $c->lastid;
		}
	}

	my $sgf = get($url);
	sleep(1) if $delay; # Don't need to wait 10 secs for these...

	my $rengo;
	$rengo = $1 if ($url =~ /\?rengo(\d)$/);

	# Get all of the info we're interested in out of the SGF file.
	my $komi = 0;
	$komi = $1 if ($sgf =~ /KM\[(-?\d+(?:\.\d+)?)\]/);
	my $handi = 0;
	$handi = $1 if ($sgf =~ /HA\[(\d+)\]/);
	$handi = 1 if $handi == 0 && $komi < 1;
	my $white = 'unknown';
	if (!$rengo) {
		$white = $1 if ($sgf =~ /PW\[([^\]]+)\]/);
	} else {
		$white = ($rengo == 1 ? $1 : $2) if ($sgf =~ /PW\[([^\]]+),([^\]]+)\]/);
	}
	my $black = 'unknown';
	if (!$rengo) {
		$black = $1 if ($sgf =~ /PB\[([^\]]+)\]/);
	} else {
		$black = ($rengo == 1 ? $1 : $2) if ($sgf =~ /PB\[([^\]]+),([^\]]+)\]/);
	}
	my (@white_decision, @black_decision);
	my ($result, $result_by) = (0, "Unknown");
	if ($sgf =~ /RE\[([^\]]+)\]/) {
		my $temp = $1;
		if (lc $temp eq 'jigo') {
			$result = 0;
		} elsif ($temp =~ /([BW])+(.*)/) {
			$result = ($1 eq 'B') ? 1 : -1;
			$result_by = $2;
		}
	}
	my ($white_id, $wregex, $wclan, $walias_id) = player_info($white);
	my ($black_id, $bregex, $bclan, $balias_id) = player_info($black);

	# Do the decision making now. @x_decision holds reasons for each player.

	push @white_decision, "NOCLAN" if !$white_id;
	push @black_decision, "NOCLAN" if !$black_id;

	my $rules = "";
	#if ($sgf !~ /RU\[Japanese\]/) {
	if ($sgf =~ /RU\[([^\]]+)\]/) {
#		print $c->p("Not a clan game: Bad ruleset.\n");
#		push @white_decision, "BADRULES";
#		push @black_decision, "BADRULES";
		$rules .= "RU[$1]";
	}
	if ($sgf !~ /SZ\[19\]/) {
		print $c->p("Not a clan game: Bad board size.\n");
		push @white_decision, "BADSIZE";
		push @black_decision, "BADSIZE";
	}
	#if ($sgf !~ /TM\[300\]OT\[5x10 byo-yomi\]/ && $sgf !~ /TM\[1200\]OT\[5x30 byo-yomi\]/ ) {
	if ($sgf =~ /TM\[([^\]]+)\]/) {
		$rules .= "TM[$1]";
	}
	if ($sgf =~ /OT\[([^\]]+)\]/ ) {
#		print $c->p("Not a clan game: Bad time settings.\n");
#		push @white_decision, "BADTIME";
#		push @black_decision, "BADTIME";
		$rules .= "OT[$1]";
	}
	print $c->p("Fits clan settings.\n") if (!@white_decision || !@black_decision);

	#my @shit = ($sgf =~ /([BW]L\[\d+(?:\.\d+)?\])/g);
	my @shit = ($sgf =~ /(\b[BW]\[[a-z][a-z]\])/g);
	my $moves = @shit;
	if ($moves < 30) {
		print $c->p("Not a clan game: Only $moves moves (needs 30).\n");
		push @white_decision, "TOOSHORT";
		push @black_decision, "TOOSHORT";
	}

	if ($white_id && $black_id && $bregex eq $wregex) {
		print $c->p("Not a clan game; W and B are in the same clan!\n");
		push @white_decision, "SAMECLAN";
		push @black_decision, "SAMECLAN";
	}

	# Check clan tags were said for both players

	if ($white_id) {
		my $moves = is_clan($sgf, $white, $wregex);
		if (!defined $moves) {
			print $c->p("Is not a clan game for $white: No clan tag.\n");
			push @white_decision, "NOTAG";
		} elsif ($moves > 10) {
			print $c->p("Is not a clan game for $white: Tag said too late (after move $moves).\n");
			push @white_decision, "LATETAG";
		} else {
			print $c->p("Tag OK: Said after move $moves.\n");
		}
	}
	if ($black_id) {
		my $moves = is_clan($sgf, $black, $bregex);
		if (!defined $moves) {
			print $c->p("Is not a clan game for $black: No clan tag.\n");
			push @black_decision, "NOTAG";
		} elsif ($moves > 10) {
			print $c->p("Is not a clan game for $black: Tag said too late (after move $moves).\n");
			push @black_decision, "LATETAG";
		} else {
			print $c->p("Tag OK: Said after move $moves.\n");
		}
	}

	# Now perform the necessary database updates.
	# Note that the system will add games to players if they didn't belong
	# to them before, but never retroactively remove them. I'm not sure if
	# this is good.

	undef $black_id if @black_decision;
	undef $white_id if @white_decision;

	my $black_qualified = $black_id ? $c->db_selectone("SELECT got100time FROM clans WHERE id=?", {}, $bclan) : undef;
	my $white_qualified = $white_id ? $c->db_selectone("SELECT got100time FROM clans WHERE id=?", {}, $wclan) : undef;
	if ($black_id && !@black_decision) {
		print $c->p("Is a clan game for $black.\n");
		if ($gameid && $old_blackid) {
			print $c->p("But was already recorded as such.\n");
		} else {
			if (!$c->db_do("UPDATE members SET won = won + ?, played = played + 1 WHERE id = ?", {}, $result == 1 ? 1 : 0, $black_id)) {
				print $c->p("<b>Error adding B result: ".DBI->errstr."</b>\n");
			}
		}
		if (!$c->db_do("UPDATE kgs_usernames SET activity = IF(? > activity, ?, activity) WHERE nick = ?", {}, $time, $time, $black)) {
			print $c->p("<b>Error updating B activity: ".DBI->errstr."</b>\n");
		}
		if (!$c->db_do("UPDATE clans SET points = points + 1 WHERE id = ?", {}, $bclan)) {
			print $c->p("<b>Error adding B clan result: ".DBI->errstr."</b>\n");
		}
	}
	if (!@white_decision) {
		print $c->p("Is a clan game for $white.\n");
		if ($gameid && $old_whiteid) {
			print $c->p("But was already recorded as such.\n");
		} else {
			if (!$c->db_do("UPDATE members SET won = won + ?, played = played + 1 WHERE id = ?", {}, $result == -1 ? 1 : 0, $white_id)) {
				print $c->p("<b>Error adding W result: ".DBI->errstr."</b>\n");
			}
		}
		if (!$c->db_do("UPDATE kgs_usernames SET activity = IF(? > activity, ?, activity) WHERE nick = ?", {}, $time, $time, $white)) {
			print $c->p("<b>Error updating W activity: ".DBI->errstr."</b>\n");
		}
		if (!$c->db_do("UPDATE clans SET points = points + 1 WHERE id = ?", {}, $wclan)) {
			print $c->p("<b>Error adding W clan result: ".DBI->errstr."</b>\n");
		}
	}
	if (!@white_decision && !@black_decision) {
		print $c->p("Is a pure clan game for $black and $white.\n");
		if ($gameid && $old_blackid && $old_whiteid) {
			print $c->p("But was already recorded as such.\n");
		} else {
			if (!$c->db_do("UPDATE members SET won_pure = won_pure + ?, played_pure = played_pure + 1 WHERE id = ?", {}, $result == 1 ? 1 : 0, $black_id)) {
				print $c->p("<b>Error adding B result: ".DBI->errstr."</b>\n");
			}
			if (!$c->db_do("UPDATE members SET won_pure = won_pure + ?, played_pure = played_pure + 1 WHERE id = ?", {}, $result == -1 ? 1 : 0, $white_id)) {
				print $c->p("<b>Error adding W result: ".DBI->errstr."</b>\n");
			}
			if (!$c->db_do("UPDATE clans SET points = points + 1 WHERE id = ? OR id = ?", {}, $wclan, $bclan)) {
				print $c->p("<b>Error adding pure clan result: ".DBI->errstr."</b>\n");
			}
		}
	}

	# Insert into games and update users.
	if (!$gameid) {
		# We already have a placeholder
		if (!$c->db_do("UPDATE games SET time=?, white=?, black=?, white_id=?, black_id=?, result=?, result_by=?, komi=?, handicap=?, white_decision=?, black_decision=?, ruleset=?, moves=? WHERE id=?", {}, $time, $white, $black, (@white_decision ? undef : $white_id), (@black_decision ? undef : $black_id), $result, $result_by, $komi, $handi, join(',',@white_decision), join(',',@black_decision), $rules, $moves, $newid)) {
			print $c->p("<b>Error adding game: ".DBI->errstr."</b>\n");
		}

		# Let the system know we've updated the user for this game.
		# Note that if we execute the statement, this game is guaranteed to be
		# more recent than lastgame.
		if ($white_id && ($wclan == $uclan || $white_id == $umember || $uall)) {
			if (!$c->db_do("UPDATE kgs_usernames SET lastgame = ? WHERE id = ?", {}, $time, $walias_id)) {
				print $c->p("<b>Error updating alias time for white.</b>\n");
			}
		}
		if ($black_id && ($bclan == $uclan || $black_id == $umember || $uall)) {
			if (!$c->db_do("UPDATE kgs_usernames SET lastgame = ? WHERE id = ?", {}, $time, $balias_id)) {
				print $c->p("<b>Error updating alias time for black.</b>\n");
			}
		}
	} else {
		if (!$c->db_do("UPDATE games SET white_id = ?, black_id = ?, white_decision = ?, black_decision = ? WHERE id = ?", {}, (@white_decision ? undef : $white_id), (@black_decision ? undef : $black_id), join(',',@white_decision), join(',',@black_decision), $gameid)) {
			print $c->p("<b>Error updating game: ".DBI->errstr."</b>\n");
		}
	}


	# Brawl qualification checks
	if (!$black_qualified && !@black_decision) {
		my $points = $c->db_selectone("SELECT points FROM clans WHERE id=?", {}, $bclan);
		my $games = $c->db_selectone("SELECT SUM(played) FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.id=?", {}, $bclan);
		my $pure = $c->db_selectone("SELECT SUM(played_pure) FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.id=?", {}, $bclan);
		if ($points >= $reqpoints && $games >= $reqgames && $pure >= $reqpure) {
			if (!$c->db_do("UPDATE clans SET got100time = ? WHERE id=?", {}, $time, $bclan)) {
				print $c->p("<b>Error updating clan brawl requirement time.</b>\n");
			}
		}
	}
	if (!$white_qualified && !@white_decision) {
		my $points = $c->db_selectone("SELECT points FROM clans WHERE id=?", {}, $wclan);
		my $games = $c->db_selectone("SELECT SUM(played) FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.id=?", {}, $wclan);
		my $pure = $c->db_selectone("SELECT SUM(played_pure) FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.id=?", {}, $wclan);
		if ($points >= $reqpoints && $games >= $reqgames && $pure >= $reqpure) {
			if (!$c->db_do("UPDATE clans SET got100time = ? WHERE id=?", {}, $time, $wclan)) {
				print $c->p("<b>Error updating clan brawl requirement time.</b>\n");
			}
		}
	}
}

# Ensure that the clan tag was said; returns moves before tag or undef.

sub is_clan {
	my ($sgf, $nick, $regex) = @_;
	my $cnick = quotemeta $nick;
	if ($sgf =~ /^(.*?)$cnick\s+\[[^\\]*\\\]:[^\n]*\b(?i:$regex)\b/s) {
		#my @shit = ($1 =~ /([BW]L\[\d+(?:\.\d+)?\])/g);
		my @shit = ($1 =~ /(\b[BW]\[[a-z][a-z]\])/g);
		my $moves = @shit;
		return $moves;
	}
	return;
}

sub player_info {
	my $res = $c->db_select("SELECT member_id, regex, clans.id, kgs_usernames.id FROM clans INNER JOIN members ON members.clan_id = clans.id INNER JOIN kgs_usernames ON kgs_usernames.member_id = members.id WHERE kgs_usernames.nick = ? AND kgs_usernames.period_id = ?", {}, $_[0], $periodid);
	if ($res && @$res) {
		return @{$res->[0]};
	}
	return ();
}

sub timeval {
	my ($mo, $d, $y, $h, $mi, $p) = ($_[0] - 1, $_[1], $_[2]+2000, $_[3], $_[4], $_[5] eq 'P');
	if ($p && $h < 12) {
		$h += 12;
	} elsif (!$p && $h == 12) {
		$h = 0;
	}
	return timegm(0, $mi, $h, $d, $mo, $y);
}

sub get {
	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);
	$ua->env_proxy;

	$lwp_response = $ua->get($_[0]);

	if ($lwp_response->is_success) {
		return $lwp_response->content;  # or whatever
	}
	return undef;
}
