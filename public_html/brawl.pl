#!/usr/bin/perl

use strict;
use warnings;
use Clans;
use LWP::Simple;
use POSIX qw/strftime/;
use Carp qw/cluck/;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = Clans->new;

$c->header("Clan Brawl");

my $mode = $c->param('mode') || 'overview';
my @modes = qw/predraw overview prelim main battle team team_current round round_current/;

$mode = 'overview' unless grep { $_ eq $mode } @modes;

my $period = $c->period_info()->{id};
my $periodparam = $c->{context_params} ? "&amp;$c->{context_params}" : "";

print $c->h3("Quick Links");

print qq{<p><a href="brawl.pl?mode=predraw$periodparam">Pre-draw</a> | <a href="brawl.pl?$periodparam">Overview</a> | <a href="brawl.pl?mode=prelim$periodparam">Preliminaries</a> | <a href="brawl.pl?mode=main$periodparam">Main</a> | <a href="brawl.pl?mode=round$periodparam">All battles</a> | <a href="brawl.pl?mode=round_current$periodparam">Current round</a></p>};

my $user_clan = $c->db_select("SELECT id, name FROM clans INNER JOIN forumuser_clans ON clans.id = forumuser_clans.clan_id WHERE clanperiod = ? AND forumuser_clans.user_id = ?", {}, $period, $c->{userid});
if (@$user_clan) {
	my $clan_teams = $c->db_select("SELECT team_id, name FROM brawl_teams WHERE clan_id = ? ORDER BY team_number", {}, $user_clan->[0][0]);
	if (@$clan_teams) {
		print "<p>".$c->render_clan(@{$user_clan->[0]}).":</p>";
		print "<ul>";
		for(@$clan_teams) {
			print qq|<li>$_->[1]: <a href="brawl.pl?mode=team&amp;team=$_->[0]">All rounds</a> or <a href="brawl.pl?mode=team_current&amp;team=$_->[0]">current round only</a></li>|;
		}
		print "</ul>";
	}
}

if ($mode eq 'overview') {
	print $c->h3("Main Event");
	print brawl_main_overview($c, $period);

	print $c->h3("Preliminaries");
	print brawl_prelim_overview($c, $period);
} elsif ($mode eq 'prelim') {
	my $position = $c->param('position');
	if (defined $position) {
		$position =~ s/\D//g;
		$position ||= 0;
		print brawl_prelim($c, $period, $position);
	} else {
		print $c->h3("Preliminaries");
		print brawl_prelim_overview($c, $period);
	}
} elsif ($mode eq 'main') {
	print $c->h3("Main Event");
	print brawl_main_overview($c, $period);
} elsif ($mode eq 'battle') {
	my $round = $c->param('round') || 0;
	my $gameno = $c->param('game') || 0;
	$round =~ s/\D//g;
	$round ||= 0;
	$gameno =~ s/\D//g;
	$gameno ||= 0;
	if ($round) {
		print $c->h3("Battle for round $round, game number ".($gameno+1));
	} else {
		print $c->h3("Preliminary battle, game number ".($gameno+1));
	}
	print brawl_battle($c, $period, $round, $gameno);
} elsif ($mode eq 'team' || $mode eq 'team_current') {
	my $team = $c->param('team') || 0;
	$team =~ s/\D//g;
	$team ||= 0;
	my $team_name = $c->db_selectone("SELECT name FROM brawl_teams WHERE team_id = ? ORDER BY team_number", {}, $team);
	if (!$team_name) {
		print "Error: Team does not exist.";
	} else {
		print $c->h3("Brawl battles for team ".$c->escapeHTML($team_name));
		my $round_data;
		if ($mode eq 'team') {
			$round_data = $c->db_select("SELECT round, FLOOR(position/2) FROM brawldraw WHERE team_id = ? ORDER BY round, position", {}, $team);
		} else {
			my $round = $c->db_selectone("SELECT MAX(round) FROM brawldraw_results WHERE clanperiod = ?", {}, $period) || 0;
			$round_data = $c->db_select("SELECT round, FLOOR(position/2) FROM brawldraw WHERE team_id = ? AND round = ? ORDER BY position", {}, $team, $round);
		}
		if (@$round_data) {
			my $round = -1;
			my $game_count = 0;
			for(@$round_data) {
				if ($_->[0] != $round) {
					$round = $_->[0];
					if ($round == 0) {
						print $c->h4("Preliminary round");
					} else {
						print $c->h4("Round $round");
					}
				}
				if ($round == 0) {
					print "<h5>Game ".(++$game_count)."</h5>";
				}
				print brawl_battle($c, $period, $round, $_->[1]);
			}
		} else {
			print "No draw exists for this team."
		}
	}
} elsif ($mode eq 'predraw') {
	# XXX copy-paste
	my $p = { period_id => $period };

	# Get a list of team members.
	my $members = $c->db_select("SELECT brawl.team_id, position, member_id FROM brawl INNER JOIN brawl_teams ON brawl.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ?", {}, $p->{period_id});

	# Sort members into teams.
	my %team_members;
	for(@$members) {
		$team_members{$_->[0]} ||= [];
		next unless $_->[1] >= 0 && $_->[1] <= 4;
		$team_members{$_->[0]}[$_->[1]] = $_->[2];
		$team_members{$_->[0]}[5]++;
	}

	# This is the first round. First, we must decide if we need to produce a preliminary draw.
	$p->{req_points} = $c->get_option('BRAWLTEAMPOINTS');
	if (!$p->{req_points}) {
		print "<h3>Error</h3>";
		print $c->p("This period was before the automatic brawl draw process.");
		$c->footer;
		exit 0;
	}
	my @points = split /,/, $p->{req_points};

	$p->{req_members} = $c->get_option('BRAWLTEAMMINMEMBERS');

	$p->{max_rounds} = $c->get_option('BRAWLROUNDS');

	# Get a list of teams.
	my $teams = $c->db_select("SELECT brawl_teams.team_id, team_number, clans.points, COUNT(member_id) AS number, clans.id, clans.name, brawl_teams.name FROM brawl_team_members INNER JOIN brawl_teams ON brawl_team_members.team_id = brawl_teams.team_id INNER JOIN clans ON clans.id = brawl_teams.clan_id WHERE clans.clanperiod = ? GROUP BY brawl_teams.team_id HAVING number >= ?", {}, $p->{period_id}, $p->{req_members});

	# Remove all teams which do not have 5 members.
	$p->{all_teams} = join ',', map { $_->[0] } @$teams;

	$p->{current_champion} = $c->get_option('BRAWLCHAMPION');

	# For both below cases, we need to know the seed score for each team.
	for(0..$#$teams) {
		$teams->[$_][3] = $teams->[$_][2] / $points[$teams->[$_][1]];
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
		$p->{auto_entry} = $c->get_option('BRAWLAUTOENTRY');
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
		$p->{teams_on_min} = $p->{remain_slots} - (@$teams % $p->{remain_slots});

		if ($p->{min_opponents} == 0) {
			# In this case, at least one team gets in free. Bung 'em all on auto_teams.
			push @auto_teams, splice(@$teams, 0, $p->{teams_on_min});
			$p->{remain_slots} -= $p->{teams_on_min};
			$p->{teams_on_min} = @$teams;
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
					$p->{teams_on_min}++;
					if ($p->{teams_on_min} == $p->{remain_slots} + 1) {
						if ($p->{min_opponents} == 1) {
							push @auto_teams, shift @$teams;
							# Here, the following two are equal.
							$p->{teams_on_min}--;
							$p->{remain_slots}--;
						} else {
							$p->{teams_on_min} = 1;
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
				my $num_opponents = $p->{min_opponents} + ($slot_num > $p->{teams_on_min} ? 1 : 0);
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
} else {
	my $round;
	if ($mode eq 'round') {
		$round = $c->param('round') || -1;
		$round =~ s/[^-\d]//g;
		$round ||= 0;
	} else {
		$round = $c->db_selectone("SELECT MAX(round) FROM brawldraw_results WHERE clanperiod = ?", {}, $period) || 0;
	}
	my $round_data;
	if ($round == -1) {
		$round_data = $c->db_select("SELECT DISTINCT round, FLOOR(position/2) FROM brawldraw WHERE clanperiod = ? ORDER BY round, position", {}, $period);
		print $c->h3("Brawl draw data for all rounds");
	} else {
		$round_data = $c->db_select("SELECT DISTINCT round, FLOOR(position/2) FROM brawldraw WHERE clanperiod = ? AND round = ? ORDER BY round, position", {}, $period, $round);
		print $c->h3("Brawl draw data round $round");
	}
	if (@$round_data) {
		my $round = -1;
		my $game_count;
		for(@$round_data) {
			if ($_->[0] != $round) {
				$round = $_->[0];
				$game_count = 0;
				if ($round == 0) {
					print $c->h4("Preliminary round");
				} else {
					print $c->h4("Round $round");
				}
			}
			print "<h5>Game ".(++$game_count)."</h5>";
			print brawl_battle($c, $period, $round, $_->[1]);
		}
	} else {
		print "No draw exists for this team.";
	}
}

$c->footer;

sub brawl_prelim_overview {
	return brawl_prelim(@_);
}

sub brawl_prelim {
	my ($c, $period, $position) = @_;

	my $draw_data;
	if (defined $position) {
		$draw_data = $c->db_select("SELECT nextround_pos, position, brawl_teams.team_id, brawl_teams.name, clans.id, clans.tag, result FROM brawldraw INNER JOIN brawl_teams ON brawldraw.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE round = 0 AND brawldraw.clanperiod = ? AND nextround_pos = ? ORDER BY position", {}, $period, $position);
	} else {
		$draw_data = $c->db_select("SELECT nextround_pos, position, brawl_teams.team_id, brawl_teams.name, clans.id, clans.tag, result FROM brawldraw INNER JOIN brawl_teams ON brawldraw.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE round = 0 AND brawldraw.clanperiod = ? ORDER BY position", {}, $period);
	}

	if (!@$draw_data) {
		return "No preliminary round data is available";
	}
	
	my %groups;
	my %teams;
	my $last_val;
	my %order;
	my $order_val = 0;
	for(@$draw_data) {
		$groups{$_->[0]} ||= {};
		$groups{$_->[0]}{$_->[2]} ||= {};
		$teams{$_->[2]} ||= $_;
		$order{$_->[2]} = $order_val++ if !exists $order{$_->[2]};
		if ($_->[1] % 2 == 0) {
			# Even position means the team is the first in its match.
			$last_val = $_;
		} else {
			# Odd position means it is the opponent of $last_val.
			$groups{$_->[0]}{$last_val->[2]}{$_->[2]} = $last_val;
			$groups{$_->[0]}{$_->[2]}{$last_val->[2]} = $_;
			undef $last_val;
		}
	}

	my $output = '';
	for my $target_pos (sort keys %groups) {
		my $level = defined $position ? 3 : 4;
		$output .= "<h$level>Fighting for position ".($target_pos+1)."</h$level>";
		$output .= "<p>A square is a + if the left team beat the top team.</p>";
		my %group = %{$groups{$target_pos}};
		my @teams = sort { $order{$a} <=> $order{$b} } keys %group;
		$output .= "<table>";
		$output .= "<tr><td></td>";
		for my $team_id (@teams) {
			$output .= "<th>$teams{$team_id}[3]<br/>(".$c->render_clan($teams{$team_id}[4], $teams{$team_id}[5]).")</th>";
		}
		$output .= "</tr>";
		for my $team_id (@teams) {
			$output .= "<tr>";
			$output .= "<th>$teams{$team_id}[3] (".$c->render_clan($teams{$team_id}[4], $teams{$team_id}[5]).")</th>";
			for my $opp_id (@teams) {
				my $info = $group{$team_id}{$opp_id};
				my $win = $info->[6];
				my $class;
				my $val;
				my $link;
				if ($win) {
					if ($win == 1) {
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

	my $prelim_rounds = $c->db_select("SELECT DISTINCT(nextround_pos) FROM brawldraw WHERE round=0 AND clanperiod=?", {}, $period);
	my %has_prelim;
	$has_prelim{$_->[0]} = 1 for (@$prelim_rounds);

	# Generate brawl league table
	my $draw_data = $c->db_select("SELECT round, position, brawl_teams.team_id, brawl_teams.name, clans.id, clans.tag, result FROM brawldraw INNER JOIN brawl_teams ON brawldraw.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE round >= 1 AND brawldraw.clanperiod = ?", {}, $period);

	if (!@$draw_data) {
		return "No main round data is available";
	}
	
	my @draw;
	for (@$draw_data) {
		$draw[$_->[0]-1] ||= [];
		$draw[$_->[0]-1][$_->[1]] = $_;
	}

	my $output = qq|<p>Click on the &quot;vs.&quot; to get the draw for that battle.</p><table border=1>|;
	$output .= "<tr>";
	for my $round (1..@draw) {
		$output .= "<th>Round $round</th>";
	}
	$output .= "</tr>";
	for my $position (0..2*@{$draw[0]}-2) {
		$output .= "<tr>";
		for my $round (0..$#draw) {
			my $block_size = 2 ** ($round+1)-1;
			my $test_size = $block_size+1;
			if ($position % $test_size == 0) {
				# Show a team
				my $index = int($position/$test_size);
				my $info = $draw[$round][$index];
				my $rowspan = $block_size > 1 ? qq| rowspan="$block_size"| : "";
				my ($class, $content);
				if ($info) {
					if (defined $info->[6]) {
						if ($info->[6] == 1) {
							$class = qq| class="clan_won"|;
						} elsif ($info->[6] == -1) {
							$class = qq| class="clan_lost"|;
						} else {
							$class = qq| class="clan_unplayed"|;
						}
					} elsif ($round = $#draw && @{$draw[$#draw]} == 1) {
						$class = qq| class="clan_won"|;
					} else {
						$class = qq| class="clan_unplayed"|;
					}
					$content = $info->[3]." (".$c->render_clan($info->[4], $info->[5]).")";
				} else {
					$class = qq| class="clan_unplayed"|;
					$content = "?";
				}
				if ($round == 0 && $has_prelim{$index}) {
					$content = qq|(<a href="brawl.pl?mode=prelim&amp;position=$index$periodparam">prelim</a>) $content|;
				}
				$output .= qq|<td$rowspan$class>|;
				$output .= $content;
				$output .= qq|</td>|;
			} elsif (($position + 1) % ($test_size * 2) == $test_size) {
				# Show a vs
				my $gameno = int($position/2/$test_size);
				$output .= qq|<td style="text-align:center;"><a href="brawl.pl?mode=battle&amp;round=@{[$round+1]}&amp;game=$gameno$periodparam">vs.</a></td>|;
			} elsif (($position + 1) % ($test_size * 2) == 0) {
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
	my ($c, $period, $round, $gameno) = @_;
	my @positions = ($gameno * 2, $gameno * 2 + 1);

	my $teamdata = $c->db_select("SELECT position, brawl_teams.team_id, brawl_teams.name, clans.id, clans.name, result FROM brawldraw INNER JOIN brawl_teams ON brawldraw.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE brawldraw.clanperiod = ? AND round = ? AND position >= ? AND position <= ?", {}, $period, $round, @positions);

	if (@$teamdata == 0) {
		return "There is no draw for this battle.";
	} elsif (@$teamdata == 1) {
		return "Team ".$c->escapeHTML($teamdata->[0][2])." (".$c->render_clan($teamdata->[0][3], $teamdata->[0][4]).") has no opponent.";
	}

	if ($positions[0] == $teamdata->[1][0]) {
		@$teamdata = reverse @$teamdata;
	}

	my $memberdata = $c->db_select("SELECT position, seat, members.id, members.name, members.rank, is_black, result, url FROM brawldraw_results INNER JOIN members ON brawldraw_results.member_id = members.id WHERE brawldraw_results.clanperiod = ? AND round = ? AND position >= ? AND position <= ? AND seat >= 0 AND seat <= 4", {}, $period, $round, @positions);
	my (@top, @bottom, @urls);

	for (@$memberdata) {
		if ($_->[0] == $positions[0]) {
			$top[$_->[1]] = $_;
		} else {
			$bottom[$_->[1]] = $_;
		}
		$urls[$_->[1]] = $_->[7] if $_->[7];
	}

	# If we get here we know it's a fight between two teams.
	my $output = qq|<table class="brawldraw">|;
	$output .= qq|<tr>|;
	{
		my $class;
		if ($teamdata->[0][5]) {
			if ($teamdata->[0][5] == 1) {
				$class = "clan_won";
			} else {
				$class = "clan_lost";
			}
		} else {
			$class = "clan_unplayed";
		}
		$output .= qq|<td class="$class" colspan="5">|.$c->escapeHTML($teamdata->[0][2])." (".$c->render_clan($teamdata->[0][3], $teamdata->[0][4]).qq|)</td>|;
	}
	$output .= qq|</tr><tr>|;
	for my $member (@top) {
		if (!$member) {
			$output .= qq|<td></td>|;
			next;
		}
		my $class;
		if ($member->[5]) {
			$class = "player_black";
		} else {
			$class = "player_white";
		}
		if ($member->[6]) {
			if ($member->[6] == 1) {
				$class .= " player_won";
			} else {
				$class .= " player_lost";
			}
		} else {
			$class .= " player_unplayed";
		}
		$output .= qq|<td class="$class">|.$c->render_member($member->[2], $member->[3], $member->[4]).qq|</td>|;
	}
	$output .= qq|</tr><tr>|;
	for my $url (@urls) {
		if ($url) {
			if ($url =~ /^http/) {
				$output .= qq|<td><a href="|.$c->escapeHTML($url).qq|">Game</a></td>|;
			} else {
				$output .= qq|<td>(Default)</td>|;
			}
		} else {
			$output .= qq|<td>(No data)</td>|;
		}
	}
	$output .= qq|</tr><tr>|;
	for my $member (@bottom) {
		if (!$member) {
			$output .= qq|<td></td>|;
			next;
		}
		my $class;
		if ($member->[5]) {
			$class = "player_black";
		} else {
			$class = "player_white";
		}
		if ($member->[6]) {
			if ($member->[6] == 1) {
				$class .= " player_won";
			} else {
				$class .= " player_lost";
			}
		} else {
			$class .= " player_unplayed";
		}
		$output .= qq|<td class="$class">|.$c->render_member($member->[2], $member->[3], $member->[4]).qq|</td>|;
	}
	$output .= qq|</tr><tr>|;
	{
		my $class;
		if ($teamdata->[1][5]) {
			if ($teamdata->[1][5] == 1) {
				$class = "clan_won";
			} else {
				$class = "clan_lost";
			}
		} else {
			$class = "clan_unplayed";
		}
		$output .= qq|<td class="$class" colspan="5">|.$c->escapeHTML($teamdata->[1][2])." (".$c->render_clan($teamdata->[1][3], $teamdata->[1][4]).qq|)</td>|;
	}
	$output .= "</tr></table>";
}
