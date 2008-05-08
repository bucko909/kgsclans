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
			return $c->db_selectone("SELECT name FROM content WHERE clanperiod = ? AND name = ? AND current = 1", {}, $period, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_select("SELECT name, name FROM content WHERE clanperiod = ? AND current = 1", {}, $period);
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
			return $c->db_selectone("SELECT revision FROM content WHERE clanperiod = ? AND name = ? AND revision = ?", {}, $period, $name, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub {
		my ($c, $period, $name) = @_;
		if ($period && $name) {
			return $c->db_select("SELECT revision, revision FROM content WHERE clanperiod = ? AND name = ?", {}, $period, $name);
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
			$revision = $c->db_selectone("SELECT revision FROM content WHERE clanperiod = ? AND name = ? AND current = 1", {}, $period, $name);
		}
		if ($revision) {
			return $c->db_selectone("SELECT content FROM content WHERE clanperiod = ? AND name = ? AND revision = ?", {}, $period, $name, $revision);
		}
		return;
	},
},
id_clan => {
	defaults => {
		brief => 'Clan',
		readonly => [ qw/clan member brawl/ ],
	},
	check => sub {
		/^\d+$/
	},
	default => sub {
		my ($c, $period) = @_;
		return $c->db_selectone("SELECT id FROM clans INNER JOIN forumuser_clans ON clans.id = forumuser_clans.clan_id WHERE forumuser_clans.user_id = ?", {}, $c->{userid});
	},
	exists => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_selectone("SELECT id FROM clans WHERE clanperiod = ? AND id = ?", {}, $period, $_);
		} else {
			return $c->db_selectone("SELECT id FROM clans WHERE id = ?", {}, $_);
		}
	},
	list => sub {
		my ($c, $period) = @_;
		if ($period) {
			return $c->db_select("SELECT id, name FROM clans WHERE clanperiod = ?", {}, $period);
		} else {
			return $c->db_select("SELECT id, CONCAT(name, ' (period ', clanperiod, ')') FROM clans");
		}
	},
	infer => sub {
		my ($c) = @_;
		$c->db_select("SELECT clanperiod FROM clans WHERE id = ?", {}, $_);
	},
},
name_clan => {
	check => sub {
		/^[a-zA-Z0-9!\[\] ]+$/
	},
	exists => sub {
		my ($c, $period, $clan_id) = @_;
		if ($period && $clan_id) {
			return $c->db_selectone("SELECT id FROM clans WHERE clanperiod = ? AND name = ? AND id != ?", {}, $period, $_, $clan_id);
		} elsif ($period) {
			return $c->db_selectone("SELECT id FROM clans WHERE clanperiod = ? AND name = ?", {}, $period, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
#	list => sub { },
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
			return $c->db_selectone("SELECT id FROM clans WHERE clanperiod = ? AND tag = ? AND id != ?", {}, $period, $_, $clan_id);
		} elsif ($period) {
			return $c->db_selectone("SELECT id FROM clans WHERE clanperiod = ? AND tag = ?", {}, $period, $_);
		} else {
			# Nonsense
			return 1;
		}
	},
#	list => sub { },
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
			my $id = $c->db_selectone("SELECT id FROM aliases WHERE clanperiod = ? AND id = ?", {}, $period, $_);
			return $id;
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub {
		my ($c, $period, $clan_id, $member_id) = @_;
		if ($member_id) {
			return $c->db_select("SELECT id, nick FROM aliases WHERE member_id = ?", {}, $member_id);
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
	},
	exists => sub {
		my ($c, $period) = @_;
		use warnings;
		if ($period) {
			my $id = $c->db_selectone("SELECT id FROM aliases WHERE clanperiod = ? AND nick = ?", {}, $period, $_);
			return $id;
		} else {
			# Nonsense
			return 1;
		}
	},
	list => sub { },
},
id_member => {
	defaults => {
		brief => 'Member',
		readonly => [ qw/clan member alias/ ],
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c, $period, $clan, $team) = @_;
		if ($period && $clan && $team) {
			return $c->db_select("SELECT members.id, members.name FROM clans INNER JOIN brawl_teams ON clans.id = brawl_teams.clan_id INNER JOIN brawl_team_members ON brawl_team_members.team_id = brawl_teams.team_id INNER JOIN members ON members.id = brawl_team_members.member_id WHERE clans.clanperiod = ? AND clans.id = ? AND brawl_teams.team_id = ? AND members.id = ?", {}, $period, $clan, $team, $_);
		} elsif ($period && $clan) {
			return $c->db_selectone("SELECT members.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.clanperiod = ? AND clans.id = ? AND members.id = ?", {}, $period, $clan, $_);
		} elsif ($period) {
			return $c->db_selectone("SELECT members.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.clanperiod = ? AND members.id = ?", {}, $period, $_);
		} elsif ($clan) {
			return $c->db_selectone("SELECT id FROM members WHERE clan_id = ? AND id = ?", {}, $clan, $_);
		} else {
			return $c->db_selectone("SELECT id FROM members WHERE id = ?", {}, $_);
		}
	},
	list => sub {
		my ($c, $period, $clan, $team) = @_;
		if ($period && $clan && $team) {
			return $c->db_select("SELECT members.id, members.name FROM clans INNER JOIN brawl_teams ON clans.id = brawl_teams.clan_id INNER JOIN brawl_team_members ON brawl_team_members.team_id = brawl_teams.team_id INNER JOIN members ON members.id = brawl_team_members.member_id WHERE clans.clanperiod = ? AND clans.id = ? AND brawl_teams.team_id = ?", {}, $period, $clan, $team);
		} elsif ($period && $clan) {
			return $c->db_select("SELECT members.id, members.name FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.clanperiod = ? AND clans.id = ?", {}, $period, $clan);
		} elsif ($period) {
			return $c->db_select("SELECT members.id, CONCAT(members.name, ' (', clans.name, ')') FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.clanperiod = ?", {}, $period);
		} elsif ($clan) {
			return $c->db_select("SELECT id, name FROM members WHERE clan_id = ?", {}, $clan);
		} else {
			return $c->db_select("SELECT members.id, CONCAT(members.name, ' (', clans.name, ', period ', clans.clanperiod, ')') FROM members INNER JOIN clans ON members.clan_id = clans.id");
		}
	},
	infer => sub {
		my ($c) = @_;
		$c->db_select("SELECT clans.clanperiod, clans.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE members.id = ?", {}, $_);
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
			return $c->db_selectone("SELECT members.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.clanperiod = ? AND clans.id = ? AND members.name = ? AND members.id != ?", {}, $period, $clan, $_, $memberid);
		} elsif ($period && $clan) {
			return $c->db_selectone("SELECT members.id FROM members INNER JOIN clans ON members.clan_id = clans.id WHERE clans.clanperiod = ? AND clans.id = ? AND members.name = ?", {}, $period, $clan, $_);
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
#	list => sub { },
},
rank_member => {
	defaults => {
		brief => 'Rank',
	},
	check => sub {
		/^[a-zA-Z0-9 ,.-]*%?[a-zA-Z0-9 ,.-]*$/
	},
	exists => undef,
#	list => sub { },
},
id_brawlteam => {
	defaults => {
		brief => 'Brawl team',
		readonly => [ qw/clan brawl/ ],
	},
	check => sub {
		/^\d+$/
	},
	exists => sub {
		my ($c, $period, $clan) = @_;
		if ($period && $clan) {
			return $c->db_selectone("SELECT brawl_teams.team_id FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ? AND clans.id = ? AND brawl_teams.team_id = ?", {}, $period, $clan, $_);
		} elsif ($period) {
			return $c->db_selectone("SELECT brawl_teams.team_id FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ? AND brawl_teams.team_id = ?", {}, $period, $_);
		} elsif ($clan) {
			return $c->db_selectone("SELECT brawl_teams.team_id FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.id = ? AND brawl_teams.team_id = ?", {}, $clan, $_);
		} else {
			return $c->db_selectone("SELECT team_id FROM brawl_teams WHERE team_id = ?", {}, $_);
		}
	},
	list => sub {
		my ($c, $period, $clan) = @_;
		if ($period && $clan) {
			return $c->db_select("SELECT brawl_teams.team_id, brawl_teams.name FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ? AND clans.id = ?", {}, $period, $clan);
		} elsif ($period) {
			return $c->db_select("SELECT brawl_teams.team_id, CONCAT(brawl_teams.name, ' (', clans.name, ')') FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ?", {}, $period);
		} elsif ($clan) {
			return $c->db_select("SELECT brawl_teams.team_id, brawl_teams.name FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.id = ?", {}, $clan);
		} else {
			return $c->db_select("SELECT brawl_teams.team_id, CONCAT(brawl_teams.name, ' (', clans.name, ', period ', clans.clanperiod, ')') FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id");
		}
	},
	infer => sub {
		my ($c) = @_;
		$c->db_select("SELECT clans.clanperiod, clans.id FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE brawl_teams.team_id = ?", {}, $_);
	},
},
name_brawlteam => {
	defaults => {
		brief => 'Brawl team name',
	},
	check => sub {
		/^[a-zA-Z0-9 ,.-]+$/
	},
	exists => sub {
		my ($c, $period, $clan, $team_id) = @_;
		my $where_extra = $team_id ? " AND brawl_teams.team_id != ?" : "";
		my @param_extra = $team_id ? ($team_id) : ();
		if ($period && $clan) {
			return $c->db_selectone("SELECT brawl_teams.team_id FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ? AND clans.id = ? AND brawl_teams.name = ?$where_extra", {}, $period, $clan, $_, @param_extra);
		} elsif ($period) {
			return $c->db_selectone("SELECT brawl_teams.team_id FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.clanperiod = ? AND brawl_teams.name = ?$where_extra", {}, $period, $_, @param_extra);
		} elsif ($clan) {
			return $c->db_selectone("SELECT brawl_teams.team_id FROM brawl_teams INNER JOIN clans ON brawl_teams.clan_id = clans.id WHERE clans.id = ? AND brawl_teams.name = ?$where_extra", {}, $clan, $_, @param_extra);
		} else {
			# Nonsense
			return 1;
		}
	},
#	list => sub {}
	get => sub {
		my ($c, $period, $clan, $teamid) = @_;
		if ($teamid) {
			return $c->db_selectone("SELECT brawl_teams.name FROM brawl_teams WHERE brawl_teams.team_id = ?", {}, $teamid);
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
		/^[a-zA-Z0-9,:\[\]\-]+$/
	},
	exists => undef,
#	list => sub { },
},
id_clanperiod => {
	defaults => {
		brief => 'Clan period',
		hidden => [ qw/clan member alias brawl/ ],
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
		return $c->db_select("SELECT id, id FROM clanperiods");
	},
	default => sub {
		my ($c) = @_;
		return $c->getperiod();
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
		return $c->db_selectone("SELECT user_id FROM phpbb_users WHERE user_id = ?", {}, $_);
	},
	list => sub {
		my ($c) = @_;
		return $c->db_select("SELECT user_id, username FROM phpbb_users");
	},
},
);
