#!/usr/bin/perl

use strict;
use warnings;
use Clans;
use LWP::Simple;
use POSIX qw/strftime/;
use Carp qw/cluck/;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = Clans->new;
my $sess = $c->getsession;

# Fetch clan period
my $periodid = $c->param('period');
my $periodspecified = $periodid ? 1 : 0;
$periodid ||= $c->getperiod;
my $periodprep = $periodspecified ? "period=$periodid&amp;" : "";

my $isadmin = 0;
foreach my $groupid (@{$c->{phpbbsess}{groupids}}) {
	$isadmin = 1 if $groupid == 2;
}

$c->header("Brawl");

my $gameguessing;

if ($c->param('mode') && $isadmin) {
	my $round = $c->param('round');
	my $position = $c->param('position');
	my $seat = $c->param('seat');
	if ($c->param('mode') eq 'url') {
		$c->db_do("UPDATE brawldraw_results SET url=? WHERE clanperiod=? AND round=? AND position=? AND seat=?", {}, $c->param('url'), $periodid, $round, $position, $seat);
	} elsif ($c->param('mode') eq 'win') {
		$c->db_do("UPDATE brawldraw_results SET result=1 WHERE clanperiod=? AND round=? AND position=? AND seat=?", {}, $periodid, $round, $position, $seat);
		# Has the clan now won?
		my $wins = $c->db_selectrow("SELECT COUNT(*), MAX(clan_id), MAX(team_id) FROM brawldraw_results INNER JOIN brawldraw ON brawldraw.clanperiod = brawldraw_results.clanperiod AND brawldraw.round = brawldraw_results.round AND brawldraw.position = brawldraw_results.position WHERE brawldraw_results.clanperiod=? AND brawldraw_results.round=? AND brawldraw_results.position=? AND result = 1", {}, $periodid, $round, $position);
		if ($wins && $wins->[0] == 3) { # == 3 so it only happens once...
			print "<p>Team won!</p>";
			&teamwon($periodid, $round, $position, $wins->[2]);
		}

		my $position = 2 * int($position / 2) + ($position + 1) % 2;
		$c->db_do("UPDATE brawldraw_results SET result=0 WHERE clanperiod=? AND round=? AND position=? AND seat=?", {}, $periodid, $round, $position, $seat);
		# Can't move from undecided->win from losing a game, so no need to
		# do anything here.
	} elsif ($c->param('mode') eq 'guess') {
		$gameguessing = 1;
	}
}

sub teamwon {
	my ($periodid, $round, $position, $teamid) = @_;
	my $newpos = int($position/2);
	my $otherpos = 2 * $newpos + ($position + 1) % 2;
	$c->db_do("UPDATE brawldraw SET nextround_pos=? WHERE clanperiod=? AND round=? AND position=?", {}, $newpos, $periodid, $round, $position);
	$c->db_do("UPDATE brawldraw SET nextround_pos=-1 WHERE clanperiod=? AND round=? AND position=?", {}, $periodid, $round, $otherpos);
	$c->db_do("REPLACE INTO brawldraw SET clanperiod=?, round=?, position=?, team_id=?", {}, $periodid, $round+1, $newpos, $teamid);
#	$c->db_do("INSERT INTO brawldraw_results SELECT 3, 0, brawldraw.position, brawl.position-1, brawl.member_id, (brawldraw.position + brawl.position) % 2, NULL, NULL FROM brawldraw INNER JOIN brawl ON brawldraw.clan_id = brawl.clan_id INNER JOIN clans ON clans.id = brawl.clan_id WHERE clans.clanperiod = 3 AND brawl.position <= 5;"
	$c->db_do("REPLACE INTO brawldraw_results SELECT ?, ?, ?, brawl.position-1, brawl.member_id, (? + brawl.position) % 2, NULL, NULL FROM brawl WHERE team_id = ?", {}, $periodid, $round+1, $newpos, $newpos, $teamid);
}

my $brawldraw = $c->db_select("SELECT round, position, brawl_teams.team_id, brawl_teams.name, clans.id, clans.name, nextround_pos FROM brawldraw INNER JOIN brawl_teams ON brawldraw.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE brawldraw.clanperiod = ?", {}, $periodid);
if (@$brawldraw) {
	print $c->h3("Results");

	# First, we need the results.
	my $brawldraw_results = $c->db_select("SELECT round, position, seat, member_id, members.name, members.rank, is_black, result, url FROM brawldraw_results INNER JOIN members ON member_id = members.id WHERE clanperiod = ?", {}, $periodid);

	# Let's process the results into a sensible 3-dim array.
	my @results;
	foreach(@$brawldraw_results) {
		$results[$_->[0]] ||= [];
		$results[$_->[0]][$_->[1]] ||= [];
		$results[$_->[0]][$_->[1]][$_->[2]] = $_;
	}

	# And similar for the draw
	my @draw;
	foreach(@$brawldraw) {
		$draw[$_->[0]] ||= [];
		$draw[$_->[0]][$_->[1]] = $_;
	}

	foreach my $round (0..$#draw) {
		print $c->h4("Round ".($round + 1));
		my @rounddraw = @{$draw[$round]};
		my @roundresults = @{$results[$round] || []};
		foreach my $position (0..$#rounddraw) {
			my $clan = $c->renderclan($rounddraw[$position][4], $rounddraw[$position][5]);
			my $team = $clan.($rounddraw[$position][3] ? " ($rounddraw[$position][3])" : "");
			if ($position % 2 == 1 && (!$rounddraw[$position][2] || !$rounddraw[$position-1][2])) {
				next;
			} elsif ($position % 2 == 0 && !$rounddraw[$position][2]) {
				if (!$rounddraw[$position+1][2]) {
					# WTF?!
					next;
				}
				my $clan = $c->renderclan($rounddraw[$position+1][4], $rounddraw[$position+1][5]);
				my $team = $clan.($rounddraw[$position+1][3] ? "($rounddraw[$position+1][3])" : "");
				print $c->p("Team $team has no opponent.");
				next;
			} elsif ($position % 2 == 0 && !$rounddraw[$position+1][2]) {
				print $c->p("Team $team has no opponent.");
				next;
			}
			my $class = defined $rounddraw[$position][6] ? "clan_".($rounddraw[$position][6] > -1 ? "won" : "lost") : "unplayed";
			if ($position % 2 == 0) {
				print "<table class=\"brawldraw\">";
				print "<tr><td colspan=\"5\" class=\"$class\">$team</td></tr>";
			}
			my $rowclass = $position % 2 ? "players_bottom" : "players_top";
			print "<tr class=\"$rowclass\">";
			my @games = @{$roundresults[$position]};
			foreach my $seat (0..4) {
				my $class = ($games[$seat][6] ? "player_black" : "player_white")." ".(defined $games[$seat][7] ? ($games[$seat][7] ? "player_won" : "player_lost") : "player_unplayed");
				print "<td class=\"$class\">";
				print $c->rendermember($games[$seat][3], $games[$seat][4], $games[$seat][5]);
				print qq| [<a href="?$periodprep|.qq|mode=win&amp;round=$round&amp;position=$position&amp;seat=$seat&amp;">win</a>]| if $isadmin and !defined $games[$seat][7];
				print "</td>";
			}
			print "</tr>";
			if ($position % 2) {
				print "<tr><td colspan=\"5\" class=\"$class\">$team</td></tr>";
				print "</table><br/><br/>";
			} else {
				# Games, too!
				print "<tr class=\"games\">";
				foreach my $seat (0..4) {
					print "<td>";
					if ($games[$seat][8]) {
						if ($games[$seat][8] =~ /^http/) {
							print "(<a href=\"".$c->escapeHTML($games[$seat][8])."\">Game</a>)";
						} else {
							print "(Default)";
						}
					} else {
						if ($isadmin) {
							my $url = "";
							if ($gameguessing) {
								my $i = -1;
								my @timevals = gmtime();
								#3, 4, 5 = d/m/y
								my $year = $timevals[5] + 1900;
								my $month = $timevals[4] + 1;
								my $day = $timevals[3];
								my $index = 1;
								my $basepos = 2*int($position/2);
								my $wadd = ($seat+1) % 2;
								my $badd = $seat % 2;
								my $black = $roundresults[$basepos+$badd][$seat][4];
								my $white = $roundresults[$basepos+$wadd][$seat][4];
								while(1) {
									my $turl;
									if ($index == 1) {
										$turl = "http://files.gokgs.com/games/$year/$month/$day/$white-$black.sgf";
									} else {
										$turl = "http://files.gokgs.com/games/$year/$month/$day/$white-$black-$index.sgf";
									}
									last unless head($turl);
									$index = $index + 1;
									$url = $turl;
								}
								undef $url unless $index > 1;
							}
							print qq|<form method="post" action="brawl.pl">|;
							print qq|<input type="text" name="url" value="$url"/>|;
							print qq|<input type="hidden" name="mode" value="url"/>|;
							print qq|<input type="hidden" name="period" value="$periodid"/>| if $periodspecified;
							print qq|<input type="hidden" name="round" value="$round"/>|;
							print qq|<input type="hidden" name="position" value="$position"/>|;
							print qq|<input type="hidden" name="seat" value="$seat"/>|;
							print qq|<input type="submit" name="submit" value="OK"/>|;
							print qq|</form>|;
						}
					}
					print "</td>";
				}
				print "</tr>";
			}
		}
	}
} else {
	print $c->h3("Teams");
	my $info = $c->db_select("SELECT clans.id AS id, clans.name AS name, GROUP_CONCAT(CONCAT(position,',',mb.id,',',mb.name,',',IF(mb.rank IS NULL,'',mb.rank),',',mb.played) ORDER BY brawl.position ASC SEPARATOR ';') FROM brawl_teams INNER JOIN brawl ON brawl.team_id = brawl_teams.team_id INNER JOIN clans ON clans.id = brawl_teams.clan_id LEFT OUTER JOIN members mb ON mb.id = brawl.member_id WHERE clanperiod = ? AND got100time IS NOT NULL AND ((position > 0 AND position < 6) OR position IS NULL) GROUP BY brawl_teams.team_id ORDER BY clans.got100time", {}, $periodid);
	print "<table class=\"brawl\">";
	print "<tr><th>Clan</th><th colspan=5>Team</th></tr>";
	my @limit = (1..@$info);
	my $displaybw;
	my $currentb = 1;
	if ($c->param('clans')) {
		@limit = split /,/, $c->param('clans');
		$displaybw = 1;
	}
	my $count = 0;
	foreach (@limit) {
		my $clan = $info->[$_-1];
		$count++;
		my @team = (("") x 5);
		foreach(split /;/, ($clan->[2] || "")) {
			my @a = split /,/, ($_ || "1");
			$team[$a[0] - 1] = $a[1] ? $c->rendermember(@a[1,2,3])." ($a[4])" : "";
		}
		foreach(0..4) {
			$team[$_] .= ($displaybw ? $currentb ? " [black]" : " [white]" : "");
			$currentb = !$currentb;
		}
		my $team = join '', map { "<td>$_</td>" } @team;
		print "<tr><td>".$c->renderclan(@{$clan}[0,1])."</a></td>$team</tr>";
		print "<tr><td colspan=6></td></tr>" if $currentb && $_ != $limit[$#limit] && $displaybw;
	}
	print "</table>";
}
$c->footer;
