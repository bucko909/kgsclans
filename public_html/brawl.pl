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
my @modes = qw/overview prelim main battle team team_current round round_current/;

$mode = 'overview' unless grep { $_ eq $mode } @modes;

my $period = $c->period_info()->{id};
my $periodparam = $c->param('period') ? "&amp;period=$period" : "";

print $c->h3("Quick Links");

print qq{<p><a href="brawl.pl?$periodparam">Overview</a> | <a href="brawl.pl?mode=prelim$periodparam">Preliminaries</a> | <a href="brawl.pl?mode=main$periodparam">Main</a> | <a href="brawl.pl?mode=round$periodparam">All battles</a> | <a href="brawl.pl?mode=round_current$periodparam">Current round</a></p>};

my $user_clan = $c->db_select("SELECT id, name FROM clans INNER JOIN forumuser_clans ON clans.id = forumuser_clans.clan_id WHERE forumuser_clans.user_id = ?", {}, $c->{userid});
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
		$round_data = $c->db_select("SELECT round, FLOOR(position/2) FROM brawldraw WHERE clanperiod = ? ORDER BY round, position", {}, $period);
		print $c->h3("Brawl draw data for all rounds");
	} else {
		$round_data = $c->db_select("SELECT round, FLOOR(position/2) FROM brawldraw WHERE clanperiod = ? AND round = ? ORDER BY round, position", {}, $period, $round);
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

	my $memberdata = $c->db_select("SELECT position, seat, members.id, members.name, members.rank, is_black, result, url FROM brawldraw_results INNER JOIN members ON brawldraw_results.member_id = members.id WHERE brawldraw_results.clanperiod = ? AND round = ? AND position >= ? AND position <= ?", {}, $period, $round, @positions);
	my (@top, @bottom, @urls);

	for (@$memberdata) {
		if ($_->[0] == $positions[0]) {
			$top[$_->[1]] = $_;
		} else {
			$bottom[$_->[1]] = $_;
		}
		$urls[$_->[1]] = $_->[7];
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
		my $class;
		if ($_->[5]) {
			$class = "player_black";
		} else {
			$class = "player_white";
		}
		if ($_->[6]) {
			if ($_->[6] == 1) {
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
		my $class;
		if ($_->[5]) {
			$class = "player_black";
		} else {
			$class = "player_white";
		}
		if ($_->[6]) {
			if ($_->[6] == 1) {
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
