package Clans::Form;
use strict;
use warnings;

our %categories = (
	period => {
		name => 'Global Admin',
		sort => -1,
	},
	messaging => {
		name => 'Messaging',
		sort => -0.3,
	},
	clan => {
		name => 'General Clan',
		sort => 5,
	},
	page => {
		name => 'Page Editing',
		sort => -0.7,
	},
	team => {
		name => 'Teams',
		sort => 1,
	},
	challenge => {
		name => 'Team Matches',
		sort => 2,
	},
	member => {
		name => 'Members',
		sort => 1,
	},
	alias => {
		name => 'KGS Usernames',
		sort => 4,
	},
	common => {
		name => 'Common Tasks',
		sort => -0.5,
	},
);

our %forms = (
add_period => {
	brief => 'Add a new period',
	checks => 'admin',
	categories => [ qw/admin/ ],
	acts_on => 'period+',
	description => 'Produces a new clan period based on another.',
	params => [
		old_period_id => {
			type => 'id_period',
			brief => 'Old period',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$p->{time} = time();

		if (!$c->db_do("SET \@old_period = ?, \@now_time = ?", {}, $p->{old_period_id}, $p->{time})) {
			return (0, "Database error during forum add. Get bucko to fix this; changes were not rolled back!");
		}
		# updateall.pl etc. still have hardcoded periods.
		my @SQL = (
			'SELECT @new_period := MAX(id) + 1 FROM clanperiods',
			'INSERT INTO content (name, period_id, revision, content, creator, created, current) SELECT name, @new_period, 1, content, creator, created, 1 FROM content WHERE period_id = @old_period AND current = 1;',
			'INSERT INTO clans (name, regex, tag, url, looking, forum_id, forum_private_id, forum_group_id, forum_leader_group_id, period_id, points) SELECT IF(points < 250, CONCAT(name, " (to delete)"), name), regex, tag, url, looking, forum_id, forum_private_id, forum_group_id, forum_leader_group_id, @new_period, 0 FROM clans WHERE period_id = @old_period;',
			'INSERT INTO members (name, clan_id, rank, active) SELECT members.name, c2.id, members.rank, 1 FROM members INNER JOIN clans c1 ON members.clan_id = c1.id AND c1.period_id = @old_period INNER JOIN clans c2 ON c1.tag = c2.tag AND c2.period_id = @new_period WHERE members.active = 1;',
			'INSERT INTO kgs_usernames (member_id, nick, rank, period_id, activity) SELECT m2.id, kgs_usernames.nick, kgs_usernames.rank, @new_period, @now_time FROM kgs_usernames INNER JOIN members m1 ON kgs_usernames.member_id = m1.id INNER JOIN clans c1 ON m1.clan_id = c1.id AND c1.period_id = @old_period INNER JOIN clans c2 ON c1. tag = c2.tag AND c2.period_id = @new_period INNER JOIN members m2 ON m2.name = m1.name AND m2.clan_id = c2.id;',
			'UPDATE clans c2 INNER JOIN clans c1 ON c1.period_id = @old_period AND c1.tag = c2.tag INNER JOIN members m1 ON m1.id = c1.leader_id INNER JOIN members m2 ON m2.name = m1.name AND m2.clan_id = c2.id SET c2.leader_id = m2.id WHERE c2.period_id = @new_period;',
			'INSERT INTO options (name, period_id, value) SELECT name, @new_period, value FROM options WHERE period_id = @old_period;',
			'INSERT INTO clanperiods (id, startdate, enddate) VALUES (@new_period, @now_time, @now_time + 24*3600*7*13);',
			'UPDATE clans SET forum_group_id = NULL, forum_leader_group_id = NULL WHERE period_id = @old_period;',
		);
		foreach my $SQL (@SQL) {
			if (!$c->db_do($SQL)) {
				# Cry. The cleanup here will be terrible horrible.
				return (0, "Database error during period add. Get bucko to fix this; changes were not rolled back!");
			}
		}
		$p->{period_id} = $c->db_selectone("SELECT \@new_period");
		return (1, 'Successfully added the clan period. Some clans may be tagged "to delete" and must be manually funged for now.');
	}
},
send_message => {
	brief => 'Send a message to KGS user names [not best practice]',
	checks => 'admin',
	categories => [ qw/messaging admin/ ],
	acts_on => 'period',
	description => 'Send messages to KGS users.',
	params => [
		period_id => {
			type => 'id_period',
		},
		alias_id => {
			type => 'id_kgs($period_id)',
			multi => 1,
			brief => 'Users to message',
			description => 'You can hold Ctrl to select multiple members',
		},
		message_content => {
			type => 'content_message',
			brief => "Enter your message",
			input_type => 'textarea',
		},
	],
	action => sub {
		require Clans::Message;
		my ($c, $p) = @_;
		$p->{success} = [];
		$p->{failed} = [];
		for(@{$p->{alias_id}}) {
			my $alias_name = $c->db_selectone("SELECT nick FROM kgs_usernames WHERE id = ?", {}, $_);
			my ($stat, $reason) = $c->kgs_send_message($alias_name, $p->{message_content});
			if ($stat) {
				push @{$p->{success}}, "$alias_name ($reason)";
			} else {
				push @{$p->{failed}}, "$alias_name ($reason)";
			}
		}
		$c->kgs_message_flush();
		if (@{$p->{success}}) {
			if (@{$p->{failed}}) {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).". Failures: ".join(", ", @{$p->{failed}}).".");
			} else {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).".");
			}
		} else {
			return (1, "All messages failed: ".join(", ", @{$p->{failed}}).".");
		}
	},
},
send_message_forum => {
	brief => 'Send a message to forum members',
	checks => 'admin',
	categories => [ qw/messaging admin/ ],
	acts_on => 'period',
	description => 'Send messages to KGS users.',
	params => [
		period_id => {
			type => 'id_period',
		},
		forum_id => {
			type => 'id_forum',
			multi => 1,
			brief => 'Members to message',
			description => 'You can hold Ctrl to select multiple members',
		},
		message_content => {
			type => 'content_message',
			brief => "Enter your message",
			input_type => 'textarea',
		},
	],
	action => sub {
		require Clans::Message;
		my ($c, $p) = @_;
		$p->{success} = [];
		$p->{failed} = [];
		for(@{$p->{forum_id}}) {
			my $username = $c->db_selectone("SELECT username FROM phpbb3_users WHERE user_id = ?", {}, $_);
			my ($stat, $reason) = $c->send_message($_, $p->{message_content});
			if ($stat) {
				push @{$p->{success}}, "$username ($reason)";
			} else {
				push @{$p->{failed}}, "$username ($reason)";
			}
		}
		$c->kgs_message_flush();
		if (@{$p->{success}}) {
			if (@{$p->{failed}}) {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).". Failures: ".join(", ", @{$p->{failed}}).".");
			} else {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).".");
			}
		} else {
			return (1, "All messages failed: ".join(", ", @{$p->{failed}}).".");
		}
	},
},
send_message_group => {
	brief => 'Send a message to a group of clan leaders',
	checks => 'admin',
	categories => [ qw/messaging admin/ ],
	acts_on => 'period',
	description => 'Send messages to KGS users by group (clan leaders, clan leaders for clans involved in the brawl, clan leaders for clans involved in the preliminary round, clan leaders for clans in the brawl and not in the preliminaries).',
	params => [
		period_id => {
			type => 'id_period',
		},
		recepients => {
			type => 'enum(All Clan Leaders,Brawl Clan Leaders,Prelim Clan Leaders,Nonprelim Brawl Clan Leaders)',
		},
		message_content => {
			type => 'content_message',
			brief => "Enter your message",
			input_type => 'textarea',
		},
	],
	action => sub {
		require Clans::Message;
		my ($c, $p) = @_;
		if ($p->{recepients} =~ /^All/) {
			$p->{SQL} = "SELECT id, name FROM clans WHERE clans.period_id = ? AND clans.points >= 0";
		} elsif ($p->{recepients} =~ /^Brawl/) {
			$p->{SQL} = "SELECT clans.id, clans.name FROM clans INNER JOIN teams ON teams.clan_id = clans.id INNER JOIN team_match_teams ON team_match_teams.team_id = teams.id LEFT OUTER JOIN brawl ON brawl.team_match_id = team_match_teams.team_match_id LEFT OUTER JOIN brawl_prelim ON brawl_prelim.team_match_id = team_match_teams.team_match_id WHERE clans.period_id = ? AND (brawl.period_id IS NOT NULL OR brawl_prelim.period_id IS NOT NULL) GROUP BY clans.id";
		} elsif ($p->{recepients} =~ /^Prelim/) {
			$p->{SQL} = "SELECT clans.id, clans.name FROM clans INNER JOIN teams ON teams.clan_id = clans.id INNER JOIN team_match_teams ON team_match_teams.team_id = teams.id LEFT OUTER JOIN brawl_prelim ON brawl_prelim.team_match_id = team_match_teams.team_match_id WHERE clans.period_id = ? AND brawl_prelim.period_id IS NOT NULL GROUP BY clans.id";
		} else {
			$p->{SQL} = "SELECT clans.id, clans.name, MAX(brawl.period_id), MAX(brawl_prelim.period_id) FROM clans INNER JOIN teams ON teams.clan_id = clans.id INNER JOIN team_match_teams ON team_match_teams.team_id = teams.id LEFT OUTER JOIN brawl ON brawl.team_match_id = team_match_teams.team_match_id LEFT OUTER JOIN brawl_prelim ON brawl_prelim.team_match_id = team_match_teams.team_match_id WHERE clans.period_id = ? GROUP BY clans.id";
		}
		my $clans = $c->db_select($p->{SQL}, {}, $p->{period_id});
		return (0, "Problem getting list of clans") unless $clans;
		$p->{success} = [];
		$p->{failed} = [];
		for(@$clans) {
			if (@$_ > 2) {
				next if !$_->[2] || $_->[3];
			}
			my $clan_name = $_->[1];
			my $leaders = $c->db_select("SELECT phpbb3_user_group.user_id FROM phpbb3_user_group INNER JOIN clans ON clans.forum_leader_group_id = phpbb3_user_group.group_id WHERE clans.id = ?", {}, $_->[0]);
			for (@$leaders) {
				my $username = $c->db_selectone("SELECT username FROM phpbb3_users WHERE user_id = ?", {}, $_->[0]);
				my ($stat, $reason) = $c->send_message($_, $p->{message_content});
				if ($stat) {
					push @{$p->{success}}, "$username ($reason)";
				} else {
					push @{$p->{failed}}, "$username ($reason)";
				}
			}
		}
		$c->kgs_message_flush();
		if (@{$p->{success}}) {
			if (@{$p->{failed}}) {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).". Failures: ".join(", ", @{$p->{failed}}).".");
			} else {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).".");
			}
		} else {
			return (1, "All messages failed: ".join(", ", @{$p->{failed}}).".");
		}
	},
},
send_message_clan => {
	brief => 'Send a message to members of a clan',
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/clan messaging admin/ ],
	acts_on => 'clan',
	description => 'Send messages to all KGS users in a clan.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id, $clan_id)',
			hidden => 1,
			informational => 1,
		},
		message_content => {
			type => 'content_message',
			brief => "Enter your message",
			input_type => 'textarea',
		},
	],
	action => sub {
		require Clans::Message;
		my ($c, $p) = @_;
		my $results = $c->db_select("SELECT phpbb3_user_group.user_id, phpbb3_users.username FROM phpbb3_users INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN clans ON clans.forum_group_id = phpbb3_user_group.group_id WHERE clans.id = ?", {}, $p->{clan_id});
		return (0, "Problem getting list of members") unless $results;
		$p->{success} = [];
		$p->{failed} = [];
		for(@$results) {
			my $user_id = $_->[0];
			my $username = $_->[1];
			my ($stat, $reason) = $c->send_message($user_id, $p->{message_content});
			if ($stat) {
				push @{$p->{success}}, "$username ($reason)";
			} else {
				push @{$p->{failed}}, "$username ($reason)";
			}
		}
		$c->kgs_message_flush();
		if (@{$p->{success}}) {
			if (@{$p->{failed}}) {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).". Failures: ".join(", ", @{$p->{failed}}).".");
			} else {
				return (1, "OK, message(s) sent to ".join(", ", @{$p->{success}}).".");
			}
		} else {
			return (1, "All messages failed: ".join(", ", @{$p->{failed}}).".");
		}
	},
},
remove_clan => {
	brief => 'Remove an entire clan',
	checks => 'admin',
	categories => [ qw/admin/ ],
	acts_on => 'clan-',
	description => 'Remove a clan as best as can be afforded by the system.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id, $clan_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Sanity check - will not remove clans with pure games
		$p->{num_games} = $c->db_selectone("SELECT SUM(played_pure) FROM members WHERE clan_id = ?", {}, $p->{clan_id});

		$c->db_do('SET @clan_id = ?', {}, $p->{clan_id});
		my @SQL = (
			# Safe
			'DELETE kgs_usernames FROM kgs_usernames INNER JOIN members ON kgs_usernames.member_id = members.id WHERE members.clan_id = @clan_id',

			# Remove only non-pure games.
			'DELETE games FROM games INNER JOIN members ON (games.black_id = members.id AND games.white_id IS NULL) OR (games.white_id = members.id AND games.black_id IS NULL) WHERE members.clan_id = @clan_id',

			# Remove only members who have not played pure games.
			'DELETE FROM members WHERE clan_id = @clan_id AND played_pure = 0',
			'UPDATE members SET active = 0, played = played_pure, won = won_pure WHERE clan_id = @clan_id',

			# Remove forum stuff. First gather some extra information.
			"SELECT \@leaders_group := group_id FROM phpbb3_groups WHERE group_name = 'Clan Leaders'",
			'SELECT @group_id := forum_group_id, @leader_group_id := forum_leader_group_id FROM clans WHERE id = @clan_id',
			'SELECT @leader_forum_user := g1.user_id FROM phpbb3_user_group g1 INNER JOIN phpbb3_user_group g2 ON g1.user_id = g2.user_id WHERE g1.group_id = @leader_group_id AND g2.group_id = @leaders_group',

			# Remove all members from groups.
			"DELETE FROM phpbb3_user_group WHERE group_id = \@group_id",
			"DELETE FROM phpbb3_user_group WHERE group_id = \@leader_group_id",

			# Remove voting privileges from leader.
			"DELETE FROM phpbb3_user_group WHERE group_id = \@leaders_group AND user_id = \@leader_forum_user",

			# Remove group permissions
			"DELETE FROM phpbb3_acl_groups WHERE group_id = \@leader_group_id",
			"DELETE FROM phpbb3_acl_groups WHERE group_id = \@group_id",

			# Remove groups
			'DELETE FROM phpbb3_groups WHERE group_id = @group_id',
			'DELETE FROM phpbb3_groups WHERE group_id = @leader_group_id',

			$p->{num_games} == 0 ? (
				'DELETE FROM clans WHERE id = @clan_id',
			) : (
				'UPDATE clans SET points = -100, looking = "Disbanded" WHERE id = @clan_id',
			),
		);
		foreach my $SQL (@SQL) {
			if (!$c->db_do($SQL)) {
				# Cry. The cleanup here will be terrible horrible.
				return (0, "Database error during period add. Get bucko to fix this; changes were not rolled back!");
			}
		}

		if ($p->{num_games} > 0) {
			return (1, "Removed all KGS usernames, non-pure games and members without pure games, forum groups and forum voting status. Clan remains intact.");
		} else {
			return (1, "OK, removed empty clan.");
		}
	},
},
brawl_draw => {
	brief => 'Produce draw for next round of the brawl',
	checks => 'admin',
	categories => [ qw/admin/ ],
	acts_on => 'period',
	description => 'Produces the draw for the next round of the brawl.',
	params => [
		period_id => {
			type => 'id_period',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Four cases:
		# - Asked to produce a first round, and there's few enough teams to fit.
		# - Asked to produce a first round and a preliminary round is needed.
		# - Asked to produce the first round after preliminaries.
		# - Asked to produce any other round.

		# First, let's see if this will be the first draw of any kind.
		$p->{draw_made} = $c->db_selectone("SELECT brawl.team_match_id FROM brawl WHERE brawl.period_id = ?", {}, $p->{period_id});

		# Helper routine
		my $insert_match = sub {
			my ($team1, $team2, $start_date) = @_;
			$c->db_do("INSERT INTO team_matches SET period_id = ?, start_date = ?", {}, $p->{period_id}, $start_date);
			my $match = $c->lastid;
			$c->db_do("INSERT INTO team_match_teams SET team_match_id = ?, team_no = 1, team_id = ?", {}, $match, $team1) if $team1;
			$c->db_do("INSERT INTO team_match_teams SET team_match_id = ?, team_no = 2, team_id = ?", {}, $match, $team2) if $team2;
			return $match;
		};

		# Get a list of team members.
		my $members = $c->db_select("SELECT team_id, seat_no, member_id FROM team_seats INNER JOIN teams ON team_seats.team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ?", {}, $p->{period_id});

		# Sort members into teams.
		my %team_members;
		for(@$members) {
			$team_members{$_->[0]} ||= [];
			next unless $_->[1] >= 0 && $_->[1] <= 4;
			$team_members{$_->[0]}[$_->[1]] = $_->[2];
			$team_members{$_->[0]}[5]++;
		}

		# List of matches that need seats drawn for them.
		my @matches;
		if ($p->{draw_made}) {
			# We're making a draw for round having (hopefully) got all results for the previous one.
			# First we must figure out the "current" round.
			$p->{last_round} = $c->db_selectone("SELECT MAX(round) FROM brawl NATURAL JOIN team_match_players WHERE brawl.period_id = ?", {}, $p->{period_id}) || 0;
			$p->{this_round} = $p->{last_round} + 1;
			if ($p->{last_round} == 0) {
				# We're generating round 1 based on the preliminaries.
				my $fighting_over = $c->db_select("SELECT for_position, for_team_no, COUNT(team_match_id), SUM(IF(winner IS NOT NULL,1,0)) FROM brawl_prelim INNER JOIN team_matches ON team_matches.id = brawl_prelim.team_match_id WHERE brawl_prelim.period_id = ? GROUP BY for_position, for_team_no", {}, $p->{period_id});
				$p->{fighting_over} = join ',', map { "$_->[0]=($_->[2]g/$_->[1]t)" } @$fighting_over;
				$p->{teams_unsorted} = '';
				$p->{teams_sorted} = '';
				for my $position (@$fighting_over) {
					# First ensure all positions have complete results.
					if ($position->[3] != $position->[2]) {
						return (0, "It appears that the preliminary round is not yet complete ($position->[3] results out of $position->[2] games fighting over round $position->[1]/$position->[0]).");
					}
				}
				for my $position (@$fighting_over) {
					# Get all teams fighting over position
					my $teams = $c->db_select("SELECT team_id, SUM(team_matches.id), SUM(IF(winner=team_no,1,0)) FROM brawl_prelim INNER JOIN team_matches ON team_matches.id = brawl_prelim.team_match_id INNER JOIN team_match_teams ON team_match_teams.team_match_id = brawl_prelim.team_match_id WHERE brawl_prelim.period_id = ? AND for_position = ? AND for_team_no = ? GROUP BY team_id", {}, $p->{period_id}, $position->[0], $position->[1]);
					$p->{teams_unsorted} .= "$position->[0]/$position->[1]:".(join ',', map { "$_->[0]=($_->[2].$_->[1])" } @$teams).";";
					# Sort by wins (desc) then position (asc).
					$teams = [ sort { $b->[2] <=> $a->[2] || $a->[1] <=> $b->[1] } @$teams ];
					$p->{teams_sorted} .= "$position->[0]/$position->[1]:".(join ',', map { "$_->[0]=($_->[2].$_->[1])" } @$teams).";";

					# Match should be created already.
					my $match = $c->db_selectone("SELECT team_match_id FROM brawl WHERE period_id = ? AND round = 1 AND position = ?", {}, $p->{period_id}, $position->[0]);
					# So just add team.
					$c->db_do("INSERT INTO team_match_teams SET team_match_id = ?, team_no = ?, team_id = ?", {}, $match, $position->[1], $teams->[0][0]);
				}
				@matches = map { [ $_->[0], $_[1] ] } @{$c->db_select("SELECT team_match_id, round + position FROM brawl WHERE period_id = ? AND round = 1", {}, $p->{period_id})};
			} else {
				# We're generating round n+1 based on round n > 0
				# First check round n is complete.
				my $check = $c->db_selectone("SELECT COUNT(*) - SUM(IF(winner IS NOT NULL,1,0)) FROM brawl INNER JOIN team_matches ON brawl.team_match_id = team_matches.id WHERE brawl.period_id = ? AND round = ?", {}, $p->{period_id}, $p->{last_round});
				if ($check != 0) {
					return (0, "It appears that the current round is not yet complete.");
				}

				my $winners = $c->db_select("SELECT team_id, position FROM brawl INNER JOIN team_matches ON brawl.team_match_id = team_matches.id INNER JOIN team_match_teams ON brawl.team_match_id = team_match_teams.team_match_id WHERE team_matches.winner = team_match_teams.team_no AND brawl.period_id = ? AND round = ?", {}, $p->{period_id}, $p->{last_round});
				$p->{winning_teams} = join ',', map { "$_->[1]:$_->[0]" } @$winners;
				my @next;
				for(@$winners) {
					$next[int($_->[1]/2)] ||= [];
					$next[int($_->[1]/2)][$_->[1]%2] ||= $_->[0];
				}
				for(0..$#next) {
					my $match = $insert_match->($next[$_][0], $next[$_][1], undef);
					$c->db_do("INSERT INTO brawl SET period_id = ?, round = ?, position = ?, team_match_id = ?", {}, $p->{period_id}, $p->{this_round}, $_, $match);
					push @matches, [ $match, $p->{this_round} + $_ ];
				}
			}
		} else {
			# This is the first round. First, we must decide if we need to produce a preliminary draw.
			$p->{req_points} = $c->get_option('BRAWLTEAMPOINTS', $p->{period_id});
			my @points = split /,/, $p->{req_points};

			$p->{req_members} = $c->get_option('BRAWLTEAMMINMEMBERS', $p->{period_id});

			$p->{max_rounds} = $c->get_option('BRAWLROUNDS', $p->{period_id});

			# Get a list of teams.
			my $teams = $c->db_select("SELECT teams.id, team_number, clans.points, COUNT(member_id) AS number, clans.id FROM team_members INNER JOIN teams ON team_members.team_id = teams.id INNER JOIN clans ON clans.id = teams.clan_id WHERE clans.period_id = ? AND teams.in_brawl = 1 GROUP BY teams.id HAVING number >= ?", {}, $p->{period_id}, $p->{req_members});

			# Remove all teams which do not have 5 members.
			$p->{all_teams} = join ',', map { $_->[0] } @$teams;

			$p->{current_champion} = $c->get_option('BRAWLCHAMPION', $p->{period_id});

			# For both below cases, we need to know the seed score for each team.
			for(0..$#$teams) {
				$teams->[$_][3] = $teams->[$_][2] / $points[$teams->[$_][1]-1];
				# The winner of the last brawl is always seeded top.
				$teams->[$_][3] = 9001 if $teams->[$_][4] == $p->{current_champion} && $teams->[$_][1] == 1;
			}

			# Pull out the unqualified teams.
			$p->{no_points_teams} = join ',', map { $_->[0] } grep { $_->[3] < 1 } @$teams;
			@$teams = grep { $_->[3] >= 1 } @$teams;

			# Then sort by points.
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
				
			if (@$teams > $p->{max_teams}) {
				# We must generate a preliminary round.
				$p->{this_round} = 0;

				# First, who gets auto entry?
				$p->{auto_entry} = $c->get_option('BRAWLAUTOENTRY', $p->{period_id});
				my @auto_teams = splice(@$teams, 0, $p->{auto_entry});

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
				my @fights;
				{
					my $pos = 0;
					for my $slot_num (0..$p->{remain_slots}-1) {
						my $num_teams = $p->{min_opponents} + ($slot_num > $p->{slots_on_min} ? 2 : 1);
						$fights[$slot_num] = [];
						for my $team_num (1..$num_teams) {
							push @{$fights[$slot_num]}, $teams->[$pos++];
						}
					}
				}

				# We now have an array, @fights, which contains the teams to fight over slot n, and an array, @auto_teams, which contains teams who get through automatically.

				{
					# We insert the auto teams first. They live in round 1.
					my $pos = 0;
					my @positions;
					my @games;
					for my $team (@auto_teams) {
						my $this_pos = $position_map[$pos++];
						$positions[$this_pos] = $team->[0];
					}
					for(0..$#positions) {
						$games[int($_/2)] ||= [];
						$games[int($_/2)][$_%2] ||= $positions[$_];
					}

					for (0..$#games) {
						my $match = $insert_match->($games[$_][0], $games[$_][1], undef);
						$c->db_do("INSERT INTO brawl SET period_id = ?, round = 1, position = ?, team_match_id = ?", {}, $p->{period_id}, $_, $match);
					}

					# The preliminary round is numbered 0, so let's do some insertions. Note that $pos currently tells us the nextround_pos for each group.
					my $prepos = 0;
					my $start_date = time();
					for my $group (@fights) {
						my $this_pos = $position_map[$pos++];
						for (my $t1=0; $t1 < @$group; $t1++) {
							for (my $t2=$t1+1; $t2 < @$group; $t2++) {
								my $match = $insert_match->($group->[$t1][0], $group->[$t2][0], $start_date);
								$c->db_do("INSERT INTO brawl_prelim SET period_id = ?, for_position = ?, for_team_no = ?, team_match_id = ?", {}, $p->{period_id}, int($this_pos/2), $this_pos % 2 + 1, $match);
								push @matches, [ $match, $prepos++ ];
							}
						}
					}
				}
			} else {
				$p->{this_round} = 1;
				# We are clear and can just generate a normal round.
				# We insert the auto teams first. They live in round 1.
				my $pos = 0;
				my @positions;
				my @games;
				for my $team (@$teams) {
					my $this_pos = $position_map[$pos++];
					$positions[$this_pos] = $team->[0];
				}
				for(0..$#positions) {
					$games[int($_/2)] ||= [];
					$games[int($_/2)][$_%2] ||= $positions[$_];
				}
				for (0..$#games) {
					my $match = $insert_match->($games[$_][0], $games[$_][1], undef);
					$c->db_do("INSERT INTO brawl SET period_id = ?, round = 1, position = ?, team_match_id = ?", {}, $p->{period_id}, $_, $match);
					push @matches, [ $match, $_ ];
				}
			}
		}
		for my $match (@matches) {
			for(0..4) {
				$c->db_do("INSERT INTO team_match_seats SET team_match_id = ?, seat_no = ?, black = ?", {}, $match->[0], $_, 2 - ($match->[1] + $_) % 2);
			}
			$c->db_do("INSERT INTO team_match_players SELECT team_match_seats.team_match_id, team_no, team_match_seats.seat_no, team_seats.member_id FROM team_match_seats INNER JOIN team_match_teams ON team_match_seats.team_match_id = team_match_teams.team_match_id INNER JOIN team_seats ON team_seats.team_id = team_match_teams.team_id AND team_seats.seat_no = team_match_seats.seat_no WHERE team_match_seats.team_match_id = ?", {}, $match->[0]);
		}
		return (1, "Draw successfully produced!");
	},
},
add_clan => {
	# Add clan. Autogen form on admin page.
	brief => 'Add clan',
	repeatable => 1,
	checks => 'admin',
	categories => [ qw/admin/ ],
	acts_on => 'clan+',
	description => 'Allows you to add a clan to the system. After adding, please ensure the new leader adds 4 further members before a week is up.',
	params => [
		period_id => {
			type => 'id_period',
		},
		name => {
			type => 'valid_new|name_clan($period_id)',
			brief => 'Clan name',
		},
		forum_user_id => {
			type => 'id_forum',
			brief => 'Leader on forum',
			description => 'An existing forum user must be specified to allow creation of clan groups etc.',
		},
		leader_kgs => {
			type => 'valid_new|name_kgs($period_id):valid_new|name_member($period_id)',
			brief => 'Leader on KGS',
			description => 'KGS user name of the leader.',
		},
		leader_name => {
			type => 'null_valid|valid_new|name_member($period_id)',
			brief => 'Leader\'s name',
			description => 'Name to use on clan system for the leader. Leave this blank to just use the KGS username (normal).',
		},
		tag => {
			type => 'valid_new|tag_clan($period_id)',
			brief => 'Tag',
			description => 'This must be 2-4 alphanumeric characters.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('INSERT INTO clans SET name=?, tag=?, regex=?, period_id=?;', {}, $p->{name}, $p->{tag}, $p->{tag}, $p->{period_id})) {
			return (0, "Database error during clan addition.");
		}
		$p->{actual_leader_name} = $p->{leader_name} || $p->{leader_kgs};
		$p->{clan_id} = $c->lastid;
		if (!$c->db_do('INSERT INTO members SET name=?, clan_id=?, active=1;', {}, $p->{actual_leader_name}, $p->{clan_id})) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			return (0, "Database error during leader addition.");
		}
		$p->{leader_id} = $c->lastid;
		if (!$c->db_do('INSERT INTO kgs_usernames SET nick=?, member_id=?, period_id=?, activity=?;', {}, $p->{leader_kgs}, $p->{leader_id}, $p->{period_id}, time())) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{leader_id});
			return (0, "Database error during alias addition.");
		}
		if (!$c->db_do('UPDATE clans SET leader_id=? WHERE id=?;', {}, $p->{leader_id}, $p->{clan_id})) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{leader_id});
			$c->db_do('DELETE FROM kgs_usernames WHERE member_id=?', {}, $p->{leader_id});
			return (0, "Database error during leader setting.");
		}

		# Now add the forum
		if (!$c->db_do("SET \@forum_user = ?, \@clan_id = ?", {}, $p->{forum_user_id}, $p->{clan_id})) {
			return (0, "Database error during forum add. Get bucko to fix this; changes were not rolled back!");
		}
		my @SQL = (
			# Haul out some useful values.
			"SELECT \@guest_group := group_id FROM phpbb3_groups WHERE group_name = 'GUESTS'",
			"SELECT \@registered_group := group_id FROM phpbb3_groups WHERE group_name = 'REGISTERED'",
			"SELECT \@bot_group := group_id FROM phpbb3_groups WHERE group_name = 'BOTS'",
			"SELECT \@admin_group := group_id FROM phpbb3_groups WHERE group_name = 'ADMINISTRATORS'",

			"SET \@proposals_forum = 3",
			"SELECT \@leaders_group := group_id FROM phpbb3_groups WHERE group_name = 'Clan Leaders'",
			"SELECT \@guest_group := group_id FROM phpbb3_groups WHERE group_name = 'GUESTS'",
			"SELECT \@registered_group := group_id FROM phpbb3_groups WHERE group_name = 'REGISTERED'",
			"SELECT \@bot_group := group_id FROM phpbb3_groups WHERE group_name = 'BOTS'",
			"SELECT \@admin_group := group_id FROM phpbb3_groups WHERE group_name = 'ADMINISTRATORS'",

			"SELECT \@clan_name := name FROM clans WHERE id = \@clan_id",

			# Create groups
			"INSERT INTO phpbb3_groups SET group_type = 1, group_name = \@clan_name, group_desc = ''",
			"SET \@clan_group = LAST_INSERT_ID()",
			"INSERT INTO phpbb3_groups SET group_type = 1, group_name = CONCAT(\@clan_name, ' Moderators'), group_desc = ''",
			"SET \@clan_leader_group = LAST_INSERT_ID()",

			# Add leader to groups
			"INSERT INTO phpbb3_user_group SET group_id = \@clan_group, user_id = \@forum_user, user_pending = 0, group_leader = 1",
			"INSERT INTO phpbb3_user_group SET group_id = \@clan_leader_group, user_id = \@forum_user, user_pending = 0, group_leader = 1",
			"INSERT INTO phpbb3_user_group SET group_id = \@leaders_group, user_id = \@forum_user, user_pending = 0, group_leader = 0",

			# Add clan forum
			"SELECT \@right := right_id FROM phpbb3_forums WHERE forum_id = 47",
			"UPDATE phpbb3_forums SET left_id = left_id + 2 WHERE left_id > \@right",
			"UPDATE phpbb3_forums SET right_id = right_id + 2 WHERE right_id >= \@right",
			"INSERT INTO phpbb3_forums SET parent_id = 47, left_id = \@right, right_id = \@right + 1, forum_name = \@clan_name, forum_desc = '', forum_type = 1, forum_parents='a:1:{i:48;a:2:{i:0;s:19:\"Private Clan Forums\";i:1;i:0;}}'",
			"SELECT \@newforum := LAST_INSERT_ID()",

			# Add clan leader group to proposals stuff
			"INSERT INTO phpbb3_acl_groups SELECT \@clan_leader_group, \@proposals_forum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_PROPOSALS')",

			# Set options for clan groups
			"INSERT INTO phpbb3_acl_groups SELECT \@clan_leader_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_MOD_STANDARD', 'ROLE_FORUM_FULL')",
			"INSERT INTO phpbb3_acl_groups SELECT \@clan_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_POLLS')",

			# This was present in the DB, so must be needed(!)
			"INSERT INTO phpbb3_acl_groups SELECT \@clan_group, 48, auth_option_id, 0, 1 FROM phpbb3_acl_options WHERE auth_option IN ('f_', 'f_list')",
			"INSERT INTO phpbb3_acl_groups SELECT \@clan_leader_group, 48, auth_option_id, 0, 1 FROM phpbb3_acl_options WHERE auth_option IN ('f_', 'f_list')",

			# Stuff for standard groups
			"INSERT INTO phpbb3_acl_groups SELECT \@guest_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_READONLY')",
			"INSERT INTO phpbb3_acl_groups SELECT \@registered_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_POLLS')",
			"INSERT INTO phpbb3_acl_groups SELECT \@bot_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_BOT')",
			"INSERT INTO phpbb3_acl_groups SELECT \@admin_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_FULL')",

			"UPDATE clans SET forum_id = \@newforum, forum_leader_group_id = \@clan_leader_group, forum_group_id = \@clan_group WHERE id = \@clan_id",
		);
		foreach my $SQL (@SQL) {
			if (!$c->db_do($SQL)) {
				# Cry. The cleanup here will be terrible horrible.
				return (0, "Database error during forum add. Get bucko to fix this; changes were not rolled back!");
			}
		}
		my $results = $c->db_select("SELECT \@newforum, \@clan_group, \@clan_leader_group");
		if ($results && @$results) {
			$p->{forum_id} = $results->[0][0];
			$p->{forum_group_id} = $results->[0][1];
			$p->{forum_leader_group_id} = $results->[0][2];
		}

		# Hopefully the next line should fix issues with the index not updating.
		# TODO it doesn't.
		unlink("forum/cache/sql_e4646055f69bcd0cb7ef3bbff697ee0c.php");

		return (1, "Clan and forum added.");
	}
},
add_page => {
	# Edit page. Invoked only from custom forms.
	brief => 'Add page',
	checks => 'admin',
	categories => [ qw/page admin/ ],
	acts_on => 'page+',
	params => [
		period_id => {
			type => 'id_period',
		},
		page_name => {
			type => 'valid_new|name_page($period_id)',
		},
		based_on => {
			type => 'name_page($period_id)',
			brief => 'Template',
			readonly => [ ],
		},
		content => {
			type => 'content_page($period_id,$based_on)',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Is it new? What revision?
		$p->{time} = time();
		$p->{forum_user_id} = $c->{phpbbsess}{userid};
		if (!$c->db_do("INSERT INTO content SET name=?, content=?, revision=?, period_id=?, created=?, creator=?, current=?", {}, $p->{page_name}, $p->{content}, 1, $p->{period_id}, $p->{time}, $p->{forum_user_id}, 1)) {
		my $name = $c->param('page');
			return (0, "Database error.");
		}
		return (1, "Page created.");
	}
},
change_log_format => {
	brief => 'Change log format',
	checks => 'admin',
	categories => [ qw/admin/ ],
	override_category => 'period',
	params => [
		period_id => {
			type => 'id_period',
			hidden => 1,
		},
		action_name => {
			type => 'name_action()',
		},
		action_format => {
			type => 'format_action($action_name)',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if ($c->db_do("REPLACE INTO log_formats SET action = ?, format = ?", {}, $p->{action_name}, $p->{action_format})) {
			return (1, "Successfully changed format.");
		} else {
			return (0, "Database error.");
		}
	}
},
change_page => {
	# Edit page. Invoked only from custom forms.
	brief => 'Change page',
	checks => 'admin',
	categories => [ qw/page admin/ ],
	acts_on => 'page',
	params => [
		period_id => {
			type => 'id_period',
		},
		page_name => {
			type => 'name_page($period_id)',
		},
		revision => {
			type => 'revision_page($period_id,$page_name)',
		},
		content => {
			type => 'content_page($period_id,$page_name,$revision)',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Is it new? What revision?
		$p->{lastrevision} = $c->db_selectone("SELECT MAX(revision) FROM content WHERE name = ? AND period_id = ?", {}, $p->{page_name}, $p->{period_id});
		if ($p->{lastrevision}) {
			$p->{newrevision} = $p->{lastrevision} + 1;
		} else {
			$p->{newrevision} = 1;
		}
		$p->{time} = time();
		$p->{forum_user_id} = $c->{phpbbsess}{userid};
		if (!$c->db_do("INSERT INTO content SET name=?, content=?, revision=?, period_id=?, created=?, creator=?, current=?", {}, $p->{page_name}, $p->{content}, $p->{newrevision}, $p->{period_id}, $p->{time}, $p->{forum_user_id}, 1)) {
		my $name = $c->param('page');
			return (0, "Database error.");
		}
		$c->db_do("UPDATE content SET current=0 WHERE name=? AND period_id=? AND revision!=?", {}, $p->{page_name}, $p->{period_id}, $p->{newrevision});
		return (1, "Text updated.");
	}
},
change_clan_name => {
	# Alter clan's name.
	brief => 'Change clan name',
	checks => 'clan_leader($clan_id)|period_active($period_id)',
	categories => [ qw/clan admin/ ],
	acts_on => 'clan',
	description => 'Alter the clan\'s name. Please keep the name sensible, with no profanity etc.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		oldname => {
			type => 'name_clan($period_id, $clan_id)',
			hidden => 1,
			informational => 1,
		},
		newname => {
			type => 'valid_new|name_clan($period_id, $clan_id)',
			brief => 'New name',
			description => 'There is a limited set of symbols you can use. If you get an error because of some (sensible) symbol you wanted, please complain on the Admin Stuff forum.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		# TODO rename forums.
		if (!$c->db_do('UPDATE clans SET name=? WHERE id=?;', {}, $p->{newname}, $p->{clan_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Clan name changed.");
		}
	},
},
change_clan_tag => {
	# Set clan's tag.
	brief => 'Change clan tag',
	checks => 'clan_leader($clan_id)|period_active($period_id)',
	categories => [ qw/clan admin/ ],
	acts_on => 'clan',
	description => 'Alter the clan\'s tag. Please keep the tag free of profanity etc.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		oldtag => {
			type => 'valid|tag_clan($period_id, $clan_id)',
			brief => 'Old tag',
			informational => 1,
		},
		newtag => {
			type => 'valid_new|tag_clan($period_id, $clan_id)',
			brief => 'New tag',
			description => 'You may use between 2 and 4 alphanumeric characters. If you have a good reason for using other symbols, please complain on the Admin Stuff forum.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('UPDATE clans SET tag=?, regex=? WHERE id=?;', {}, $p->{newtag}, $p->{newtag}, $p->{clan_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Clan tag changed.");
		}
	},
},
change_clan_url => {
	# Set clan's URL
	brief => 'Change clan website address',
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/clan admin/ ],
	acts_on => 'clan',
	description => 'With this form you may give a website address people can visit for more information on your clan.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		oldurl => {
			type => 'valid|null_valid|url_clan($period_id,$clan_id)',
			brief => 'Old URL',
			informational => 1,
		},
		newurl => {
			type => 'null_valid|url_clan($period_id,$clan_id)',
			brief => 'New URL',
			description => 'If the check on this fails, please mention it on the Admin Stuff forum.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('UPDATE clans SET url=? WHERE id=?;', {}, $p->{newurl}, $p->{clan_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Clan website address changed.");
		}
	},
},
change_clan_info => {
	# Set info field
	brief => 'Change clan description',
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/clan admin/ ],
	acts_on => 'clan',
	description => 'Here you may set a description for your clan. The first line will be shown on the last column of the main summary and the rest will be shown on your clan\'s info page.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		oldinfo => {
			type => 'valid|null_valid|info_clan($period_id,$clan_id)',
			brief => 'Old description',
			informational => 1,
		},
		newinfo => {
			type => 'null_valid|size(40)|info_clan($period_id,$clan_id)',
			brief => 'New description',
			description => 'If your chosen description is not allowed, and you\'re trying to put something sensible in, please mention it on the Admin Stuff forum.',
			input_type => 'textarea',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('UPDATE clans SET looking=? WHERE id=?', {}, $p->{newinfo}, $p->{clan_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Changed clan info.");
		}
	},
},
change_clan_leader => {
	brief => 'Change displayed clan leader',
	checks => 'clan_leader($clan_id)|period_active($period_id)',
	categories => [ qw/clan admin/ ],
	acts_on => 'clan',
	description => 'This changes the member who will be listed as the leader when people look at the summary page etc. It does not grant the member any permissions (you should do this by fiddling with forum groups).',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
			brief => 'New leader',
			description => 'The new member you want displayed as the leader for your clan',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('UPDATE clans SET leader_id=? WHERE id=?', {}, $p->{member_id}, $p->{clan_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Changed clan leader.");
		}
	},
},
add_team_game => {
	brief => 'Add team game',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/clan admin/ ],
	override_category => 'challenge',
	extra_category => 'common',
	description => 'This form allows you to let the system know that one of your members has played a team game. Please find the game on the KGS archives and put the URL in the form below.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
			hidden => 1,
		},
		url => {
			type => 'text',
			brief => 'Game URL',
			description => 'Link to the game at the KGS archives',
		},
		oinvert => {
			type => 'boolean',
			override => 1,
			brief => 'Force acceptance of inverted colours',
		},
		onr => {
			type => 'boolean',
			override => 1,
			brief => 'Force acceptance of NR/Jigo',
		},
		obadrules => {
			type => 'boolean',
			override => 1,
			brief => 'Force acceptance of bad rules',
		},
		oreplace => {
			type => 'boolean',
			override => 1,
			brief => 'Force replacing existing game',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		if ($p->{url} =~ m{^default:(\w+)([><])(\w+)$}) {
			$p->{black} = $1;
			$p->{white} = $3;
			$p->{result} = $2 eq '>' ? 'B' : 'W';
			if (!$c->is_admin) {
				return (0, "Only admins can add defaults.");
			}
		} elsif ($p->{url} =~ m[^http]) {
			if ($p->{url} !~ m[http://files.gokgs.com/games/] && !$c->is_admin) {
				return (0, "Only admins can add arbitrary urls. Please add one from the KGS archives.");
			}
			use LWP::Simple;
			$p->{content} = get($p->{url});
			if (!$p->{content}) {
				return (0, "The URL you provided could not be loaded, or pointed to an empty file. Please check you copied it correctly.");
			}

			$p->{black} = $1 if ($p->{content} =~ /PB\[([^\]]+)\]/);
			$p->{white} = $1 if ($p->{content} =~ /PW\[([^\]]+)\]/);

			$p->{result} = $1 if ($p->{content} =~ /RE\[([BW])\+/);

			$p->{maintime} = $1 if ($p->{content} =~ /TM\[(\d+)\]/);
			$p->{overtime} = $1 if ($p->{content} =~ /OT\[([^\]]+)\]/);
			$p->{komi} = $1 if ($p->{content} =~ /KM\[([^\]]+)\]/);
			$p->{rules} = $1 if ($p->{content} =~ /RU\[([^\]]+)\]/);
			$p->{size} = $1 if ($p->{content} =~ /SZ\[([^\]]+)\]/);

			$p->{content} = substr($p->{content},0,300);

			if (!$p->{maintime} || $p->{maintime} < 1200) {
				$p->{badrules} = 'maintime';
			} elsif (!$p->{overtime}
				|| ($p->{overtime} =~ m[(\d+)/(\d+) Canadian] && ($2 < 300 || $1 > 30))
				|| ($p->{overtime} =~ m[(\d+)x(\d+) byo-yomi] && ($1 < 3 || $2 < 20))
				|| ($p->{overtime} !~ m[(\d+)/(\d+) Canadian] && $p->{overtime} !~ m[(\d+)x(\d+) byo-yomi])) {
				$p->{badrules} = 'overtime';
			} elsif (!$p->{komi} || $p->{komi} != 6.5) {
				$p->{badrules} = 'komi';
			} elsif (!$p->{rules} || $p->{rules} ne 'Japanese') {
				$p->{badrules} = 'ruleset';
			} elsif (!$p->{size} || $p->{size} != 19) {
				$p->{badrules} = 'size';
			}

			if ($p->{badrules} && !$p->{obadrules}) {
				return (0, "Game has bad ruleset ($p->{badrules})", "obadrules", "Check here to allow the game to pass anyway.");
			}
		} else {
			return (0, "Invalid URL.");
		}

		unless($p->{black} && $p->{white}) {
			return (0, "Could not find player names.");
		}

		if (!$p->{result} && !$p->{nr}) {
			return (0, "Game has no result.", "nr", "Check here to allow the game to pass anyway.");
		}

		$p->{black_id} = $c->db_selectone("SELECT member_id FROM kgs_usernames WHERE period_id = ? AND nick = ?", {}, @$p{qw/period_id black/});
		$p->{white_id} = $c->db_selectone("SELECT member_id FROM kgs_usernames WHERE period_id = ? AND nick = ?", {}, @$p{qw/period_id white/});

		unless($p->{black_id} && $p->{white_id}) {
			return (0, "Could not find player's info in system.");
		}

		$p->{black_clan} = $c->db_selectone("SELECT clan_id FROM members WHERE id = ?", {}, $p->{black_id});
		$p->{white_clan} = $c->db_selectone("SELECT clan_id FROM members WHERE id = ?", {}, $p->{white_id});

		if (!$p->{black_clan} || !$p->{white_clan}) {
			return (0, "Members appear not to be in clans.");
		}

		if ($p->{black_clan} != $p->{clan_id} && $p->{white_clan} != $p->{clan_id} && !$c->is_admin) {
			return (0, "This game has nothing to do with your clan...");
		}

		my $match = $c->db_select("SELECT tm.id, s.seat_no, pb.team_no, pw.team_no, s.black, s.winner FROM team_matches tm INNER JOIN team_match_seats s ON s.team_match_id = tm.id INNER JOIN team_match_players pb ON pb.team_match_id = tm.id AND pb.seat_no = s.seat_no INNER JOIN team_match_players pw ON pw.team_match_id = tm.id AND pw.seat_no = s.seat_no WHERE tm.period_id = ? AND pb.member_id = ? AND pw.member_id = ? ORDER BY s.winner LIMIT 2", {}, @$p{qw/period_id black_id white_id/});

		if (@$match > 1 && !$match->[1][4]) {
			return (0, "Oh dear; there seems to be multiple possible matches for this game.");
		} elsif (@$match == 0) {
			return (0, "Could not find a game with these players");
		}

		$match = $match->[0];

		@$p{qw/match_id seat our_black_team_no our_white_team_no db_black_team_no db_result/} = @$match;

		$p->{colour_correct} = $p->{our_black_team_no} == $p->{db_black_team_no};

		if (!$p->{colour_correct} && !$p->{oinvert}) {
			return (0, "Ack! Colours are inverted!", "oinvert", "Check here to allow the game to pass with inverted colours.");
		} elsif ($p->{db_result} && !$p->{oreplace}) {
			return (0, "A result already exists for this match.", "oreplace", "Check here to allow the game to replace the old one.");
		} elsif (!$p->{result}) {
			return (0, "Only administrators can add NR matches.", "onores", "Check here to allow the game to be added despite having no result.");
		}

		if ($p->{result} eq 'B') {
			$p->{real_result} = $p->{our_black_team_no};
		} elsif ($p->{result} eq 'W') {
			$p->{real_result} = $p->{our_white_team_no};
		} else {
			$p->{real_result} = 0;
		}

		# We're ready!
		$c->db_do("UPDATE team_match_seats SET url=?, winner=? WHERE team_match_id = ? AND seat_no = ?", {}, @$p{qw/url real_result match_id seat/});

		# Can we infer a winrar?
		my $wins = $c->db_select("SELECT SUM(IF(winner IS NULL,1,0)), SUM(IF(winner=0,1,0)), SUM(IF(winner=1,1,0)), SUM(IF(winner=2,1,0)) FROM team_match_seats WHERE team_match_id=?", {}, $p->{match_id});
		@$p{qw/games_unplayed games_nr games_t1 games_t2/} = @{$wins->[0]};
		$p->{total_games} = $p->{games_unplayed} + $p->{games_t1} + $p->{games_t2} + $p->{games_nr};
		$p->{needed_games} = int(($p->{total_games} - int($p->{games_nr}/2))/2)+1;
		if ($p->{games_t1} >= $p->{needed_games}) {
			$p->{winner} = 1;
		} elsif ($p->{games_t2} >= $p->{needed_games}) {
			$p->{winner} = 2;
		} elsif ($p->{games_unplayed} == 0) {
			$p->{winner} = $c->db_selectone("SELECT winner FROM team_match_seats WHERE result IS NOT NULL AND team_match_id=? ORDER BY seat_no LIMIT 1", {}, $p->{match_id});
		}
		if ($p->{winner}) {
			$c->db_do("UPDATE team_matches SET winner=? WHERE id=?", {}, @$p{qw/winner match_id/});
			return (1, "Added game and inferred final result");
		}
		return (1, "Added game");
	},
},
change_clan_points => {
	brief => 'Change clan points',
	repeatable => 1,
	checks => 'admin',
	categories => [ qw/member clan admin/ ],
	acts_on => 'clan',
	description => 'Here you can give point bonusses or penalties to clans who have behaved/misbehaved.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'null_valid|id_member($period_id,$clan_id)',
			brief => 'Member, if any, to get credit',
		},
		member_name => {
			type => 'null_valid|name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
		change_type => {
			type => 'enum(bonus,penalty)',
			brief => 'Change type',
		},
		change_value => {
			type => 'int_positive',
			brief => 'Change amount',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		if ($p->{change_type} eq 'bonus') {
			$p->{change} = $p->{change_value};
		} else {
			$p->{change} = -$p->{change_value};
		}

		$c->db_do("UPDATE clans SET points = points + ? WHERE id = ?", {}, $p->{change}, $p->{clan_id}) or return (0, "Database error.");

		return (1, "Points altered.");
	},
},
add_member => {
	brief => 'Add member',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/member clan admin/ ],
	acts_on => 'member+',
	next_form => 'add_kgs_username',
	extra_category => 'common',
	description => 'You can add a new member to your clan with this form. If you just want to add another KGS username to an existing member, you\'re on the wrong form.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_kgs => {
			type => 'valid_new|name_kgs($period_id)',
			brief => 'KGS username',
			description => 'This should be the KGS username this member will play clan games with.',
		},
		member_name => {
			type => 'default($member_kgs):valid_new|name_member($period_id, $clan_id)',
			brief => 'Member name',
			description => 'This is the dislayed name of member on the clan system (leave blank to use KGS username, which most people do)',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		$p->{max_members} = $c->get_option('MEMBERMAX', $p->{period_id});
		$p->{current_members} = $c->db_selectone('SELECT COUNT(members.id) FROM members WHERE members.clan_id = ? AND members.active = 1', {}, $p->{clan_id});
		if ($p->{current_members} >= $p->{max_members}) {
			return (0, "Sorry, your clan has too many members.");
		}

		if (!$c->db_do('INSERT INTO members SET name=?, clan_id=?, active=1', {}, $p->{member_name}, $p->{clan_id})) {
			return (0, "Database error.");
		}

		$p->{member_id} = $c->lastid;
		$p->{time} = time();
		if (!$c->db_do('INSERT INTO kgs_usernames SET nick=?, member_id=?, period_id=?, activity=?', {}, $p->{member_kgs}, $p->{member_id}, $p->{period_id}, $p->{time})) {
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{member_id});
			return (0, "Database error.");
		}
		return (1, "Member added.");
	},
},
add_private_clan_forum => {
	brief => 'Add private clan forum',
	checks => 'clan_leader($clan_id)|period_active($period_id)',
	categories => [ qw/clan admin/ ],
	acts_on => 'clan',
	description => 'With this form, you can add a private forum for your clan\'s members. Only people in your clan\'s members group on the forum (and of course admins) will be able to see it.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;

		my $clan_info = $c->clan_info($p->{clan_id});
		$p->{forum_private_id} = $clan_info->{forum_private_id};

		if ($p->{forum_private_id}) {
			return (0, "Your clan already has a private forum!.");
		}

		# Let's go!
		if (!$c->db_do("SELECT \@clan_id := id, \@clan_group := forum_group_id, \@clan_leader_group := forum_leader_group_id, \@clan_name := name FROM clans WHERE id = ?", {}, $p->{clan_id})) {
			return (0, "Database error.");
		}
		my @SQL = (
			# Create forum
			"SELECT \@right := right_id FROM phpbb3_forums WHERE forum_id = 48",
			"UPDATE phpbb3_forums SET left_id = left_id + 2 WHERE left_id > \@right",
			"UPDATE phpbb3_forums SET right_id = right_id + 2 WHERE right_id >= \@right",
			"INSERT INTO phpbb3_forums SET parent_id = 48, left_id = \@right, right_id = \@right + 1, forum_name = \@clan_name, forum_desc = '', forum_type = 1, forum_parents='a:1:{i:48;a:2:{i:0;s:19:\"Private Clan Forums\";i:1;i:0;}}'",
			"SELECT \@newforum := LAST_INSERT_ID()",

			# Set options for clan groups
			"INSERT INTO phpbb3_acl_groups SELECT \@clan_leader_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_MOD_STANDARD', 'ROLE_FORUM_FULL')",
			"INSERT INTO phpbb3_acl_groups SELECT \@clan_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_POLLS')",

			# Set options for standard groups
			"SELECT \@guest_group := group_id FROM phpbb3_groups WHERE group_name = 'GUESTS'",
			"SELECT \@registered_group := group_id FROM phpbb3_groups WHERE group_name = 'REGISTERED'",
			"SELECT \@bot_group := group_id FROM phpbb3_groups WHERE group_name = 'BOTS'",
			"SELECT \@admin_group := group_id FROM phpbb3_groups WHERE group_name = 'ADMINISTRATORS'",
			"INSERT INTO phpbb3_acl_groups SELECT \@guest_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_NOACCESS')",
			"INSERT INTO phpbb3_acl_groups SELECT \@registered_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_NOACCESS')",
			"INSERT INTO phpbb3_acl_groups SELECT \@bot_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_NOACCESS')",
			"INSERT INTO phpbb3_acl_groups SELECT \@admin_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_FULL')",

			"UPDATE clans SET forum_private_id = \@newforum WHERE id = \@clan_id",
		);
		foreach my $SQL (@SQL) {
			if (!$c->db_do($SQL)) {
				# Cry. The cleanup here will be terrible horrible.
				return (0, "Database error.");
			}
		}
		return (1, "Added private forum.");
	}
},
remove_member => {
	brief => 'Remove clan member',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/member clan admin/ ],
	acts_on => 'member-',
	description => 'You can use this to remove a member from your clan. If they have any clan games, they will have all of their KGS names removed, so that they are marked inactive and won\'t count towards your total when adding new members. This means any games they played still count for your clan, and they will still be pure games for both players if played against another clan.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$p->{game_id} = $c->db_selectone("SELECT id FROM games WHERE white_id = ? OR black_id = ?", {}, $p->{member_id}, $p->{member_id});
		if (!$p->{game_id}) {
			if (!$c->db_do('DELETE FROM kgs_usernames WHERE member_id=?', {}, $p->{member_id}) || !$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{member_id})) {
				return (0, "Database error.");
			} else {
				return (1, "Removed member from clan!.");
			}
		} else {
			if (!$c->db_do('DELETE FROM kgs_usernames WHERE member_id=?', {}, $p->{member_id}) || !$c->db_do('UPDATE members SET active=0 WHERE id=?', {}, $p->{member_id})) {
				return (0, "Database error.");
			} else {
				return (1, "Member had played games, hence only removed KGS user names.");
			}
		}
	},
},
add_challenge => {
	brief => 'Challenge a clan',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/challenge clan admin/ ],
	acts_on => 'challenge+',
	description => 'This form allows you to challenge another clan. The other clan can pick which team they respond to (you may want to agree this with them beforehand). They must respond within 2 weekly updates.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		cclan_id => {
			type => 'id_clan($period_id)',
			brief => 'Clan to challenge',
			readonly => [],
		},
		cclan_name => {
			type => 'name_clan($period_id,$cclan_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;

		if ($p->{cclan_id} == $p->{clan_id}) {
			return (0, "You can't challenge your own clan!");
		}

		if ($c->db_selectone("SELECT id FROM challenges WHERE challenger_team_id = ? AND challenged_clan_id = ?", {}, $p->{team_id}, $p->{cclan_id})) {
			return (0, "Sorry, you already have an active challenge to that clan for this team.");
		}

		# Check the challenge makes sense...
		$p->{req_points} = $c->get_option('BRAWLMEMBERPOINTS', $p->{period_id});
		$p->{chal_qual_players} = $c->db_selectone("SELECT COUNT(*) FROM members WHERE members.clan_id = ? AND members.played + members.played_pure >= ?", {}, $p->{cclan_id}, $p->{req_points});
		$p->{our_seats} = $c->db_selectone("SELECT COUNT(*) FROM team_seats WHERE team_seats.team_id = ?", {}, $p->{team_id});
		if ($p->{chal_qual_players} < 5) {
			return (0, "The opposing clan does not have enough qualified members to make a team. Please ensure the opposing clan is ready to meet your challenge.");
		} elsif ($p->{our_seats} != 5) {
			return (0, "Your team does not have a full roster. Please ensure your team has a full roster before sending challenges.");
		}

		# Send challenge.
		$p->{time} = time();
		if ($c->db_do("INSERT INTO challenges SET challenger_team_id = ?, challenged_clan_id = ?, challenge_date = ?", {}, $p->{team_id}, $p->{cclan_id}, $p->{time})) {
			$p->{challenge_id} = $c->lastid;
			$p->{forum_id} = $c->db_selectone("SELECT forum_id FROM clans WHERE id=?", {}, $p->{cclan_id});
			($p->{post_id}, $p->{topic_id}) = $c->forum_post_or_reply($p->{forum_id}, "Team Challenges", "Challenge from $p->{clan_name}", $c->render_clan($p->{clan_id}, $p->{clan_name}).qq|'s $p->{team_name} team has challenged your clan to a battle. You must <a href="/admin.pl?form=accept_challenge&accept_challenge_challenge_id=$p->{challenge_id}&accept_challenge_changed=challenge_id">accept</a> or <a href="/admin.pl?form=decline_challenge&decline_challenge_challenge_id=$p->{challenge_id}&decline_challenge_changed=challenge_id">decline</a> within a week or get a penalty of 5 points.|, "00000000");
			$c->db_do("UPDATE challenges SET forum_post_id = ? WHERE id = ?", {}, $p->{post_id}, $p->{challenge_id});
			return (1, "OK; sent challenge.");
		} else {
			return (0, "Database error.");
		}
	},
},
accept_challenge => {
	brief => 'Accept a challenge',
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/challenge team clan admin/ ],
	acts_on => 'challenge-,team_match+',
	override_category => 'challenge',
	description => 'This form allows you to accept a challenge sent to your clan.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		challenge_id => {
			type => 'id_challenge($period_id,$clan_id)',
			brief => 'Challenge to accept'
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
			brief => 'Team you wish to play if accepting'
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;

		$p->{time} = time();
		$p->{chal_team_id} = $c->db_selectone("SELECT challenger_team_id FROM challenges WHERE id = ?", {}, $p->{challenge_id});
		$p->{post_id} = $c->db_selectone("SELECT forum_post_id FROM challenges WHERE id = ?", {}, $p->{challenge_id});

		# First, ensure there are no scheduling conflicts
		if ($c->db_selectone("SELECT tm1.member_id FROM team_seats ts1 INNER JOIN team_seats ts2 INNER JOIN team_match_players tm1 ON ts1.member_id = tm1.member_id INNER JOIN team_match_players tm2 ON ts2.member_id = tm2.member_id AND tm1.team_match_id = tm2.team_match_id AND tm1.seat_no = tm2.seat_no INNER JOIN team_match_seats ts ON ts.team_match_id = tm1.team_match_id AND ts.seat_no = tm1.seat_no WHERE ts.winner IS NULL AND ts1.team_id = ? AND ts2.team_id = ?", {}, $p->{chal_team_id}, $p->{team_id})) {
			return (0, "Scheduling conflict; a pair of players who this match would draw against each other are already playing each other in a different, active match. Please ensure this match is complete first.");
		}

		# Next, ensure that both teams have a complete roster.
		$p->{chal_seats} = $c->db_selectone("SELECT COUNT(*) FROM team_seats WHERE team_seats.team_id = ?", {}, $p->{chal_team_id});
		$p->{our_seats} = $c->db_selectone("SELECT COUNT(*) FROM team_seats WHERE team_seats.team_id = ?", {}, $p->{team_id});
		if ($p->{chal_seats} != 5) {
			return (0, "The opposing team does not have a full roster. Please ensure both teams have a full roster before continuing.");
		} elsif ($p->{our_seats} != 5) {
			return (0, "Your team does not have a full roster. Please ensure both teams have a full roster before continuing.");
		}

		# Now, create the match.
		$c->db_do("DELETE FROM challenges WHERE id = ?", {}, $p->{challenge_id}) or return (0, "Database error.");
		$c->db_do("INSERT INTO team_matches SET start_date = ?, period_id = ?", {}, $p->{time}, $p->{period_id}) or return (0, "Database error.");
		$p->{match_id} = $c->lastid;
		$c->db_do("INSERT INTO team_match_teams SET team_match_id = ?, team_no = 1, team_id = ?", {}, $p->{match_id}, $p->{chal_team_id}) or return (0, "Database error.");
		$c->db_do("INSERT INTO team_match_teams SET team_match_id = ?, team_no = 2, team_id = ?", {}, $p->{match_id}, $p->{team_id}) or return (0, "Database error.");
		$p->{offset} = int(rand()*2)%2;
		for(0..4) {
			$c->db_do("INSERT INTO team_match_seats SET team_match_id = ?, seat_no = ?, black = ?", {}, $p->{match_id}, $_, 2 - (($p->{offset} + $_) % 2)) or return (0, "Database error.");
		}
		$c->db_do("INSERT INTO team_match_players SELECT team_match_seats.team_match_id, team_no, team_match_seats.seat_no, team_seats.member_id FROM team_match_seats INNER JOIN team_match_teams ON team_match_seats.team_match_id = team_match_teams.team_match_id INNER JOIN team_seats ON team_seats.team_id = team_match_teams.team_id AND team_seats.seat_no = team_match_seats.seat_no WHERE team_match_seats.team_match_id = ?", {}, $p->{match_id}) or return (0, "Database error.") or return (0, "Database error.");

		# Also update the forum post.
		if ($p->{post_id}) {
			$p->{user_name} = $c->db_selectone("SELECT username FROM phpbb3_users WHERE user_id = ?", {}, $c->{userid});
			$c->db_do(qq|UPDATE phpbb3_posts SET post_text = CONCAT(post_text, "\n\nThis challenge was accepted by $p->{user_name} using team $p->{team_name}.") WHERE post_id = ?|, {}, $p->{post_id}) or return (0, "Database error.");
		}
		
		return (1, "OK; accepted challenge.");
	},
},
decline_challenge => {
	brief => 'Decline a challenge',
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/challenge clan admin/ ],
	acts_on => 'challenge-',
	description => 'This form allows you to accept a challenge sent to your clan.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		challenge_id => {
			type => 'id_challenge($period_id,$clan_id)',
			brief => 'Challenge to decline'
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Update the forum post.
		$p->{post_id} = $c->db_selectone("SELECT forum_post_id FROM challenges WHERE id = ?", {}, $p->{challenge_id});
		if ($p->{post_id}) {
			$p->{user_name} = $c->db_selectone("SELECT username FROM phpbb3_users WHERE user_id = ?", {}, $c->{userid});
			$c->db_do(qq|UPDATE phpbb3_posts SET post_text = CONCAT(post_text, "\n\nThis challenge was declined by $p->{user_name}.") WHERE post_id = ?|, {}, $p->{post_id}) or return (0, "Database error.");
		}
		
		if (!$c->db_do("DELETE FROM challenges WHERE id = ?", {}, $p->{challenge_id})) {
			return (0, "Database error deleting challenge.");
		} else {
			return (1, "OK, you declined the challenge.");
		}
	},
},
add_team => {
	brief => 'Add team',
	checks => 'clan_moderator($clan_id)|period_predraw($period_id)',
	categories => [ qw/team clan admin/ ],
	acts_on => 'team+',
	next_form => 'change_team_members',
	description => 'This form allows you to add a new team for your clan. Note that it currently does not check you have met the requirements for entering teams into the brawl, so even if you can add a team it doesn\'t mean it will be entered into the brawl.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_name => {
			type => 'valid_new|name_team($period_id,$clan_id)',
			description => 'All teams are required to have a name. If you can\'t think of one, suggested names are variations along the themes of "Warriors", "Crushers" or "Hamsters".',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$p->{top_team} = $c->db_selectone("SELECT MAX(team_number) FROM teams WHERE clan_id = ?", {}, $p->{clan_id});
		if ($c->db_do('INSERT INTO teams SET name=?, clan_id=?, team_number=?', {}, $p->{team_name}, $p->{clan_id}, $p->{top_team}+1)) {
			$p->{team_id} = $c->lastid;
			return (1, "Added new team.");
		} else {
			return (0, "Database error.");
		}
	},
},
change_team_order => {
	brief => 'Change order of teams',
	checks => 'clan_moderator($clan_id)|period_predraw($period_id)',
	categories => [ qw/team clan admin/ ],
	acts_on => 'team',
	description => 'You can use this form to reorder your teams (for example, to change which gets automatically entered into the brawl). Moving a team up gives it higher priority.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		updown => {
			type => 'enum(Up,Down)',
			brief => 'Direction to move',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$p->{old_number} = $c->db_selectone("SELECT team_number FROM teams WHERE id = ?", {}, $p->{team_id});
		if ($p->{updown} eq 'Down') {
			$p->{swap_team_id} = $c->db_selectone("SELECT id FROM teams WHERE clan_id = ? AND team_number > ? ORDER BY team_number ASC", {}, $p->{clan_id}, $p->{old_number});
		} else {
			$p->{swap_team_id} = $c->db_selectone("SELECT id FROM teams WHERE clan_id = ? AND team_number < ? ORDER BY team_number DESC", {}, $p->{clan_id}, $p->{old_number});
		}
		if (!$p->{swap_team_id}) {
			return (0, "Cannot move a team below the bottom or above the top.");
		}
		$p->{new_number} = $c->db_selectone("SELECT team_number FROM teams WHERE id = ?", {}, $p->{swap_team_id});
		$p->{temp_number} = $c->db_selectone("SELECT MAX(team_number)+1 FROM teams WHERE clan_id = ?", {}, $p->{clan_id});
		$c->db_do("UPDATE teams SET team_number = ? WHERE id = ?", {}, $p->{temp_number}, $p->{swap_team_id});
		$c->db_do("UPDATE teams SET team_number = ? WHERE id = ?", {}, $p->{new_number}, $p->{team_id});
		$c->db_do("UPDATE teams SET team_number = ? WHERE id = ?", {}, $p->{old_number}, $p->{swap_team_id});
		return (1, "Altered order of teams.");
	},
},
change_team_name => {
	brief => 'Change team name',
	checks => 'clan_moderator($clan_id)|period_predraw($period_id)',
	categories => [ qw/team clan admin/ ],
	acts_on => 'team',
	description => 'You can use this form to rename your team.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		oldname => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		newname => {
			type => 'valid_new|name_team($period_id,$clan_id,$team_id)',
			brief => 'New name',
			description => 'If you find some symbol that isn\'t allowed, plase complain in the Admin Stuff forum.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if ($c->db_do('UPDATE teams SET name=? WHERE id=?', {}, $p->{newname}, $p->{team_id})) {
			return (1, "Renamed team.");
		} else {
			return (0, "Database error.");
		}
	},
},
remove_team => {
	brief => 'Remove team',
	checks => 'clan_moderator($clan_id)|period_predraw($period_id)',
	categories => [ qw/team clan admin/ ],
	acts_on => 'team-',
	description => 'If you find you no longer want some team in the brawl, you can remove it here.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$p->{challenge_id} = $c->db_selectone("SELECT challenger_team_id FROM challenges WHERE challenger_team_id = ?", {}, $p->{team_id});
		$p->{match_id} = $c->db_selectone("SELECT team_id FROM team_match_teams WHERE team_id = ?", {}, $p->{team_id});
		if ($p->{challenge_id}) {
			return (0, "Sorry, your team has sent a challenge to another clan. The team can't be removed while the challenge exists.");
		} elsif ($p->{match_id}) {
			return (0, "Sorry, you cannot remove a team which has played or is playing a match.");
		}
		# Splat members and stuff first.
		$c->db_do('DELETE FROM team_seats WHERE team_id=?', {}, $p->{team_id}) or return (0, "Database error removing seats.");
		$c->db_do('DELETE FROM team_members WHERE team_id=?', {}, $p->{team_id}) or return (0, "Database error removing members.");
		if ($c->db_do('DELETE FROM teams WHERE id=?', {}, $p->{team_id})) {
			return (1, "Deleted team.");
		} else {
			return (0, "Database error.");
		}
	},
},
remove_member_from_team => {
	brief => 'Remove member from team',
	repeatable => 1,
	hidden => 1,
	checks => 'clan_moderator($clan_id)|period_predraw($period_id)',
	categories => [ qw/team member clan admin/ ],
	acts_on => 'team',
	description => 'Here you can remove members from teams. If you select "None", all members will be removed.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'null_valid|id_member($period_id,$clan_id,$team_id)',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if ($p->{member_id}) {
			# Check the member is not currently playing a team game.
			# It's consistent to remove them if they are, but pretty wierd.
			if ($c->db_selectone("SELECT tm.member_id FROM team_match_players tm INNER JOIN team_match_seats ts ON ts.team_match_id = tm.team_match_id AND ts.seat_no = tm.seat_no WHERE ts.winner IS NULL AND ts.member_id = ?", {}, $p->{member_id})) {
				return (0, "This player has an unfinished game in a match, and cannot be removed until they finish it.");
			} elsif (!$c->db_do('DELETE FROM team_seats WHERE member_id = ?', {}, $p->{member_id})) {
				return (0, "Database error removing seat.");
			} elsif (!$c->db_do('DELETE FROM team_members WHERE member_id = ?', {}, $p->{member_id})) {
				return (0, "Database error removing member.");
			} else {
				return (1, "Removed member from team.");
			}
		} else {
			if (!$c->db_do('DELETE FROM team_seats WHERE team_id = ?', {}, $p->{team_id})) {
				return (0, "Database error removing seats.");
			} elsif (!$c->db_do('DELETE FROM team_members WHERE team_id = ?', {}, $p->{team_id})) {
				return (0, "Database error removing members.");
			} else {
				return (1, "Removed members from team.");
			}
		}
	},
},
change_team_members => {
	brief => 'Select team members',
	checks => 'clan_moderator($clan_id)|period_predraw($period_id)',
	categories => [ qw/team clan admin/ ],
	acts_on => 'team',
	next_form => 'change_team_seats',
	description => 'Here you can select the complete roster for a team. The roster will be completely wiped and then the members below added (seated players in this team remain on their seats).',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'filter_qualified|id_member($period_id,$clan_id):list_default|id_member($period_id,$clan_id,$team_id)',
			multi => 1,
			brief => 'New team member list',
			description => 'You can hold Ctrl to select multiple members',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
			multi => 1,
			multi_col => 'member_id',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Clear team rosters as appropriate.
		$c->db_do('DELETE FROM team_members WHERE team_id = ?', {}, $p->{team_id}) or return (0, 'Database error removing old members from this team.');
		if (@{$p->{member_id}}) {
			# XXX not using prepare properly.
			$c->db_do('DELETE FROM team_members WHERE member_id IN('.join(',',@{$p->{member_id}}).')') or return (0, 'Database error removing members from old teams.');
			$c->db_do('DELETE FROM team_seats WHERE member_id IN('.join(',',@{$p->{member_id}}).') AND team_id != ?', {}, $p->{team_id}) or return (0, 'Database error clearing member seats.');
			$c->db_do('DELETE FROM team_seats WHERE member_id NOT IN('.join(',',@{$p->{member_id}}).') AND team_id = ?', {}, $p->{team_id}) or return (0, 'Database error clearing team seats.');
		} else {
			$c->db_do('DELETE FROM team_seats WHERE team_id = ?', {}, $p->{team_id}) or return (0, 'Database error clearing seats.');
		}

		# Check each member has the points
		$p->{max_members} = $c->get_option('BRAWLTEAMMAXMEMBERS', $p->{period_id});
		if (@{$p->{member_id}} > $p->{max_members}) {
			return (0, "Too many members selected.");
		}
		for(@{$p->{member_id}}) {
			if (!$c->db_do('INSERT INTO team_members SET team_id=?, member_id=?', {}, $p->{team_id}, $_)) {
				return (0, "Database error adding member to team.");
			}
		}
		return (1, "Set complete team roster.");
	},
},
add_member_to_team => {
	brief => 'Add member to team',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_prelims($period_id)',
	categories => [ qw/team member clan admin/ ],
	acts_on => 'team',
	description => 'Here you can add members to a team.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$c->db_do('DELETE FROM team_members WHERE member_id = ?', {}, $p->{member_id});
		$p->{req_points} = $c->get_option('BRAWLMEMBERPOINTS', $p->{period_id});
		$p->{current_points} = $c->db_selectone('SELECT played + played_pure FROM members WHERE id = ?', {}, $p->{member_id}) || 0;
		if ($p->{current_points} < $p->{req_points}) {
			return (0, "This member has not played enough games.");
		}
		$p->{max_members} = $c->get_option('BRAWLTEAMMAXMEMBERS', $p->{period_id});
		$p->{current_members} = $c->db_selectone('SELECT COUNT(*) FROM team_members WHERE team_id = ?', {}, $p->{team_id}) || 0;
		if ($p->{current_members} >= $p->{max_members}) {
			return (0, "This team has too many members.");
		}
		if (!$c->db_do('INSERT INTO team_members SET team_id=?, member_id=?', {}, $p->{team_id}, $p->{member_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Added member to team.");
		}
	},
},
change_team_seats => {
	brief => 'Change seating of team members',
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/team member clan admin/ ],
	acts_on => 'team',
	description => 'Choose the lineup for your team here. You can only select people who are already in the team (use Select Team Members to choose this).',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		old_seats => {
			type => 'positions_team($period_id,$clan_id,$team_id)',
			html => 1,
			informational => 1,
			brief => 'Current positions',
		},
		mem1_id => {
			type => 'id_member($period_id,$clan_id,$team_id,1)',
			brief => 'Seat 1',
		},
		mem1_name => {
			type => 'name_member($period_id,$clan_id,$mem1_id)',
			hidden => 1,
			informational => 1,
		},
		mem2_id => {
			type => 'null_valid|id_member($period_id,$clan_id,$team_id,2)',
			brief => 'Seat 2',
		},
		mem2_name => {
			type => 'null_valid|name_member($period_id,$clan_id,$mem2_id)',
			hidden => 1,
			informational => 1,
		},
		mem3_id => {
			type => 'null_valid|id_member($period_id,$clan_id,$team_id,3)',
			brief => 'Seat 3',
		},
		mem3_name => {
			type => 'null_valid|name_member($period_id,$clan_id,$mem3_id)',
			hidden => 1,
			informational => 1,
		},
		mem4_id => {
			type => 'null_valid|id_member($period_id,$clan_id,$team_id,4)',
			brief => 'Seat 4',
		},
		mem4_name => {
			type => 'null_valid|name_member($period_id,$clan_id,$mem4_id)',
			hidden => 1,
			informational => 1,
		},
		mem5_id => {
			type => 'null_valid|id_member($period_id,$clan_id,$team_id,5)',
			brief => 'Seat 5',
		},
		mem5_name => {
			type => 'null_valid|name_member($period_id,$clan_id,$mem5_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;
		# Check all members are different.
		my @member_ids;
		my @id_map;
		my %counter;
		for (1 .. 5) {
			push @member_ids, $p->{'mem'.$_.'_id'} if $p->{'mem'.$_.'_id'};
			$id_map[$_-1] = $p->{'mem'.$_.'_id'};
			$counter{$p->{'mem'.$_.'_id'}} = 1 if $p->{'mem'.$_.'_id'};
		}
		$p->{unique_seats} = keys %counter;
		$p->{set_seats} = @member_ids;
		if ($p->{unique_seats} != $p->{set_seats}) {
			return (0, "You used the same member several times!");
		}

		# Clear members from team roster(s).
		for (@member_ids) {
			$c->db_do('DELETE FROM team_seats WHERE member_id = ?', {}, $_) or return (0, "Database error clearing member $_ from rosters.");
		}
		$c->db_do('DELETE FROM team_seats WHERE team_id = ?', {}, $p->{team_id}) or return (0, "Database error clearing team roster.");

		for (0..4) {
			next unless $member_ids[$_];
			if (!$c->db_do('INSERT INTO team_seats SET team_id=?, member_id=?, seat_no=?', {}, $p->{team_id}, $member_ids[$_], $_)) {
				return (0, "Database error adding seat ".($_+1).".");
			}
		}
		return (1, "Changed team roster.");
	},
},
change_team_seat => {
	brief => 'Change seat of team member',
	repeatable => 1,
	hidden => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/team member clan admin/ ],
	acts_on => 'team',
	description => 'Choose the lineup for your teams here.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		old_seats => {
			type => 'positions_team($period_id,$clan_id,$team_id)',
			html => 1,
			informational => 1,
			brief => 'Current positions',
		},
		member_id => {
			type => 'id_member($period_id,$clan_id,$team_id)',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
		seat_no => {
			type => 'null_valid|enum(1,2,3,4,5)',
			brief => 'Position',
		}
	],
	action => sub {
		my ($c, $p) = @_;
		$c->db_do('DELETE FROM team_seats WHERE member_id = ?', {}, $p->{member_id});
		if (!$p->{seat_no}) {
			# That's it in this case.
			return (1, "Member will no longer be playing in the next round.");
		}
		if (!$c->db_do('INSERT INTO team_seats SET team_id=?, member_id=?, seat_no=?', {}, $p->{team_id}, $p->{member_id}, $p->{seat_no}-1)) {
			return (0, "Database error.");
		} else {
			return (1, "Changed member's team position.");
		}
	},
},
set_brawl_ready_status => {
	brief => 'Set team ready status',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_prebrawl($period_id)',
	categories => [ qw/team member clan admin/ ],
	acts_on => 'team',
	description => 'If you want your team to participate in the brawl, you must set the team "ready" below.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		team_id => {
			type => 'id_team($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_team($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		ready_status => {
			type => 'ready_team($period_id,$clan_id,$team_id)',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('UPDATE teams SET in_brawl=? WHERE id = ?', {}, $p->{ready_status}, $p->{team_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Set ready status.");
		}
	},
},
change_member_name => {
	brief => 'Change member name',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/member clan admin/ ],
	acts_on => 'member',
	description => 'You can change the displayed name of a member here.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		oldname => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
		newname => {
			type => 'valid_new|name_member($period_id,$clan_id,$member_id)',
			brief => 'New name',
			description => 'Complain in the Admin Stuff forum if something you want to use here doesn\'t work.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('UPDATE members SET name=? WHERE id=?', {}, $p->{newname}, $p->{member_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Renamed member.");
		}
	},
},
change_member_rank => {
	brief => 'Change member rank',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/member clan admin/ ],
	acts_on => 'member',
	description => 'This is not the player\'s playing strength, but a string that will be placed next to their name. You may for instace set a Captain rank on one member. If you put a % sign in the rank, for instance "%, Fishmonger", the % will be changed to the member name, resulting in "Fred, Fishmonger" or something in this case. Otherwise the rank will be placed before the member\'s name.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
		oldrank => {
			type => 'valid|null_valid|rank_member($period_id,$clan_id,$member_id)',
			brief => 'Old rank',
			informational => 1,
		},
		newrank => {
			type => 'null_valid|rank_member($period_id,$clan_id,$member_id)',
			brief => 'New rank',
			description => 'Complain in the Admin Stuff forum if something you want to use here doesn\'t work.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('UPDATE members SET rank=? WHERE id=?', {}, $p->{newrank}, $p->{member_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Changed rank.");
		}
	},
},
add_kgs_username => {
	brief => 'Add KGS username to member',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/alias member clan admin/ ], 
	acts_on => 'alias+',
	override_category => 'member',
	description => 'If a member has several names on KGS, you can add them all here. Please keep this below 3 names per member, as each name adds time to the nightly update and places load on KGS\'s servers.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
		member_alias => {
			type => 'valid_new|name_kgs($period_id)',
			brief => 'New username',
			description => 'You can of course only add a username to one member - if another member already has this username, it needs to be removed first.',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		$p->{time} = time();
		$p->{was_active} = $c->db_selectone('SELECT active FROM members WHERE id=?', {}, $p->{member_id});
		$p->{max_members} = $c->get_option('MEMBERMAX', $p->{period_id});
		$p->{current_members} = $c->db_selectone('SELECT COUNT(members.id) FROM members WHERE members.clan_id = ? AND members.active = 1', {}, $p->{clan_id});
		if (!$p->{was_active} && ($p->{current_members} >= $p->{max_members})) {
			return (0, "Sorry, but activating that members would put your clan over the maximum number of members.");
		}
		if (!$c->db_do('INSERT INTO kgs_usernames SET nick=?, member_id=?, period_id=?, activity=?', {}, $p->{member_alias}, $p->{member_id}, $p->{period_id}, $p->{time})) {
			return (0, "Database error.");
		} else {
			$p->{alias_id} = $c->lastid;
			if (!$p->{was_active}) {
				if (!$c->db_do('UPDATE members SET active=1 WHERE id=?', {}, $p->{member_id})) {
					return (0, "Database error setting active status.");
				}
			}
			return (1, "Added KGS username.");
		}
	},
},
remove_kgs_username => {
	brief => 'Remove KGS username from member',
	repeatable => 1,
	checks => 'clan_moderator($clan_id)|period_active($period_id)',
	categories => [ qw/alias member clan admin/ ],
	acts_on => 'alias-',
	override_category => 'member',
	description => 'If a member no longer uses a username to play clan games, remove it here. If you remove all usernames, a member becomes inactive and no longer counts towards total membership when adding new members.',
	params => [
		period_id => {
			type => 'id_period',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		clan_name => {
			type => 'name_clan($period_id,$clan_id)',
			hidden => 1,
			informational => 1,
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		member_name => {
			type => 'name_member($period_id,$clan_id,$member_id)',
			hidden => 1,
			informational => 1,
		},
		alias_id => {
			type => 'id_kgs($period_id,$clan_id,$member_id)',
			brief => 'Username to remove',
		},
		member_alias => {
			type => 'name_kgs($period_id,$clan_id,$member_id,$alias_id)',
			hidden => 1,
			informational => 1,
		}
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('DELETE FROM kgs_usernames WHERE id=? AND member_id=?', {}, $p->{alias_id}, $p->{member_id})) {
			return (0, "Database error.");
		} else {
			if (!$c->db_selectone('SELECT COUNT(*) FROM kgs_usernames WHERE member_id=?', {}, $p->{member_id})) {
				if (!$c->db_do("UPDATE members SET active=0 WHERE id=?", {}, $p->{member_id})) {
					return (0, "Database error.");
				}
			}
			return (1, "Removed KGS username.");
		}
	},
},
);
