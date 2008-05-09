package Clans::Form;
use strict;
use warnings;

our %forms = (
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
			type => 'valid_new|name_clan',
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
			description => 'This must be 2-4 alphanumeric charactersi.',
		},
	],
	action => sub {
		my ($c, $p) = @_;
		if (!$c->db_do('INSERT INTO clans SET name=?, tag=?, regex=?, clanperiod=?;', {}, $p->{name}, $p->{tag}, $p->{tag}, $p->{period_id})) {
			return (0, "Database error.");
		}
		$p->{leader_name_} = $p->{leader_name} || $p->{leader_kgs};
		$p->{clan_id} = $c->lastid;
		if (!$c->db_do('INSERT INTO members SET name=?, clan_id=?;', {}, $p->{leader_name}, $p->{clan_id})) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			return (0, "Database error.");
		}
		$p->{leader_id} = $c->lastid;
		if (!$c->db_do('INSERT INTO aliases SET nick=?, member_id=?, clanperiod=?, activity=?;', {}, $p->{leader_kgs}, $p->{leader_id}, $p->{period_id}, time())) {
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{leader_id});
			return (0, "Database error.");
		}
		if (!$c->db_do('UPDATE clans SET leader_id=? WHERE id=?;', {}, $p->{leader_id}, $p->{clan_id})) {
			$c->log('ADDCLAN_FAIL', $p);
			$c->db_do('DELETE FROM clans WHERE id=?', {}, $p->{clan_id});
			$c->db_do('DELETE FROM members WHERE id=?', {}, $p->{leader_id});
			$c->db_do('DELETE FROM aliases WHERE member_id=?', {}, $p->{leader_id});
			return (0, "Database error.");
		}

		# Now add the forum
		if (!$c->db_do("SET \@forum_user = ?, \@clan_id = ?", {}, $p->{forum_user_id}, $p->{clan_id})) {
			return (0, "Database error.");
		}
		my @SQL = (
			# Set options for standard groups
			"SELECT \@guest_group := group_id FROM phpbb3_groups WHERE group_name = 'GUESTS'",
			"SELECT \@registered_group := group_id FROM phpbb3_groups WHERE group_name = 'REGISTERED'",
			"SELECT \@bot_group := group_id FROM phpbb3_groups WHERE group_name = 'BOTS'",
			"SELECT \@admin_group := group_id FROM phpbb3_groups WHERE group_name = 'ADMINISTRATORS'",
			"INSERT INTO phpbb3_acl_groups SELECT \@guest_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_NOACCESS')",
			"INSERT INTO phpbb3_acl_groups SELECT \@registered_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_NOACCESS')",
			"INSERT INTO phpbb3_acl_groups SELECT \@bot_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_NOACCESS')",
			"INSERT INTO phpbb3_acl_groups SELECT \@admin_group, \@newforum, 0, role_id, 1 FROM phpbb3_acl_roles WHERE role_name IN ('ROLE_FORUM_FULL')",

			"SET \@proposals_forum = 3",
			"SELECT \@leaders_group := group_id FROM phpbb3_groups WHERE group_name = 'Clan Leaders'",
			"SELECT \@guest_group := group_id FROM phpbb3_groups WHERE group_name = 'GUESTS'",
			"SELECT \@registered_group := group_id FROM phpbb3_groups WHERE group_name = 'REGISTERED'",
			"SELECT \@bot_group := group_id FROM phpbb3_groups WHERE group_name = 'BOTS'",
			"SELECT \@admin_group := group_id FROM phpbb3_groups WHERE group_name = 'ADMINISTRATORS'",

			# Create groups
			"INSERT INTO phpbb_groups SET group_type = 1, group_name = \@clan_name, group_desc = '', group_type = 1",
			"SET \@clan_group = LAST_INSERT_ID()",
			"INSERT INTO phpbb_groups SET group_type = 1, group_name = CONCAT(\@clan_name, ' Moderators'), group_desc = '', group_type = 1",
			"SET \@clan_leader_group = LAST_INSERT_ID()",

			# Add leader to groups
			"INSERT INTO phpbb_user_group SET group_id = \@clan_group, user_id = \@forum_user, user_pending = 0, group_leader = 1",
			"INSERT INTO phpbb_user_group SET group_id = \@clan_leader_group, user_id = \@forum_user, user_pending = 0, group_leader = 1",
			"INSERT INTO phpbb_user_group SET group_id = \@leaders_group, user_id = \@forum_user, user_pending = 0, group_leader = 0",

			# Add clan forum
			"SELECT \@clan_name := name FROM clans WHERE id = \@clan_id",
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
				return (0, "Database error.");
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
new_page => {
	# Edit page. Invoked only from custom forms.
	brief => 'New page',
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
edit_page => {
	# Edit page. Invoked only from custom forms.
	brief => 'Edit page',
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
set_clan_name => {
	# Alter clan's name.
	brief => 'Rename clan',
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
			type => 'valid|name_clan($period_id, $clan_id)',
			hidden => [ qw/clan admin/ ],
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
set_clan_tag => {
	# Set clan's tag.
	brief => 'Change clan\'s tag',
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
			readonly => [ qw/clan admin/ ],
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
set_clan_url => {
	# Set clan's URL
	brief => 'Set clan\'s website address',
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
			readonly => [ qw/clan admin/ ],
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
set_clan_info => {
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
			readonly => [ qw/clan admin/ ],
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
set_clan_leader => {
	brief => 'Set displayed clan leader',
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

		$p->{max_members} = $c->getoption('MEMBERMAX', $p->{period_id});
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
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		name => {
			type => 'valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/member clan admin/ ],
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
		# TODO check qualification status
		if ($c->db_do('INSERT INTO brawl_teams SET name=?, clan_id=?', {}, $p->{team_name}, $p->{clan_id})) {
			return (1, "Added new brawl team.");
		} else {
			return (0, "Database error.");
		}
	},
},
set_clan_brawl_team_name => {
	brief => 'Set brawl team name',
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
		team_id => {
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		oldname => {
			type => 'valid|name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => [ qw/brawl clan admin/ ],
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
		team_id => {
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		name => {
			type => 'valid|name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => [ qw/brawl clan admin/ ],
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
	category => [ qw/member brawl clan admin/ ],
	description => 'Here you can remove members from brawl teams. If you select "None", all members will be removed.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		team_id => {
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'valid|name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => [ qw/brawl clan admin/ ],
		},
		member_id => {
			type => 'null_valid|id_member($period_id,$clan_id,$team_id)',
		},
		member_name => {
			type => 'valid|null_valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/brawl clan admin/ ],
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
	category => [ qw/member brawl clan admin/ ],
	description => 'Here you can add members to brawl teams.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		team_id => {
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'valid|name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => [ qw/member brawl clan admin/ ],
		},
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		member_name => {
			type => 'valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/member brawl clan admin/ ],
		},
	],
	action => sub {
		my ($c, $p) = @_;
		$c->db_do('DELETE FROM brawl_team_members WHERE member_id = ?', {}, $p->{member_id});
		$p->{req_points} = $c->getoption('BRAWLMEMBERPOINTS', $p->{period_id});
		$p->{current_points} = $c->db_selectone('SELECT played + played_pure FROM members WHERE id = ?', {}, $p->{member_id}) || 0;
		if ($p->{current_points} < $p->{req_points}) {
			return (0, "This member has not played enough games.");
		}
		$p->{max_members} = $c->getoption('BRAWLMAXMEMBERS', $p->{period_id});
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
set_brawl_pos => {
	brief => 'Set position of team members',
	level => 'clan_moderator($clan_id)',
	category => [ qw/member brawl clan admin/ ],
	description => 'Before each round draw happens, you are required to have picked your team lineup.',
	params => [
		period_id => {
			type => 'id_clanperiod',
		},
		clan_id => {
			type => 'id_clan($period_id)',
		},
		team_id => {
			type => 'id_brawlteam($period_id,$clan_id)',
		},
		team_name => {
			type => 'valid|name_brawlteam($period_id,$clan_id,$team_id)',
			hidden => [ qw/member brawl clan admin/ ],
		},
		member_id => {
			type => 'id_member($period_id,$clan_id,$team_id)',
		},
		member_name => {
			type => 'valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/member brawl clan admin/ ],
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
set_member_name => {
	brief => 'Rename member',
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
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		oldname => {
			type => 'valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/member clan admin/ ],
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
set_member_rank => {
	brief => 'Set member\'s rank',
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
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		name => {
			type => 'valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/member clan admin/ ],
		},
		oldrank => {
			type => 'valid|null_valid|rank_member($period_id,$clan_id,$member_id)',
			brief => 'Old rank',
			readonly => [ qw/member clan admin/ ],
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
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		name => {
			type => 'valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/member clan admin/ ],
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
		member_id => {
			type => 'id_member($period_id,$clan_id)',
		},
		name => {
			type => 'valid|name_member($period_id,$clan_id,$member_id)',
			hidden => [ qw/member clan admin/ ],
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
