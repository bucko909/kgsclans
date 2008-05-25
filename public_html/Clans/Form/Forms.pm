package Clans::Form;
use strict;
use warnings;

our %forms = (
brawl_draw => {
	brief => 'Produce draw for next round of the brawl',
	level => 'admin',
	category => [ qw/admin/ ],
	description => 'Produces the draw for the next round of the brawl.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Four cases:
		# - Asked to produce a first round, and there's few enough teams to fit.
		# - Asked to produce a first round and a preliminary round is needed.
		# - Asked to produce the first round after preliminaries.
		# - Asked to produce any other round.

		# First, let's see if this will be the first round of any kind.
		my $draw_made = $c->db_selectone("SELECT brawldraw.team_id FROM brawldraw INNER JOIN brawl_teams ON brawldraw.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ?", {}, $p->{period_id});

		my $insert_team = sub {
			my ($round, $position, $team, $next) = @_;
			$c->db_do("INSERT INTO brawldraw SET clanperiod=?, round=?, team_id=?, position=?, nextround_pos=?", {}, $p->{period_id}, $round, $team, $position, $next);
		};

		# Get a list of team members.
		my $members = $c->db_select("SELECT brawl.team_id, position, member_id FROM brawl INNER JOIN brawl_teams ON brawl.team_id = brawl_teams.team_id INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ?", {}, $p->{period_id});

		# Sort members into teams.
		my %team_members;
		for(@$members) {
			$team_members{$_->[0]} ||= [];
			next unless $_->[1] >= 1 && $_->[1] <= 5;
			$team_members{$_->[0]}[$_->[1]-1] = $_->[2];
			$team_members{$_->[0]}[5]++;
		}

		my $insert_members = sub {
			my ($round, $position, $team) = @_;
			for(1 .. 5) {
				$c->db_do("INSERT INTO brawldraw_results SET clanperiod=?, round=?, position=?, seat=?, member_id=?, is_black=?", {}, $p->{period_id}, $round, $position, $_, $team_members{$team->[0]}[$_-1], ($position+$round+$_+1)%2);
			}
		};

		if ($draw_made) {
			# We're making a draw for round having (hopefully) got all results for the previous one.
			# First we must figure out the "current" round.
			$p->{last_round} = $c->db_selectone("SELECT MAX(round) FROM brawldraw_results");
			$p->{this_round} = $p->{last_round} + 1;
			if ($p->{last_round} == 0) {
				# We're generating round 1 based on the preliminaries.
				my $fighting_over = $c->db_select("SELECT nextround_pos, COUNT(DISTINCT team_id), SUM(IF(result=1,1,0)) FROM brawldraw WHERE clanperiod = ? AND round = 0 GROUP BY nextround_pos", {}, $p->{period_id});
				$p->{fighting_over} = join ',', map { "$_->[0]=($_->[2]g/$_->[1]t)" } @$fighting_over;
				$p->{teams_unsorted} = '';
				$p->{teams_sorted} = '';
				for my $position (@$fighting_over) {
					# First ensure all positions have complete results.
					# Simple check: The number of wins in the group should be equal to the number of games, which is in turn equal to 1 + 2 + ... + n-1 where n is the number of teams.
					# This is of course equal to n(n-1)/2.
					if ($position->[2] != $position->[1] * ($position->[1] - 1) / 2) {
						return (0, "It appears that the preliminary round is not yet complete ($position->[2] results for $position->[1] teams).");
					}
				}
				for my $position (@$fighting_over) {
					# Get all teams fighting over position
					my $teams = $c->db_select("SELECT team_id, SUM(position), SUM(IF(result=1,1,0)) FROM brawldraw WHERE clanperiod = ? AND round = 0 AND nextround_pos = ? GROUP BY team_id", {}, $p->{period_id}, $position->[0]);
					$p->{teams_unsorted} .= "$position->[0]:".(join ',', map { "$_->[0]=($_->[2].$_->[1])" } @$teams).";";
					# Sort by wins (desc) then position (asc).
					$teams = [ sort { $b->[2] <=> $a->[2] || $a->[1] <=> $b->[1] } @$teams ];
					$p->{teams_sorted} .= "$position->[0]:".(join ',', map { "$_->[0]=($_->[2].$_->[1])" } @$teams).";";
					# Insert the winner into the brawl.
					$insert_team->($p->{this_round}, $position->[0], $teams->[0][0], int($position->[0]/2));
				}
			} else {
				# We're generating round n+1 based on round n > 0
				# First check round n is complete.
				my $check = $c->db_selectone("SELECT COUNT(DISTINCT nextround_pos) - SUM(IF(result=1,1,0)) FROM brawldraw WHERE clanperiod = ? AND round = ?", {}, $p->{period_id}, $p->{last_round});
				if ($check != 0) {
					return (0, "It appears that the current round is not yet complete.");
				}

				my $winners = $c->db_select("SELECT team_id, nextround_pos FROM brawldraw WHERE clanperiod = ? AND round = ? AND result = 1", {}, $p->{period_id}, $p->{last_round});
				$p->{winning_teams} = join ',', map { "$_->[1]:$_->[0]" } @$winners;
				if (@$winners == 1) {
					# In this case we found the brawl winner. The next round position is not defined!
					$insert_team->($p->{this_round}, $winners->[0][1], $winners->[0][0], undef);
				} else {
					# It's a normal round.
					for my $team (@$winners) {
						$insert_team->($p->{this_round}, $team->[1], $team->[0], int($team->[1]/2));
					}
				}
			}
		} else {
			# This is the first round. First, we must decide if we need to produce a preliminary draw.
			$p->{req_points} = $c->get_option('BRAWLTEAMPOINTS');
			my @points = split /,/, $p->{req_points};

			$p->{req_members} = $c->get_option('BRAWLTEAMMINMEMBERS');

			$p->{max_rounds} = $c->get_option('BRAWLROUNDS');

			# Get a list of teams.
			my $teams = $c->db_select("SELECT brawl_teams.team_id, team_number, clans.points, COUNT(member_id) AS number, clans.id FROM brawl_team_members INNER JOIN brawl_teams ON brawl_team_members.team_id = brawl_teams.team_id INNER JOIN clans ON clans.id = brawl_teams.clan_id WHERE clans.clanperiod = ? GROUP BY brawl_teams.team_id HAVING number >= ?", {}, $p->{period_id}, $p->{req_members});

			# Remove all teams which do not have 5 members.
			$p->{all_teams} = join ',', map { $_->[0] } @$teams;
			$teams = [ grep { $team_members{$_->[0]} && $team_members{$_->[0]}[5] == 5 } @$teams ];
			$p->{culled_teams} = join ',', map { $_->[0] } @$teams;

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
			while(@tree > 1) {
				my @new_tree;
				for(0 .. @tree / 2 - 1) {
					push @new_tree, [$tree[$_], $tree[$#tree-$_]];
				}
				@tree = @new_tree;
			}
			# Do a depth first search to pull the tree back apart.
			my $dfs;
			$dfs = sub { ref $_[0] ? ($dfs->($_[0][0]), $dfs->($_[0][1])) : $_[0] };
			my @position_map = $dfs->(\@tree);
				
			if (@$teams > $p->{max_teams}) {
				# We must generate a preliminary round.
				$p->{this_round} = 0;

				# First, who gets auto entry?
				$p->{auto_entry} = $c->get_option('BRAWLAUTOENTRY');
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
				$p->{teams_on_min} = $p->{remain_slots} - (@$teams % $p->{remain_slots});

				if ($p->{min_opponents} == 0) {
					# In this case, at least one team gets in free. Bung 'em all on auto_teams.
					push @auto_teams, splice(@$teams, 0, $p->{teams_on_min});
					$p->{remain_slots} -= $p->{teams_on_min};
					$p->{teams_on_min} = 0;
					$p->{min_opponents} = 1;
				}

				$p->{auto_teams} = join ',', map { $_->[0] } @auto_teams;
				$p->{preliminary_teams} = join ',', map { $_->[0] } @$teams;

				# Now we have a list of teams which need to be blocked together. We do one pass placing the highest seeded teams each in their respective slot, then reverse direction
				# and place the rest, for example:
				# 1 2  3 4
				# 8 7  6 5
				#     10 9
				my @fights;
				for(0..$p->{remain_slots}-1) {
					$fights[$_] = [$teams->[$_]];
					for(my $i=2; $i<5; $i++) {
						push @{$fights[$_]}, $teams->[$p->{remain_slots}*$i-$_] if $teams->[$p->{remain_slots}*$i-$_];
					}
				}

				# We now have an array, @fights, which contains the teams to fight over slot n, and an array, @auto_teams, which contains teams who get through automatically.

				# We insert the auto teams first. They live in round 1.
				my $pos = 0;
				for my $team (@auto_teams) {
					my $this_pos = $position_map[$pos++];
					$insert_team->(1, $this_pos, $team->[0], int($this_pos/2));
				}

				# The preliminary round is numbered 0, so let's do some insertions. Note that $pos currently tells us the nextround_pos for each group.
				my $prepos = 0;
				for my $group (@fights) {
					my $this_pos = $position_map[$pos++];
					for (my $t1=0; $t1 < @$group; $t1++) {
						for (my $t2=$t1+1; $t2 < @$group; $t2++) {
							$insert_team->($p->{this_round}, $prepos++, $group->[$t1][0], $this_pos);
							$insert_team->($p->{this_round}, $prepos++, $group->[$t2][0], $this_pos);
						}
					}
				}
			} else {
				$p->{this_round} = 1;
				# We are clear and can just generate a normal round.
				# We insert the auto teams first. They live in round 1.
				my $pos = 0;
				for my $team (@$teams) {
					my $this_pos = $position_map[$pos++];
					$insert_team->($p->{this_round}, $this_pos, $team->[0], int($this_pos/2));
				}
			}
		}
		my $teams_to_insert = $c->db_select("SELECT team_id, position FROM brawldraw WHERE clanperiod = ? AND round = ?", {}, $p->{period_id}, $p->{this_round});
		for my $team (@$teams_to_insert) {
			$insert_members->($p->{this_round}, $team->[1], $team);
		}
		return (1, "Draw successfully produced!");
	},
},
add_clan => {
	# Add clan. Autogen form on admin page.
	brief => 'Add clan',
	level => 'admin',
	category => [ qw/admin/ ],
	description => 'Allows you to add a clan to the system. After adding, please ensure the new leader adds 4 further members before a week is up.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
		if (!$c->db_do('INSERT INTO clans SET name=?, tag=?, regex=?, clanperiod=?;', {}, $p->{name}, $p->{tag}, $p->{tag}, $p->{period_id})) {
			return (0, "Database error during clan addition.");
		}
		$p->{actual_leader_name} = $p->{leader_name} || $p->{leader_kgs};
		$p->{clan_id} = $c->lastid;
		if (!$c->db_do('INSERT INTO members SET name=?, clan_id=?;', {}, $p->{actual_leader_name}, $p->{clan_id})) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			return (0, "Database error during leader addition.");
		}
		$p->{leader_id} = $c->lastid;
		if (!$c->db_do('INSERT INTO aliases SET nick=?, member_id=?, clanperiod=?, activity=?;', {}, $p->{leader_kgs}, $p->{leader_id}, $p->{period_id}, time())) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{leader_id});
			return (0, "Database error during alias addition.");
		}
		if (!$c->db_do('UPDATE clans SET leader_id=? WHERE id=?;', {}, $p->{leader_id}, $p->{clan_id})) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{leader_id});
			$c->db_do('DELETE FROM aliases WHERE member_id=?', {}, $p->{leader_id});
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
		return (1, "Clan and forum added.");
	}
},
add_page => {
	# Edit page. Invoked only from custom forms.
	brief => 'Add page',
	level => 'admin',
	category => [ qw/page admin/ ], # TODO not finished types for params
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		name => {
			type => 'valid_new|name_page($period_id)',
		},
		based_on => {
			type => 'name_page($period_id)',
			brief => 'Template',
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
		if (!$c->db_do("INSERT INTO content SET name=?, content=?, revision=?, clanperiod=?, created=?, creator=?, current=?", {}, $p->{name}, $p->{content}, 1, $p->{period_id}, $p->{time}, $p->{forum_user_id}, 1)) {
		my $name = $c->param('page');
			return (0, "Database error.");
		}
		return (1, "Page created.");
	}
},
change_page => {
	# Edit page. Invoked only from custom forms.
	brief => 'Change page',
	level => 'admin',
	category => [ qw/page admin/ ], # TODO not finished types for params
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		name => {
			type => 'name_page($period_id)',
		},
		revision => {
			type => 'revision_page($period_id,$name)',
		},
		content => {
			type => 'content_page($period_id,$name,$revision)',
		},
	],
	action => sub {
		my ($c, $p) = @_;

		# Is it new? What revision?
		$p->{lastrevision} = $c->db_selectone("SELECT MAX(revision) FROM content WHERE name = ? AND clanperiod = ?", {}, $p->{name}, $p->{period_id});
		if ($p->{lastrevision}) {
			$p->{newrevision} = $p->{lastrevision} + 1;
		} else {
			$p->{newrevision} = 1;
		}
		$p->{time} = time();
		$p->{forum_user_id} = $c->{phpbbsess}{userid};
		if (!$c->db_do("INSERT INTO content SET name=?, content=?, revision=?, clanperiod=?, created=?, creator=?, current=?", {}, $p->{name}, $p->{content}, $p->{newrevision}, $p->{period_id}, $p->{time}, $p->{forum_user_id}, 1)) {
		my $name = $c->param('page');
			return (0, "Database error.");
		}
		$c->db_do("UPDATE content SET current=0 WHERE name=? AND clanperiod=? AND revision!=?", {}, $p->{name}, $p->{period_id}, $p->{newrevision});
		return (1, "Text updated.");
	}
},
change_clan_name => {
	# Alter clan's name.
	brief => 'Change clan name',
	level => 'clan_leader($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'Alter the clan\'s name. Please keep the name sensible, with no profanity etc.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
	level => 'clan_leader($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'Alter the clan\'s tag. Please keep the tag free of profanity etc.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
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
	level => 'clan_moderator($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'With this form you may give a website address people can visit for more information on your clan.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
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
	level => 'clan_moderator($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'Here you may set a description for your clan. Some of this will be shown on the summary page, and all of it will be shown on your clan\'s info page.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		oldinfo => {
			type => 'valid|null_valid|info_clan($period_id,$clan_id)',
			brief => 'Old description',
			informational => 1,
		},
		newinfo => {
			type => 'null_valid|info_clan($period_id,$clan_id)',
			brief => 'New description',
			description => 'If your chosen description is not allowed, and you\'re trying to put something sensible in, please mention it on the Admin Stuff forum.',
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
	level => 'clan_leader($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'This changes the member who will be listed as the leader when people look at the summary page etc. It does not grant the member any permissions (you should do this by fiddling with forum groups).',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
			brief => 'New leader',
			description => 'The new member you want displayed as the leader for your clan',
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
add_clan_member => {
	brief => 'Add member',
	level => 'clan_moderator($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'You can add a new member to your clan with this form. If you just want to add another KGS username to an existing member, you\'re on the wrong form.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
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
		my $currentmembers_list = $c->db_select('SELECT members.id FROM members INNER JOIN aliases ON members.id = aliases.member_id WHERE members.clan_id = ? GROUP BY members.id', {}, $p->{clan_id}); ## Hax
		$p->{current_members} = @$currentmembers_list;
		if ($p->{current_members} >= $p->{max_members}) {
			return (0, "Sorry, your clan has too many members.");
		}

		if (!$c->db_do('INSERT INTO members SET name=?, clan_id=?', {}, $p->{member_name}, $p->{clan_id})) {
			return (0, "Database error.");
		}

		$p->{member_id} = $c->lastid;
		$p->{time} = time();
		if (!$c->db_do('INSERT INTO aliases SET nick=?, member_id=?, clanperiod=?, activity=?', {}, $p->{member_kgs}, $p->{member_id}, $p->{period_id}, $p->{time})) {
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{member_id});
			return (0, "Database error.");
		}
		return (1, "Member added.");
	},
},
add_private_clan_forum => {
	brief => 'Add private clan forum',
	level => 'clan_leader($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'With this form, you can add a private forum for your clan\'s members. Only people in your clan\'s members group on the forum (and of course admins) will be able to see it.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
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
remove_clan_member => {
	brief => 'Remove clan member',
	level => 'clan_moderator($clan_id)',
	category => [ qw/member clan admin/ ],
	description => 'You can use this to remove a member from your clan. If they have any clan games, they will have all of their KGS names removed, so that they are marked inactive and won\'t count towards your total when adding new members. This means any games they played still count for your clan, and they will still be pure games for both players if played against another clan.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
			if (!$c->db_do('DELETE FROM aliases WHERE member_id=?', {}, $p->{member_id}) || !$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{member_id})) {
				return (0, "Database error.");
			} else {
				return (1, "Removed member from clan!.");
			}
		} else {
			if (!$c->db_do('DELETE FROM aliases WHERE member_id=?', {}, $p->{member_id})) {
				return (0, "Database error.");
			} else {
				return (1, "Member had played games, hence only removed KGS user names.");
			}
		}
	},
},
add_clan_brawl_team => {
	brief => 'Add brawl team',
	level => 'clan_moderator($clan_id)',
	category => [ qw/clan admin/ ],
	description => 'This form allows you to add a new brawl team for your clan. Note that it currently does not check you have met the requirements for entering teams into the brawl, so even if you can add a team it doesn\'t mean it will be entered into the brawl.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		team_name => {
			type => 'valid_new|name_brawlteam($period_id,$clan_id)',
			description => 'All brawl teams are now required to have a name. If you can\'t think of one, suggested names are variations along the themes of "Warriors", "Crushers" or "Hamsters".',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$p->{existing_teams} = $c->db_selectone("SELECT COUNT(*) FROM brawl_teams WHERE clan_id = ?", {}, $p->{clan_id});
		my @requirements = split /,/, $c->get_option('BRAWLTEAMPOINTS');
		$p->{points_required} = $requirements[$p->{existing_teams}];
		$p->{points_accrued} = $c->db_selectone("SELECT points FROM clans WHERE id = ?", {}, $p->{clan_id});
		if ($p->{points_accrued} < $p->{points_required}) {
			return (0, "Not enough points to add this team ($p->{points_accrued} < $p->{points_required}).");
		}
		if ($c->db_do('INSERT INTO brawl_teams SET name=?, clan_id=?, team_number=?', {}, $p->{team_name}, $p->{clan_id}, $p->{existing_teams}+1)) {
			return (1, "Added new brawl team.");
		} else {
			return (0, "Database error.");
		}
	},
},
change_clan_brawl_team_order => {
	brief => 'Change order of brawl team',
	level => 'clan_moderator($clan_id)',
	category => [ qw/brawl clan admin/ ],
	description => 'You can use this form to reorder your teams (for example, to change which gets automatically entered into the brawl). Moving a team up gives it higher priority.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_brawlteam($period_id,$clan_id,$team_id)',
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
		$p->{old_number} = $c->db_selectone("SELECT team_number FROM brawl_teams WHERE team_id = ?", {}, $p->{team_id});
		$p->{new_number} = $p->{old_number} + ($p->{updown} eq 'Down' ? 1 : -1);
		$p->{total_teams} = $c->db_selectone("SELECT COUNT(*) FROM brawl_teams WHERE clan_id = ?", {}, $p->{clan_id});
		if ($p->{new_number} > $p->{total_teams}) {
			return (0, "Cannot move a team below the bottom.");
		}
		if ($p->{new_number} < 1) {
			return (0, "Cannot move a team above the top.");
		}
		$c->db_do("UPDATE brawl_teams SET team_number = ? WHERE team_number = ? AND clan_id = ?", {}, 100, $p->{old_number}, $p->{clan_id});
		$c->db_do("UPDATE brawl_teams SET team_number = ? WHERE team_number = ? AND clan_id = ?", {}, $p->{old_number}, $p->{new_number}, $p->{clan_id});
		$c->db_do("UPDATE brawl_teams SET team_number = ? WHERE team_number = ? AND clan_id = ?", {}, $p->{new_number}, 100, $p->{clan_id});
		return (1, "Altered order of brawl teams.");
	},
},
change_clan_brawl_team_name => {
	brief => 'Change brawl team name',
	level => 'clan_moderator($clan_id)',
	category => [ qw/brawl clan admin/ ],
	description => 'You can use this form to rename your brawl team.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		oldname => {
			type => 'name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		newname => {
			type => 'valid_new|name_brawlteam($period_id,$clan_id,$team_id)',
			brief => 'New name',
			description => 'If you find some symbol that isn\'t allowed, plase complain in the Admin Stuff forum.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if ($c->db_do('UPDATE brawl_teams SET name=? WHERE team_id=?', {}, $p->{newname}, $p->{team_id})) {
			return (1, "Renamed brawl team.");
		} else {
			return (0, "Database error.");
		}
	},
},
remove_clan_brawl_team => {
	brief => 'Remove brawl team',
	level => 'clan_moderator($clan_id)',
	category => [ qw/brawl clan admin/ ], 
	description => 'If you find you no longer want some team in the brawl, you can remove it here.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
	],
	action => sub {
		my ($c, $p) = @_;
		# Splat members and stuff first.
		$c->db_do('DELETE FROM brawl_team_members WHERE team_id=?', {}, $p->{team_id});
		$c->db_do('DELETE FROM brawl WHERE team_id=?', {}, $p->{team_id});
		if ($c->db_do('DELETE FROM brawl_teams WHERE team_id=?', {}, $p->{team_id})) {
			return (1, "Deleted brawl team.");
		} else {
			return (0, "Database error.");
		}
	},
},
remove_member_from_brawl => {
	brief => 'Remove member from brawl team',
	level => 'clan_moderator($clan_id)',
	category => [ qw/brawl member clan admin/ ],
	description => 'Here you can remove members from brawl teams. If you select "None", all members will be removed.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_brawlteam($period_id,$clan_id,$team_id)',
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
		# All sensible checking is already done...
		if ($p->{member_id}) {
			if (!$c->db_do('DELETE FROM brawl_team_members WHERE member_id = ?', {}, $p->{member_id})) {
				return (0, "Database error.");
			} else {
				return (1, "Removed member from brawl team.");
			}
		} else {
			if (!$c->db_do('DELETE FROM brawl_team_members WHERE team_id = ?', {}, $p->{team_id})) {
				return (0, "Database error.");
			} else {
				return (1, "Removed members from brawl team.");
			}
		}
	},
},
add_member_to_brawl => {
	brief => 'Add member to brawl team',
	level => 'clan_moderator($clan_id)',
	category => [ qw/brawl member clan admin/ ],
	description => 'Here you can add members to brawl teams.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_brawlteam($period_id,$clan_id,$team_id)',
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
		$c->db_do('DELETE FROM brawl_team_members WHERE member_id = ?', {}, $p->{member_id});
		$p->{req_points} = $c->get_option('BRAWLMEMBERPOINTS', $p->{period_id});
		$p->{current_points} = $c->db_selectone('SELECT played + played_pure FROM members WHERE id = ?', {}, $p->{member_id}) || 0;
		if ($p->{current_points} < $p->{req_points}) {
			return (0, "This member has not played enough games.");
		}
		$p->{max_members} = $c->get_option('BRAWLTEAMMAXMEMBERS', $p->{period_id});
		$p->{current_members} = $c->db_selectone('SELECT COUNT(*) FROM brawl_team_members WHERE team_id = ?', {}, $p->{team_id}) || 0;
		if ($p->{current_members} >= $p->{max_members}) {
			return (0, "This team has too many members.");
		}
		if (!$c->db_do('INSERT INTO brawl_team_members SET team_id=?, member_id=?', {}, $p->{team_id}, $p->{member_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Added member to team.");
		}
	},
},
change_brawl_pos => {
	brief => 'Change position of team members',
	level => 'clan_moderator($clan_id)',
	category => [ qw/brawl member clan admin/ ],
	description => 'Before each round draw happens, you are required to have picked your team lineup.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => 1,
			informational => 1,
		},
		old_positions => {
			type => 'positions_brawlteam($period_id,$clan_id,$team_id)',
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
		pos_id => {
			type => 'null_valid|enum(1,2,3,4,5)',
			brief => 'Position',
		}
	],
	action => sub {
		my ($c, $p) = @_;
		$c->db_do('DELETE FROM brawl WHERE member_id = ?', {}, $p->{member_id});
		if (!$p->{pos_id}) {
			# That's it in this case.
			return (1, "Member will no longer be playing in the next round.");
		}
		if (!$c->db_do('INSERT INTO brawl SET team_id=?, member_id=?, position=?', {}, $p->{team_id}, $p->{member_id}, $p->{pos_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Changed clan brawl position.");
		}
	},
},
change_member_name => {
	brief => 'Change member name',
	level => 'clan_moderator($clan_id)',
	category => [ qw/member clan admin/ ],
	description => 'You can change the displayed name of a member here.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
	level => 'clan_moderator($clan_id)',
	category => [ qw/member clan admin/ ],
	description => 'This is not the player\'s playing strength, but a string that will be placed next to their name. You may for instace set a Captain rank on one member. If you put a % sign in the rank, for instance "%, Fishmonger", the % will be changed to the member name, resulting in "Fred, Fishmonger" or something in this case. Otherwise the rank will be placed before the member\'s name.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
add_member_alias => {
	brief => 'Add KGS username to member',
	level => 'clan_moderator($clan_id)',
	category => [ qw/member clan admin/ ], 
	description => 'If a member has several names on KGS, you can add them all here. Please keep this below 3 names per member, as each name adds time to the nightly update and places load on KGS\'s servers.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
		if (!$c->db_do('INSERT INTO aliases SET nick=?, member_id=?, clanperiod=?, activity=?', {}, $p->{member_alias}, $p->{member_id}, $p->{period_id}, $p->{time})) {
			return (0, "Database error.");
		} else {
			return (1, "Added KGS username.");
		}
	},
},
remove_member_alias => {
	brief => 'Remove KGS username from member',
	level => 'clan_moderator($clan_id)',
	category => [ qw/alias member clan admin/ ],
	description => 'If a member no longer uses a username to play clan games, remove it here. If you remove all usernames, a member becomes inactive and no longer counts towards total membership when adding new members.',
	params => [
		period_id => {
			type => 'id_clanperiod',
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
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('DELETE FROM aliases WHERE id=? AND member_id=?', {}, $p->{alias_id}, $p->{member_id})) {
			return (0, "Database error.");
		} else {
			return (1, "Removed KGS username.");
		}
	},
},
);
