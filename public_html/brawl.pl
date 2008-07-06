#!/usr/bin/perl

use strict;
use warnings;
use Clans;
use LWP::Simple;
use POSIX qw/strftime/;
use Carp qw/cluck/;
use Time::Local;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = Clans->new;

$c->header("Clan Battles");

my $mode = $c->param('mode') || 'battles';
my @modes = qw/battles brawl_draw brawl_overview brawl_prelim/;

unless (grep { $_ eq $mode } @modes) {
	$mode = 'battles';
}

my $period = $c->period_info()->{id};
my $periodparam = $c->{context_params} ? "&amp;$c->{context_params}" : "";

print $c->h3("Quick Links");

# TODO mask some off, add links for individual rounds.
print qq{<p>Brawl: <a href="brawl.pl?mode=brawl_draw$periodparam">Draw Preview</a> | <a href="brawl.pl?mode=brawl_overview$periodparam">Overview</a> | <a href="brawl.pl?mode=battles&amp;brawl=prelim$periodparam">Preliminary Battles</a> | <a href="brawl.pl?mode=battles&amp;brawl=main$periodparam">Knockout Battles</a> | <a href="brawl.pl?mode=battles&amp;brawl=all$periodparam">All Battles</a> | <a href="brawl.pl?mode=battles&amp;brawl=all&amp;unfinished=1$periodparam">Current Round Battles</a></p>};
print qq{<p>Team Battles: <a href="brawl.pl?mode=battles&amp;undecided=1&amp;brawl=no$periodparam">Currently Undecided</a> | <a href="brawl.pl?mode=battles&amp;age=2&amp;brawl=no$periodparam">Last 2 Weeks</a> | <a href="brawl.pl?mode=battles&amp;brawl=no$periodparam">All</a>};

# TODO fix
#my $user_clan = $c->db_select("SELECT id, name FROM clans INNER JOIN forumuser_clans ON clans.id = forumuser_clans.clan_id WHERE clanperiod = ? AND forumuser_clans.user_id = ?", {}, $period, $c->{userid});
#if (@$user_clan) {
#	my $clan_teams = $c->db_select("SELECT team_id, name FROM brawl_teams WHERE clan_id = ? ORDER BY team_number", {}, $user_clan->[0][0]);
#	if (@$clan_teams) {
#		print "<p>".$c->render_clan(@{$user_clan->[0]}).":</p>";
#		print "<ul>";
#		for(@$clan_teams) {
#			print qq{<li>$_->[1]: <a href="brawl.pl?mode=battles&amp;team=$_->[0]">All rounds</a> | <a href="brawl.pl?mode=battles&amp;team=$_->[0]&amp;open=1">current round only</a></li>|;
#		}
#		print "</ul>";
#	}
#}

if ($mode eq 'brawl_overview') {
	print $c->h3("Main Event");
	print brawl_main_overview($c, $period);

	print $c->h3("Preliminaries");
	print brawl_prelim_overview($c, $period);
} elsif ($mode eq 'brawl_prelim') {
	my $for_position = $c->param('for_position');
	my $for_team_no = $c->param('for_team_no');
	if (defined $for_position) {
		$for_position =~ s/\D//g;
		$for_team_no =~ s/\D//g;
		$for_position ||= 0;
		$for_team_no ||= 0;
		print brawl_prelim($c, $period, $for_position, $for_team_no);
	} else {
		print $c->h3("Preliminaries");
		print brawl_prelim_overview($c, $period);
	}
} elsif ($mode eq 'battles') {
	my ($SQL_where, $SQL_from, @params_where, @params_join) = ("1", "team_matches");
	$SQL_from .= " LEFT OUTER JOIN brawl ON brawl.team_match_id = team_matches.id";
	$SQL_from .= " LEFT OUTER JOIN brawl_prelim ON brawl_prelim.team_match_id = team_matches.id";
	if (my $brawl = $c->param('brawl')) {
		if ($brawl eq 'all') {
			$SQL_where .= " AND (brawl.team_match_id IS NOT NULL OR brawl_prelim.team_match_id IS NOT NULL)";
		} elsif ($brawl eq 'main') {
			$SQL_where .= " AND brawl.team_match_id IS NOT NULL";
		} elsif ($brawl eq 'prelim') {
			$SQL_where .= " AND brawl_prelim.team_match_id IS NOT NULL";
		} elsif ($brawl eq 'no') {
			$SQL_where .= " AND brawl.team_match_id IS NULL AND brawl_prelim.team_match_id IS NULL";
		} elsif ($brawl =~ /^[0-9]+$/) {
			$SQL_where .= " AND brawl.round = ?";
			push @params_where, $brawl;
		} else {
			$c->die_fatal_badinput("Unknown value for brawl parameter");
		}
	}
	if (my $unfinished = $c->param('unfinished')) {
		$SQL_where .= " AND team_matches.winner IS NULL";
	}
	if (my $match_id = $c->param('match_id')) {
		$SQL_where .= " AND team_matches.id = ?";
		push @params_where, $match_id;
	}
	if (my $team_id = $c->param('team_id')) {
		$SQL_from .= " LEFT OUTER JOIN team_match_teams ON team_match_teams.team_match_id = team_matches.id";
		$SQL_where .= " AND team_match_teams.team_id = ?";
		push @params_where, $team_id;
	}
	if (my $age = $c->param('age')) {
		$SQL_where .= " AND team_matches.start_date >= ?";
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime();
		$sec = 0;
		$min = 0;
		$hour = 0;
		my $midnighttime = timegm($sec,$min,$hour,$mday,$mon,$year);

		$wday = ($wday - 1) % 7; # Now Monday is 0.
		# Days to shift back is (days to return to Monday) + age * 7

		$midnighttime -= $wday + $age * 7;

		push @params_where, $midnighttime;
	}
	my $id_arr = $c->db_select("SELECT team_matches.id, brawl_prelim.for_position, brawl_prelim.for_team_no, brawl.round, brawl.position FROM $SQL_from WHERE $SQL_where AND team_matches.period_id = ? ORDER BY brawl.round, brawl.position, brawl_prelim.for_position, brawl_prelim.for_team_no, start_date", {}, @params_join, @params_where, $period);
	if (!$id_arr) {
		$c->die_fatal_db("Database error getting match list.");
	}
	my ($first, $forp, $fort, $round, $pos) = (1);
	for(@$id_arr) {
		if (defined $_->[1]) {
			if (!defined $forp || $forp != $_->[1] || $fort != $_->[2]) {
				print "<h3>Brawl preliminaries for position $_->[1] (slot $_->[2])</h3>";
			}
		} elsif (defined $_->[3]) {
			if (!defined $round || $round != $_->[3]) {
				print "<h3>Brawl round $_->[3]</h3>";
			}
			if (!defined $pos || $pos != $_->[4]) {
				# Don't really need to output anything here...
			}
		} elsif ($first) {
			print "<h3>Non-brawl battles</h3>";
		}
		if ($first) {
			print "<p>Click the 'Game' links for the SGF files. Red background implies a loss, green a win, and the player's name is their colour in the game.</p>";
		}
		($forp, $fort, $round, $pos) = @$_[1..4];
		undef $first;
		print "<p>".brawl_battle($c, $_->[0])."</p>";
	}
} elsif ($mode eq 'brawl_draw') {
	# XXX copy-paste
	my $p = { period_id => $period };

	# Get a list of team members.
	my $members = $c->db_select("SELECT team_id, seat_no, member_id FROM team_seats INNER JOIN teams ON team_seats.team_id = teams.id INNER JOIN clans ON  teams.clan_id = clans.id WHERE clans.period_id = ?", {}, $p->{period_id});

	# Sort members into teams.
	my %team_members;
	for(@$members) {
		$team_members{$_->[0]} ||= [];
		next unless $_->[1] >= 0 && $_->[1] <= 4;
		$team_members{$_->[0]}[$_->[1]] = $_->[2];
		$team_members{$_->[0]}[5]++;
	}

	# This is the first round. First, we must decide if we need to produce a preliminary draw.
	$p->{req_points} = $c->get_option('BRAWLTEAMPOINTS', $p->{period_id});
	if (!$p->{req_points}) {
		print "<h3>Error</h3>";
		print $c->p("This period was before the automatic brawl draw process.");
		$c->footer;
		exit 0;
	}
	my @points = split /,/, $p->{req_points};

	$p->{req_members} = $c->get_option('BRAWLTEAMMINMEMBERS', $p->{period_id});

	$p->{max_rounds} = $c->get_option('BRAWLROUNDS', $p->{period_id});

	# Get a list of teams.
	my $teams = $c->db_select("SELECT teams.id, team_number, clans.points, COUNT(member_id) AS number, clans.id, clans.name, teams.name FROM team_members INNER JOIN teams ON team_members.team_id = teams.id INNER JOIN clans ON clans.id = teams.clan_id WHERE clans.period_id = ? GROUP BY teams.id HAVING number >= ?", {}, $p->{period_id}, $p->{req_members});

	# Remove all teams which do not have 5 members.
	$p->{all_teams} = join ',', map { $_->[0] } @$teams;

	$p->{current_champion} = $c->get_option('BRAWLCHAMPION', $p->{period_id});

	# For both below cases, we need to know the seed score for each team.
	for(0..$#$teams) {
		$teams->[$_][3] = $teams->[$_][2] / $points[$teams->[$_][1]-1];
		# The winner of the last brawl is always seeded top.
		$teams->[$_][3] = 9001 if $teams->[$_][4] == $p->{current_champion} && $teams->[$_][1] == 1;
	}
	@$teams = sort { $b->[3] <=> $a->[3] } @$teams;
	$p->{sorted_teams} = join ',', map { $_->[0] } @$teams;

	# Generate an order mapping, as this is also used in both cases.
	# We do this by recursively pairing top with bottom on opponent groups.
	$p->{max_teams} = 2 ** $p->{max_rounds};
	my @tree = (0 .. $p->{max_teams} - 1);
	while(@tree > 2) {
		my @new_tree;
		for(0 .. @tree / 2 - 1) {
			if (ref $tree[0]) {
				# Subsequent swaps
				push @new_tree, [$tree[$_], $tree[$#tree-$_]];
			} else {
				# First swap is reversed to make sure the seeds get even positions and make table render properly.
				push @new_tree, [$tree[$#tree-$_], $tree[$_]];
			}
		}
		@tree = @new_tree;
	}
	# Do a depth first search to pull the tree back apart.
	my $dfs;
	$dfs = sub { ref $_[0] ? ($dfs->($_[0][0]), $dfs->($_[0][1])) : $_[0] };
	my @position_map_inverse = $dfs->(\@tree);
	my @position_map;
	$position_map[$position_map_inverse[$_]] = $_ for 0..$#position_map_inverse;

	my (@auto_teams, @fights);

	if (@$teams > $p->{max_teams}) {
		# We must generate a preliminary round.
		$p->{this_round} = 0;

		# First, who gets auto entry?
		$p->{auto_entry} = $c->get_option('BRAWLAUTOENTRY', $p->{period_id});
		@auto_teams = splice(@$teams, 0, $p->{auto_entry});

		# Remove any teams which are the second or above from their clan.
		my $prelim_index = 0;
		my $moved_something = 1;
		while($moved_something) {
			my %clans_hit;
			$moved_something = 0;
			for(0..$p->{auto_entry}-1) {
				my $clan_id = $auto_teams[$_][4];
				if ($clans_hit{$clan_id} && @$teams > $prelim_index) {
					# Swap for next preliminary team, assuming there is one.
					my $temp = $auto_teams[$_];
					$auto_teams[$_] = $teams->[$prelim_index];
					$teams->[$prelim_index++] = $temp;
					$moved_something = 1;
				} else {
					$clans_hit{$clan_id} = 1;
				}
			}
			@auto_teams = sort { $b->[3] <=> $a->[3] } @auto_teams;
			@$teams = sort { $b->[3] <=> $a->[3] } @$teams;
		}
		$p->{double_auto_teams} = join ',', map { $_->[0] } @{$teams}[0..$prelim_index-1];

		# Now, the remainder have to duke it out. We solve this with an all-play-all league.
		$p->{remain_slots} = $p->{max_teams} - $p->{auto_entry};
		$p->{min_opponents} = int(@$teams/$p->{remain_slots}) - 1; # >= 1 by if condition
		$p->{slots_on_min} = $p->{remain_slots} - (@$teams % $p->{remain_slots});

		if ($p->{min_opponents} == 0) {
			# In this case, at least one team gets in free. Bung 'em all on auto_teams.
			push @auto_teams, splice(@$teams, 0, $p->{slots_on_min});
			$p->{remain_slots} -= $p->{slots_on_min};
			$p->{slots_on_min} = @$teams / 2;
			$p->{min_opponents} = 1;
		}

		# There may be some teams in the preliminary round which have no lineup. If this is the case, we cull them now, one by one.
		{
			my @culled = ();
			while(1) {
				my @cull = grep { !$team_members{$teams->[$_][0]} || $team_members{$teams->[$_][0]}[5] != 5 } (0..$#$teams);
				if (@cull) {
					my $cull_idx = $cull[$#cull];
					push @culled, $teams->[$cull_idx];
					splice(@$teams, $cull_idx, 1);
					$p->{slots_on_min}++;
					if ($p->{slots_on_min} == $p->{remain_slots} + 1) {
						if ($p->{min_opponents} == 1) {
							push @auto_teams, shift @$teams;
							# Here, the following two are equal.
							$p->{slots_on_min}--;
							$p->{remain_slots}--;
						} else {
							$p->{slots_on_min} = 1;
							$p->{min_opponents}--;
						}
					}
				} else {
					last;
				}
			}
			$p->{cull_teams} = join ',', map { $_->[0] } @culled;
		}

		$p->{auto_teams} = join ',', map { $_->[0] } @auto_teams;
		$p->{preliminary_teams} = join ',', map { $_->[0] } @$teams;

		# Now we have a list of teams which need to be blocked together. We this by grouping the teams as follows:
		# 1 3 5  8
		# 2 4 6  9
		#     7 10
		{
			my $pos = 0;
			for my $slot_num (0..$p->{remain_slots}-1) {
				my $num_opponents = $p->{min_opponents} + ($slot_num > $p->{slots_on_min} ? 2 : 1);
				$fights[$slot_num] = [];
				for my $opp_num (1..$num_opponents) {
					push @{$fights[$slot_num]}, $teams->[$pos++];
				}
			}
		}
	} else {
		@auto_teams = @$teams;
	}

	print $c->h3("Preliminary round data");

	print $c->p("If the draw were made right now, this would be the result.");

	print $c->h4("Automatically qualified");
	if (@auto_teams) {
		print "<ul>";
		print "<li>$_->[6] (".$c->render_clan(@$_[4,5]).")</li>" for @auto_teams;
		print "</ul>";
	} else {
		print $c->p("No teams automatically qualified.");
	}

	if (@fights) {
		my $group_no = 1;
		for (@fights) {
			print $c->h4("Group $group_no");
			$group_no++;
			print "<ul>";
			print "<li>$_->[6] (".$c->render_clan(@$_[4,5]).")</li>" for @$_;
			print "</ul>";
		}
	}
}

$c->footer;

sub brawl_prelim_overview {
	return brawl_prelim(@_);
}

sub brawl_prelim {
	my ($c, $period, $position, $team_no) = @_;

	my $draw_data;
	if (defined $position) {
		$draw_data = $c->db_select("SELECT brawl_prelim.for_position, brawl_prelim.for_team_no, team_match_teams.team_no, teams.id, teams.name, clans.id, clans.tag, team_matches.winner, brawl_prelim.team_match_id FROM brawl_prelim NATURAL JOIN team_match_teams INNER JOIN team_matches ON brawl_prelim.team_match_id = team_matches.id INNER JOIN teams ON team_match_teams.team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE brawl_prelim.period_id = ? AND for_position = ? AND for_team_no = ? ORDER BY for_position, for_team_no, brawl_prelim.team_match_id, team_no", {}, $period, $position, $team_no);
	} else {
		$draw_data = $c->db_select("SELECT brawl_prelim.for_position, brawl_prelim.for_team_no, team_match_teams.team_no, teams.id, teams.name, clans.id, clans.tag, team_matches.winner, brawl_prelim.team_match_id FROM brawl_prelim NATURAL JOIN team_match_teams INNER JOIN team_matches ON brawl_prelim.team_match_id = team_matches.id INNER JOIN teams ON team_match_teams.team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE brawl_prelim.period_id = ? ORDER BY for_position, for_team_no, brawl_prelim.team_match_id, team_no", {}, $period);
	}

	if (!@$draw_data) {
		return "No preliminary round data is available";
	}
	
	my @groups;
	my %teams;
	my $last_val;
	my %order;
	my $order_val = 0;
	for(@$draw_data) {
		$groups[$_->[0]]||= [];
		$groups[$_->[0]][$_->[1]-1] ||= {};
		$teams{$_->[3]} ||= $_;
		$order{$_->[3]} = $order_val++ if !exists $order{$_->[3]};
		if ($_->[2] == 1) {
			# The team is the first in its match.
			$last_val = $_;
		} else {
			# Odd position means it is the opponent of $last_val.
			$groups[$_->[0]][$_->[1]-1]{$last_val->[3]}{$_->[3]} = $last_val;
			$groups[$_->[0]][$_->[1]-1]{$_->[3]}{$last_val->[3]} = $_;
			undef $last_val;
		}
	}

	my $output = '';
	for my $index (0..2*@groups-1) {
		my $for_position = int($index/2);
		my $for_team_no = $index%2+1;
		next unless $groups[$for_position] && $groups[$for_position][$for_team_no-1];
		my $level = defined $position ? 3 : 4;
		$output .= "<h$level>Fighting for position ".($for_position+1)." (slot $for_team_no)</h$level>";
		$output .= "<p>A square is a + if the left team beat the top team.</p>";
		my %group = %{$groups[$for_position][$for_team_no-1]};
		my @teams = sort { $order{$a} <=> $order{$b} } keys %group;
		$output .= "<table>";
		$output .= "<tr><td></td>";
		for my $team_id (@teams) {
			$output .= "<th>$teams{$team_id}[4]<br/>(".$c->render_clan($teams{$team_id}[5], $teams{$team_id}[6]).")</th>";
		}
		$output .= "</tr>";
		for my $team_id (@teams) {
			$output .= "<tr>";
			$output .= "<th>$teams{$team_id}[4] (".$c->render_clan($teams{$team_id}[5], $teams{$team_id}[6]).")</th>";
			for my $opp_id (@teams) {
				my $info = $group{$team_id}{$opp_id};
				my $win = $info->[7];
				my $class;
				my $val;
				my $link;
				if ($win) {
					if ($win == $info->[2]) {
						$class = qq| class="clan_won"|;
						$val = "+";
					} else {
						$class = qq| class="clan_lost"|;
						$val = "-";
					}
				} elsif ($team_id == $opp_id) {
					$class = "";
					$val = "";
				} else {
					$class = qq| class="clan_unplayed"|;
					$val = "?";
				}
				if ($class) {
					my $gameno = int($info->[1]/2);
					$link = "brawl.pl?mode=battle&amp;round=0&amp;game=$gameno$periodparam";
				}
				$output .= qq|<td style="text-align:center;"$class>|;
				$output .= qq|<a href="$link">| if $link;
				$output .= $val;
				$output .= qq|</a>| if $link;
				$output .= qq|</td>|;
			}
			$output .= "</tr>";
		}
		$output .= "</table>";
	}
	return $output;
}

sub brawl_main_overview {
	my ($c, $period) = @_;

	my $prelim_rounds = $c->db_select("SELECT for_position, for_team_no FROM brawl_prelim WHERE period_id=?", {}, $period);
	my @has_prelim;
	for (@$prelim_rounds) {
		$has_prelim[$_->[0]] ||= [];
		$has_prelim[$_->[0]][$_->[1]] = 1;
	}

	# Generate brawl league table
	my $draw_data = $c->db_select("SELECT brawl.round, brawl.position, team_match_teams.team_no, teams.id, teams.name, clans.id, clans.tag, team_matches.winner, brawl.team_match_id FROM brawl NATURAL JOIN team_match_teams INNER JOIN team_matches ON brawl.team_match_id = team_matches.id INNER JOIN teams ON team_match_teams.team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE brawl.period_id = ?", {}, $period);

	if (!@$draw_data) {
		return "No main round data is available";
	}
	
	my @draw;
	for (@$draw_data) {
		$draw[$_->[0]-1] ||= [];
		$draw[$_->[0]-1][$_->[1]] ||= [];
		$draw[$_->[0]-1][$_->[1]][$_->[2]-1] = $_;
	}

	my $output = qq|<p>Click on the &quot;vs.&quot; to get the draw for that battle.</p><table border=1>|;
	$output .= "<tr>";
	for my $round (1..@draw) {
		$output .= "<th>Round $round</th>";
	}
	$output .= "</tr>";
	for my $row (0..4*@{$draw[0]}-2) {
		$output .= "<tr>";
		for my $round (0..$#draw) {
			my $block_size = 2 ** ($round+1)-1;
			my $test_size = $block_size+1;
			my $position = int($row/$test_size/2);
			my $team_no = int($row/$test_size)%2+1;
			my $info = $draw[$round][$position][$team_no-1];
			if ($row % $test_size == 0) {
				# Show a team
				my $rowspan = $block_size > 1 ? qq| rowspan="$block_size"| : "";
				my ($class, $content);
				if ($info) {
					if (defined $info->[7]) {
						if ($info->[7] == $team_no) {
							$class = qq| class="clan_won"|;
						} elsif ($info->[7]) {
							$class = qq| class="clan_lost"|;
						} else {
							$class = qq| class="clan_unplayed"|;
						}
					} elsif ($round = $#draw && @{$draw[$#draw]} == 1) {
						$class = qq| class="clan_won"|;
					} else {
						$class = qq| class="clan_unplayed"|;
					}
					$content = qq|<a href="brawl.pl?mode=battles&amp;team_id=$info->[3]$periodparam">$info->[4]</a> (|.$c->render_clan($info->[5], $info->[6]).")";
				} else {
					$class = qq| class="clan_unplayed"|;
					$content = "?";
				}
				if ($round == 0 && $has_prelim[$position][$team_no]) {
					$content = qq|(<a href="brawl.pl?mode=brawl_prelim&amp;for_position=$position&amp;for_team_no=$team_no$periodparam">prelim</a>) $content|;
				}
				$output .= qq|<td$rowspan$class>|;
				$output .= $content;
				$output .= qq|</td>|;
			} elsif (($row + 1) % ($test_size * 2) == $test_size) {
				# Show a vs
				$output .= qq|<td style="text-align:center;"><a href="brawl.pl?mode=battles&amp;brawl=@{[$round+1]}&amp;game=$info->[8]$periodparam">vs.</a></td>|;
			} elsif (($row + 1) % ($test_size * 2) == 0) {
				# Show a blank
				$output .= qq|<td></td>|;
			} else {
				# We're inside another already output cell, so skip.
			}
		}
		$output .= "</tr>";
	}
	$output .= "</table>";
	return $output;
}

sub brawl_battle {
	my ($c, $match_id) = @_;

	my $teamdata = $c->db_select("SELECT team_match_teams.team_no, teams.id, teams.name, clans.id, clans.name, team_matches.winner, team_matches.start_date FROM team_matches INNER JOIN team_match_teams ON team_matches.id = team_match_teams.team_match_id INNER JOIN teams ON team_match_teams.team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE team_match_id = ? ORDER BY team_no", {}, $match_id);
	my $memberdata = $c->db_select("SELECT team_match_players.team_no, team_match_players.seat_no, members.id, members.name, members.rank, team_match_seats.black, team_match_seats.winner, team_match_seats.url FROM team_match_seats NATURAL JOIN team_match_players INNER JOIN members ON team_match_players.member_id = members.id WHERE team_match_players.team_match_id = ? ORDER BY team_match_players.team_no, team_match_players.seat_no", {}, $match_id);

	if (@$memberdata == 0) {
		return "<p>There is no draw for this battle.</p>";
	} elsif (@$teamdata == 1) {
		return "<p>Team ".$c->escapeHTML($teamdata->[0][2])." (".$c->render_clan($teamdata->[0][3], $teamdata->[0][4]).") has no opponent.</p>";
	}

	my (@team_members) = ([],[]);
	for (@$memberdata) {
		$team_members[$_->[0]-1][$_->[1]] = $_;
	}

	# If we get here we know it's a fight between two teams.
	my $brawl_battle_team = sub {
		my ($team_no) = @_;
		my $output = qq|<tr>|;
		my $class;
		if ($teamdata->[$team_no-1][5]) {
			if ($teamdata->[$team_no-1][5] == $team_no) {
				$class = "clan_won";
			} else {
				$class = "clan_lost";
			}
		} else {
			$class = "clan_unplayed";
		}
		$output .= qq|<td class="$class" colspan="5"><a href="brawl.pl?mode=battles&amp;team_id=$teamdata->[$team_no-1][1]">|.$c->escapeHTML($teamdata->[$team_no-1][2])."</a> (".$c->render_clan($teamdata->[$team_no-1][3], $teamdata->[$team_no-1][4]).qq|)</td>|;
		$output .= qq|</tr>|;
		return $output;
	};
	my $brawl_battle_members = sub {
		my ($team_no) = @_;
		my $output = qq|<tr>|;
		for my $member (@{$team_members[$team_no-1]}) {
			if (!$member) {
				$output .= qq|<td></td>|;
				next;
			}
			my $class = "";
			if ($member->[5]) {
				if ($member->[5] == $team_no) {
					$class = "player_black";
				} else {
					$class = "player_white";
				}
			}
			if ($member->[6]) {
				if ($member->[6] == $team_no) {
					$class .= " player_won";
				} else {
					$class .= " player_lost";
				}
			} else {
				$class .= " player_unplayed";
			}
			$output .= qq|<td class="$class">|.$c->render_member($member->[2], $member->[3], $member->[4]).qq|</td>|;
		}
		$output .= qq|</tr>|;
		return $output;
	};
	my $brawl_battle_games = sub {
		my $output = qq|<tr>|;
		for my $member (@{$team_members[0]}) {
			if ($member->[7]) {
				if ($member->[7] =~ /^http/) {
					$output .= qq|<td><a href="|.$c->escapeHTML($member->[7]).qq|">Game</a></td>|;
				} else {
					$output .= qq|<td>(Default)</td>|;
				}
			} else {
				$output .= qq|<td>(No data)</td>|;
			}
		}
		$output .= qq|</tr>|;
		return $output;
	};
	my $output = qq|<table class="brawldraw">|;
	$output .= &$brawl_battle_team(1);
	$output .= &$brawl_battle_members(1);
	$output .= &$brawl_battle_games();
	$output .= &$brawl_battle_members(2);
	$output .= &$brawl_battle_team(2);
	$output .= "</table>";
	return $output;
}
