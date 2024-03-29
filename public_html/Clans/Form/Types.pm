package Clans::Form;
use strict;
use warnings;

our %input_tests = (
name_page => {
	defaults => {
		brief => 'Page',
		readonly => [ qw/page/ ],
	},
	check => sub {
		/^\w+$/
	},
	exists => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_selectone("SELECT name FROM content WHERE period_id = ? AND name = ? AND current = 1", {}, $period, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_select("SELECT name, name FROM content WHERE period_id = ? AND current = 1 ORDER BY name", {}, $period);
		}
		return;
	},
},
revision_page => {
	defaults => {
		brief => 'Revision',
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c, $period, $name) = @_;
		if ($period && $name) {
			return $c->db_selectone("SELECT revision FROM content WHERE period_id = ? AND name = ? AND revision = ?", {}, $period, $name, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub {
		my ($c, $period, $name) = @_;
		if ($period && $name) {
			return $c->db_select("SELECT revision, revision FROM content WHERE period_id = ? AND name = ? ORDER BY revision", {}, $period, $name);
		}
		return;
	},
},
content_page => {
	defaults => {
		brief => 'Content',
		input_type => 'textarea',
	},
	check => sub {
		return 1;
	},
	exists => undef,
	get => sub {
		my ($c, $period, $name, $revision) = @_;
		if (!$revision) {
			$revision = $c->db_selectone("SELECT revision FROM content WHERE period_id = ? AND name = ? AND current = 1", {}, $period, $name);
		}
		if ($revision) {
			return $c->db_selectone("SELECT content FROM content WHERE period_id = ? AND name = ? AND revision = ?", {}, $period, $name, $revision);
		}
		return;
	},
},
id_clan => {
	defaults => {
		brief => 'Clan',
		readonly => [ qw/clan member team challenge/ ],
	},
	check => sub {
		/^\d+$/
	},
	default => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_selectone("SELECT id FROM clans INNER JOIN forumuser_clans ON clans.id = forumuser_clans.clan_id WHERE forumuser_clans.user_id = ? AND clans.period_id = ?", {}, $c->{userid}, $period);
		} else {
			return $c->db_selectone("SELECT id FROM clans INNER JOIN forumuser_clans ON clans.id = forumuser_clans.clan_id WHERE forumuser_clans.user_id = ?", {}, $c->{userid});
		}
	},
	exists => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_selectone("SELECT id FROM clans WHERE period_id = ? AND id = ?", {}, $period, $_);
		} else {
			return $c->db_selectone("SELECT id FROM clans WHERE id = ?", {}, $_);
		}
	},
	list => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_select("SELECT id, name FROM clans WHERE period_id = ? ORDER BY name", {}, $period);
		} else {
			return $c->db_select("SELECT id, CONCAT(name, ' (period ', period_id, ')') FROM clans ORDER BY period_id, name");
		}
	},
	infer => sub {
		my ($c) = @_;
		$c->db_select("SELECT period_id FROM clans WHERE id = ?", {}, $_);
	},
},
name_clan => {
	check => sub {
		/^[a-zA-Z0-9'!\[\] -]+$/
	},
	exists => sub {
		my ($c, $period, $clan_id) = @_;
		if ($period && $clan_id) {
			return $c->db_selectone("SELECT id FROM clans WHERE period_id = ? AND name = ? AND id != ?", {}, $period, $_, $clan_id);
		} elsif ($period) {
			return $c->db_selectone("SELECT id FROM clans WHERE period_id = ? AND name = ?", {}, $period, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
	get => sub {
		my ($c, $period, $clan_id) = @_;
		if ($period && $clan_id) {
			return $c->db_selectone("SELECT name FROM clans WHERE period_id = ? AND id = ?", {}, $period, $clan_id);
		} else {
			return;
		}
	},
},
info_clan => {
	check => sub {
		1
	},
	exists => undef,
	get => sub {
		my ($c, $period, $clan_id) = @_;
		if ($period && $clan_id) {
			return $c->db_selectone("SELECT looking FROM clans WHERE period_id = ? AND id = ?", {}, $period, $clan_id);
		} else {
			return;
		}
	},
},
url_clan => {
	check => sub {
		m#^http://[a-zA-Z0-9.]+(?::[0-9]+)?/\S*$#
	},
	exists => undef,
	get => sub {
		my ($c, $period, $clan_id) = @_;
		if ($period && $clan_id) {
			return $c->db_selectone("SELECT url FROM clans WHERE period_id = ? AND id = ?", {}, $period, $clan_id);
		} else {
			return;
		}
	},
},
tag_clan => {
	defaults => {
		brief => 'Tag',
	},
	check => sub {
		/^[A-Za-z0-9]{2,4}$/
	},
	exists => sub {
		my ($c, $period, $clan_id) = @_;
		if ($period && $clan_id) {
			return $c->db_selectone("SELECT id FROM clans WHERE period_id = ? AND tag = ? AND id != ?", {}, $period, $_, $clan_id);
		} elsif ($period) {
			return $c->db_selectone("SELECT id FROM clans WHERE period_id = ? AND tag = ?", {}, $period, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
	get => sub {
		my ($c, $period, $clan_id) = @_;
		if ($period && $clan_id) {
			return $c->db_selectone("SELECT tag FROM clans WHERE period_id = ? AND id = ?", {}, $period, $clan_id);
		} else {
			return;
		}
	},
},
id_kgs => {
	defaults => {
		brief => 'KGS username',
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c, $period, $clan_id, $member_id) = @_;
		use warnings;
		if ($period) {
			my $id = $c->db_selectone("SELECT id FROM kgs_usernames WHERE period_id = ? AND id = ?", {}, $period, $_);
			return $id;
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub {
		my ($c, $period, $clan_id, $member_id) = @_;
		if ($member_id) {
			return $c->db_select("SELECT id, nick FROM kgs_usernames WHERE member_id = ? ORDER BY nick", {}, $member_id);
		} elsif ($period) {
			return [sort { lc($a->[1]) cmp lc($b->[1]) } @{$c->db_select("SELECT id, nick FROM kgs_usernames WHERE period_id = ?", {}, $period)}];
		}
		return;
	},
},
name_kgs => {
	defaults => {
		brief => 'KGS username',
	},
	check => sub {
		use LWP::Simple;
		/^[a-zA-Z][a-zA-Z0-9]{0,9}$/ || return;
		my $contents = get('http://www.gokgs.com/gameArchives.jsp?user='.$_);
		if ($contents =~ /Games of KGS player/) {
			return 1;
		}
		return 1;
	},
	exists => sub {
		my ($c, $period) = @_;
		use warnings;
		if ($period) {
			my $id = $c->db_selectone("SELECT id FROM kgs_usernames WHERE period_id = ? AND nick = ?", {}, $period, $_);
			return $id;
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub { },
	get => sub {
		my ($c, $period, $clan, $member, $alias) = @_;
		if ($alias) {
			return $c->db_selectone("SELECT nick FROM kgs_usernames WHERE id = ?", {}, $alias);
		}
	}
},
id_member => {
	defaults => {
		brief => 'Member',
		readonly => [ qw/member alias/ ],
	},
	check => sub {
		/^\d+$/
	},
	filter_qualified => sub {
		my ($c, $params, $info) = @_;
		return $info->[1] >= $c->get_option('BRAWLMEMBERPOINTS', $params->[0]);
	},
	exists => sub {
		my ($c, $period, $clan, $team) = @_;
		if ($period && $clan && $team) {
			return $c->db_select("SELECT members.id, members.played + members.played_pure FROM clans INNER JOIN teams ON clans.id = teams.clan_id INNER JOIN team_members ON team_members.team_id = teams.id INNER JOIN members ON members.id = team_members.member_id WHERE clans.period_id = ? AND clans.id = ? AND teams.id = ? AND members.id = ?", {}, $period, $clan, $team, $_);
		} elsif ($period && $clan) {
			return $c->db_selectone("SELECT members.id, members.played + members.played_pure FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? AND members.id = ?", {}, $period, $clan, $_);
		} elsif ($period) {
			return $c->db_selectone("SELECT members.id, members.played + members.played_pure FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.period_id = ? AND members.id = ?", {}, $period, $_);
		} elsif ($clan) {
			return $c->db_selectone("SELECT id, members.played + members.played_pure FROM members WHERE clan_id = ? AND id = ?", {}, $clan, $_);
		} else {
			return $c->db_selectone("SELECT id, members.played + members.played_pure FROM members WHERE id = ?", {}, $_);
		}
	},
	get => sub {
		my ($c, $period, $clan, $team, $seat) = @_;
		if ($period && $clan && $team && $seat) {
			return $c->db_selectone("SELECT member_id FROM team_seats WHERE team_id = ? AND seat_no = ?", {}, $team, $seat-1);
		}
	},
	list => sub {
		my ($c, $period, $clan, $team) = @_;
		if ($period && $clan && $team) {
			return $c->db_select("SELECT members.id, members.name, members.played + members.played_pure FROM clans INNER JOIN teams ON clans.id = teams.clan_id INNER JOIN team_members ON team_members.team_id = teams.id INNER JOIN members ON members.id = team_members.member_id WHERE clans.period_id = ? AND clans.id = ? AND teams.id = ? ORDER BY members.name", {}, $period, $clan, $team);
		} elsif ($period && $clan) {
			return $c->db_select("SELECT members.id, members.name, members.played + members.played_pure FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? ORDER BY members.name", {}, $period, $clan);
		} elsif ($period) {
			return $c->db_select("SELECT members.id, CONCAT(members.name, ' (', clans.name, ')'), members.played + members.played_pure FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.period_id = ? ORDER BY clans.name, members.name", {}, $period);
		} elsif ($clan) {
			return $c->db_select("SELECT id, name, members.played + members.played_pure FROM members WHERE clan_id = ? ORDER BY members.name", {}, $clan);
		} else {
			return $c->db_select("SELECT members.id, CONCAT(members.name, ' (', clans.name, ', period ', clans.period_id, ')'), members.played + members.played_pure FROM members INNER JOIN clans ON members.clan_id = clans.id ORDER BY clans.period_id, clans.name, members.name");
		}
	},
	infer => sub {
		my ($c) = @_;
		$c->db_select("SELECT clans.period_id, clans.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE members.id = ?", {}, $_);
	},
},
name_member => {
	defaults => {
		brief => 'Member name',
	},
	check => sub {
		/^[a-zA-Z0-9 ,.-]+$/
	},
	exists => sub {
		my ($c, $period, $clan, $memberid) = @_;
		if ($period && $clan && $memberid) {
			return $c->db_selectone("SELECT members.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? AND members.name = ? AND members.id != ?", {}, $period, $clan, $_, $memberid);
		} elsif ($period && $clan) {
			return $c->db_selectone("SELECT members.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? AND members.name = ?", {}, $period, $clan, $_);
		} elsif ($period) {
			# Normally nonsense, but it's used in the case of creation of a new clan.
			return 0;
		} else {
			# Nonsense
			return 1;
		}
	},
	get => sub {
		my ($c, $period, $clan, $memberid) = @_;
		if ($memberid) {
			return $c->db_selectone("SELECT members.name FROM members WHERE members.id = ?", {}, $memberid);
		}
	}
},
rank_member => {
	defaults => {
		brief => 'Rank',
	},
	check => sub {
		/^[a-zA-Z0-9 ,'.-]*%?[a-zA-Z0-9 ,'.-]*$/
	},
	exists => undef,
	get => sub {
		my ($c, $period, $clan, $memberid) = @_;
		if ($memberid) {
			return $c->db_selectone("SELECT members.rank FROM members WHERE members.id = ?", {}, $memberid);
		}
	}
},
id_challenge => {
	defaults => {
		brief => 'Challenge',
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c, $period, $clan) = @_;
		if ($clan) {
			return $c->db_selectone("SELECT challenges.id FROM challenges INNER JOIN clans ON challenged_clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? AND challenges.id = ?", {}, $period, $clan, $_);
		} else {
			return $c->db_selectone("SELECT challenges.id FROM challenges INNER JOIN clans ON challenged_clan_id = clans.id WHERE clans.period_id = ? AND challenges.id = ?", {}, $period, $_);
		}
	},
	list => sub {
		my ($c, $period, $clan) = @_;
		if ($clan) {
			return $c->db_select("SELECT challenges.id, CONCAT(teams.name, ' (', clans.name, ')') FROM challenges INNER JOIN teams ON challenges.challenger_team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? AND challenged_clan_id = ? ORDER BY teams.name, clans.name", {}, $period, $clan);
		} else {
			return $c->db_select("SELECT challenges.id, CONCAT(teams.name, ' (', clans.name, ')') FROM challenges INNER JOIN teams ON challenges.challenger_team_id = teams.id INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? ORDER BY teams.name, clans.name", {}, $period);
		}
	},
	infer => sub {
		my ($c) = @_;
		$c->db_select("SELECT clans.period_id, clans.id FROM challenges INNER JOIN clans ON challenged_clan_id = clans.id WHERE challenges.id = ?", {}, $_);
	},
},
id_team => {
	defaults => {
		brief => 'Team',
		readonly => [ qw/team/ ],
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c, $period, $clan) = @_;
		if ($period && $clan) {
			return $c->db_selectone("SELECT teams.id FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? AND teams.id = ?", {}, $period, $clan, $_);
		} elsif ($period) {
			return $c->db_selectone("SELECT teams.id FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? AND teams.id = ?", {}, $period, $_);
		} elsif ($clan) {
			return $c->db_selectone("SELECT teams.id FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.id = ? AND teams.id = ?", {}, $clan, $_);
		} else {
			return $c->db_selectone("SELECT id FROM teams WHERE id = ?", {}, $_);
		}
	},
	list => sub {
		my ($c, $period, $clan) = @_;
		if ($period && $clan) {
			return $c->db_select("SELECT teams.id, teams.name FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? ORDER BY team_number", {}, $period, $clan);
		} elsif ($period) {
			return $c->db_select("SELECT teams.id, CONCAT(teams.name, ' (', clans.name, ')') FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? ORDER BY clans.name, team_number", {}, $period);
		} elsif ($clan) {
			return $c->db_select("SELECT teams.id, teams.name FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.id = ? ORDER BY team_number", {}, $clan);
		} else {
			return $c->db_select("SELECT teams.id, CONCAT(teams.name, ' (', clans.name, ', period ', clans.period_id, ')') FROM teams INNER JOIN clans ON teams.clan_id = clans.id ORDER BY period_id, clans.name, team_number");
		}
	},
	infer => sub {
		my ($c) = @_;
		$c->db_select("SELECT clans.period_id, clans.id FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE teams.id = ?", {}, $_);
	},
},
ready_team => {
	# "0.0" used instead of 0 because it == 0 and is also true.
	defaults => {
		brief => 'Team name',
	},
	check => sub {
		/^[a-zA-Z0-9 ,.-]+$/
	},
	exists => undef,
	list => sub {
		return [ [ 1, 'Ready' ], [ '0.0', 'Not ready' ] ];
	},
	get => sub {
		my ($c, $period, $clan, $teamid) = @_;
		if ($teamid) {
			return $c->db_selectone("SELECT IF(teams.in_brawl,1,'0.0') FROM teams WHERE teams.id = ?", {}, $teamid);
		}
	},
},
name_team => {
	defaults => {
		brief => 'Team name',
	},
	check => sub {
		/^[a-zA-Z0-9 ,.-]+$/
	},
	exists => sub {
		my ($c, $period, $clan, $team_id) = @_;
		my $where_extra = $team_id ? " AND teams.id != ?" : "";
		my @param_extra = $team_id ? ($team_id) : ();
		if ($period && $clan) {
			return $c->db_selectone("SELECT teams.id FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? AND clans.id = ? AND teams.name = ?$where_extra", {}, $period, $clan, $_, @param_extra);
		} elsif ($period) {
			return $c->db_selectone("SELECT teams.id FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.period_id = ? AND teams.name = ?$where_extra", {}, $period, $_, @param_extra);
		} elsif ($clan) {
			return $c->db_selectone("SELECT teams.id FROM teams INNER JOIN clans ON teams.clan_id = clans.id WHERE clans.id = ? AND teams.name = ?$where_extra", {}, $clan, $_, @param_extra);
		} else {
			# Nonsense
			return 1;
		}
	},
#	list => sub {}
	get => sub {
		my ($c, $period, $clan, $teamid) = @_;
		if ($teamid) {
			return $c->db_selectone("SELECT teams.name FROM teams WHERE teams.id = ?", {}, $teamid);
		}
	},
},
positions_team => {
	defaults => {
		brief => 'Team positions',
	},
	check => sub {
		/^[a-zA-Z0-9 ,.-]+$/
	},
	exists => undef,
#	list => sub {}
	get => sub {
		my ($c, $period, $clan, $team) = @_;
		if ($team) {
			# TODO should be more generic
			my $results = $c->db_select("SELECT team_seats.seat_no, members.id, members.name, members.rank FROM team_seats INNER JOIN members ON members.id = team_seats.member_id WHERE team_seats.team_id = ? ORDER BY team_seats.seat_no", {}, $team);
			return "Team has no seated members." if !$results || !@$results;
			my $result = "<ul>";
			for(@$results) {
				$result .= "<li>".($_->[0]+1).": ".$c->render_member($_->[1], $_->[2], $_->[3])."</li>";
			}
			$result .= "</ul>";
			return $result;
		}
	},
},
default => {
	modify => sub {
		$_ ||= $_[1];
	},
	exists => undef,
},
enum => {
	check => sub {
		my ($c, @list) = @_;
		my $s = $_ || '';
		return grep { $_ eq $s } @list;
	},
	exists => sub {
		my ($c, @list) = @_;
		my $val = $_ || '';
		grep { $_ eq $val } @list;
	},
	list => sub {
		my ($c, @list) = @_;
		return [map { [ $_, $_ ] } @list];
	},
},
text => {
	check => sub {
		/^[a-zA-Z0-9,.:\[\]\\\/>< \(\)'";!\r\n-]+$/
	},
	exists => undef,
#	list => sub { },
},
content_message => {
	check => sub {
		/^[a-zA-Z0-9`¬!"£\$\%^\&\*()\-=_+\[\]{};'#:@~,\.\/<>\? \r\n]+$/
	},
	exists => undef,
#	list => sub { },
},
name_action => {
	defaults => {
		brief => 'Action name',
	},
	exists => sub {
		my ($c) = @_;
		return $c->db_selectone("SELECT action FROM log WHERE action = ? LIMIT 1", {}, $_);
	},
	list => sub {
		my ($c) = @_;
		return $c->db_select("SELECT DISTINCT action, action FROM log ORDER BY action");
	},
},
format_action => {
	defaults => {
		brief => 'Log format',
	},
	check => sub {
		/^[a-zA-Z0-9 ',.\%_\]\[\{\}\-]+$/
	},
	exists => undef,
#	list => sub {}
	get => sub {
		my ($c, $action) = @_;
		if ($action) {
			return $c->db_selectone("SELECT format FROM log_formats WHERE action = ?", {}, $action);
		}
	},
},
id_period => {
	defaults => {
		brief => 'Clan period',
		hidden => [ qw/clan member alias team challenge/ ],
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c) = @_;
		return $c->db_selectone("SELECT id FROM clanperiods WHERE id = ?", {}, $_);
	},
	list => sub {
		my ($c) = @_;
		return $c->db_select("SELECT id, id FROM clanperiods ORDER BY id");
	},
	default => sub {
		my ($c) = @_;
		my $period_info = $c->period_info;
		return $period_info->{id};
	}
},
url => {
	check => sub {
		m#^http://[a-zA-Z0-9.]+(?::[0-9]+)?/\S*$#
	},
	exists => undef,
#	list => sub { },
},
id_forum => {
	defaults => {
		brief => 'Forum user',
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c) = @_;
		return $c->db_selectone("SELECT user_id FROM phpbb3_users WHERE user_id = ?", {}, $_);
	},
	list => sub {
		my ($c) = @_;
		return [ sort { lc $a->[1] cmp lc $b->[1] } @{$c->db_select("SELECT user_id, username FROM phpbb3_users ORDER BY username")} ];
	},
},
int_positive => {
	check => sub {
		/^[0-9]+$/
	},
	exists => undef,
},
boolean => {
	defaults => {
		input_type => 'checkbox',
	},
	check => sub {
		/^[01]$/
	},
	exists => undef,
},
);
