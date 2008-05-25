package Clans;

use strict;
use warnings;
use Time::Local;
use Time::HiRes;
use LWP::Simple;
use POSIX qw/strftime/;
use CGI;
use DBI;

sub new {
	my $this = {};
	bless $this;
	$this->{startup} = Time::HiRes::time();
	$this->{dbreqs} = 0;
	$this->{cgi} = new CGI;
	$this->get_dbi;
	$this->read_session;
	$this->read_common_params;
	return $this;
}

sub get_dbi {
	return $_[0]->{dbi} if exists $_[0]->{dbi};

	open MYCNF, "$ENV{HOME}/.my.cnf";
	local $/;
	my $contents = <MYCNF>;
	close MYCNF;
	my ($user, $database, $password);
	$user = $1 if $contents =~ /user = (.*)/;
	$database = $1 if $contents =~ /database = (.*)/;
	$password = $1 if $contents =~ /password = (.*)/;

	if (!$user || !$database || !$password) {
		$_[0]->die_fatal("Sorry, the .my.cnf file appears to be corrupt");
	}

	$_[0]->{dbi} = DBI->connect("dbi:mysql:database=$database", $user, $password);

	if (!$_[0]->{dbi}) {
		$_[0]->die_fatal_db("Sorry, I can't seem to connect to the database.");
	}

	return $_[0]->{dbi};
}

sub die_fatal {
	$_[0]->header("Argh") unless $_[0]->{header};
	print $_[0]->h2("Fatal error: $_[1]");
	print $_[0]->h3("$_[2]");
	$_[0]->footer;
	exit;
}

sub die_fatal_db {
	$_[0]->die_fatal($_[1], "Database says: ".DBI->errstr);
}

sub die_fatal_permissions {
	$_[0]->die_fatal($_[1], "You don't have permission to do that!");
}

sub die_fatal_badinput {
	$_[0]->die_fatal($_[1], "Your input was incomplete or invalid.");
}

sub render_member {
	my $this = shift;
	if (ref $_[0]) {
		@_ = ($_[0]{id}, $_[0]{name}, $_[0]{rank});
	} elsif (!$_[1]) {
		my $member = $this->member_info($_[0]);
		@_ = ($member->{id}, $member->{name}, $member->{rank});
	}
	my $name = qq(<a href="index.pl?page=games&amp;member=$_[0]">$_[1]</a>);
	return $name unless $_[2];
	if ($_[2] =~ /%/) {
		my $r = $_[2];
		$r =~ s/%/$name/;
		return $r;
	}
	return $_[2].' '.$name;
}

sub render_clan {
	my $this = shift;
	if (ref $_[0]) {
		@_ = ($_[0]{id}, $_[0]{name});
	} elsif (!$_[1]) {
		my $clan = $this->clan_info($_[0]);
		@_ = ($clan->{id}, $clan->{name});
	}
	return qq(<a href="index.pl?page=clan&amp;clan=$_[0]">$_[1]</a>);
}

sub render_team {
	my $this = shift;
	if (ref $_[0]) {
		@_ = ($_[0]{id}, $_[0]{name});
		my $clan_id = $this->db_selectone("SELECT clan_id FROM brawl_teams WHERE team_id = ?", {}, $_[0]);
		if (!$clan_id) {
			return "$_[1] (????)";
		} else {
			return "$_[1] (".$this->renderclan($clan_id).")";
		}
	} elsif (!$_[1]) {
		my $info = $this->db_selectrow("SELECT clan_id, nane FROM brawl_teams WHERE team_id = ?", {}, $_[0]);
		if (!$info) {
			return "????";
		} else {
			return "$info->[1] (".$this->renderclan($info->[0]).")";
		}
	}
}

sub header {
	my $this = $_[0];
	&die_clean_fatal("Header output twice?!") if $this->{header};
	$this->{header} = 1;
	my $cgi = new CGI;
	if ($this->{sess}) {
		my $sesscookie = $cgi->cookie(-name => 'sessid', -value => $this->{sess}->{id});
		print $cgi->header(-cookie => $sesscookie);
	} else {
		print $cgi->header;
	}
	if ($this->{dbi}) {
		$this->db_do("UPDATE hits SET hits=hits+1");
		$this->{hits} = $this->db_selectone("SELECT hits FROM hits");
	}
	print $cgi->start_html(-title => "Clan Stats", -style => { -src => 'style.css' }, -onLoad=>'if(set_focus){set_focus.focus();}', -script => 'var set_focus;');
	print $cgi->h1("Clan Stats");

	my $period = $cgi->param('period') ? '&amp;period='.$cgi->param('period') : '';

	print qq{<p class=nav><a href="index.pl?page=index$period">Summary</a> | <a href="index.pl?page=stats$period">Stats</a> | <a href="index.pl?page=help$period">Help</a> | <a href="/forum">Forum</a> | <a href="/brawl.pl$period">Brawl</a></p>};

	print $cgi->h2($_[1]) if $_[1];
	$this->{cgi} = $cgi;
	return $cgi;
}

sub footer {
	my $this = shift;
	my $cgi = $this->{cgi};
	my $time = Time::HiRes::time() - $this->{startup};
	print $cgi->p("Request took $time secs, made $this->{dbreqs} queries and is the $this->{hits}th pageload.");
	print $cgi->end_html;
}

sub db_do {
	my $this = shift @_;
	$this->{dbreqs}++;
	return $this->{dbi}->do(@_);
}

sub db_select {
	my $this = shift @_;
	$this->{dbreqs}++;
	return $this->{dbi}->selectall_arrayref(@_);
}

sub db_selectrow {
	my $this = shift @_;
	$this->{dbreqs}++;
	return $this->{dbi}->selectrow_arrayref(@_);
}

sub db_selectone {
	my $this = shift @_;
	my $row = $this->{dbi}->selectrow_arrayref(@_);
	$this->{dbreqs}++;
	return undef unless $row;
	return $row->[0];
}

sub lastid {
	my $this = shift @_;
	return $this->db_selectone("SELECT LAST_INSERT_ID();");
}

sub period_info {
	my ($this, $period_id) = @_;
	$period_id = 'this' if !defined $period_id;
	$this->{period_cache} ||= {};
	return $this->{period_cache}{$period_id} if exists $this->{period_cache}{$period_id};
	my $stuff;
	if ($period_id eq 'this') {
		$stuff = $this->db_selectrow("SELECT id, startdate, enddate FROM clanperiods ORDER BY id DESC LIMIT 1");
	} else {
		$stuff = $this->db_selectrow("SELECT id, startdate, enddate FROM clanperiods WHERE id = ?", {}, $period_id);
	}
	if ($stuff) {
		my $period = {
			id => $stuff->[0],
			startdate => $stuff->[1],
			enddate => $stuff->[2],
		};
		$this->{period_cache}{$period_id} = $period;
		$this->{period_cache}{$period->{id}} = $period if $period_id eq 'this';
		return $period;
	}
	$this->{period_cache}{$period_id} = undef;
	return;
}

sub clan_info {
	my ($this, $clan_id) = @_;
	$this->{clan_cache} ||= {};
	return $this->{clan_cache}{$clan_id} if exists $this->{clan_cache}{$clan_id};
	my @rows = qw/id name tag regex leader_id userid tag url looking clanperiod email forum_id forum_group_id forum_leader_group_id forum_private_id/;
	my $rows = join ',', @rows;
	my $stuff = $this->db_selectrow("SELECT $rows FROM clans WHERE id = ?", {}, $clan_id);
	if ($stuff) {
		my $clan = {};
		$clan->{$rows[$_]} = $stuff->[$_] for(0..$#rows);
		$this->{clan_cache}{$clan_id} = $clan;
		return $clan;
	}
	$this->{clan_cache}{$clan_id} = undef;
	return;
}

sub member_info {
	my ($this, $member_id) = @_;
	$this->{member_cache} ||= {};
	return $this->{member_cache}{$member_id} if exists $this->{member_cache}{$member_id};
	my @rows = qw/id name clan_id played won played_pure won_pure rank/;
	my $rows = join ',', @rows;
	my $stuff = $this->db_selectrow("SELECT $rows FROM members WHERE id = ?", {}, $member_id);
	if ($stuff) {
		my $member = {};
		$member->{$rows[$_]} = $stuff->[$_] for(0..$#rows);
		$this->{member_cache}{$member_id} = $member;
		return $member;
	}
	$this->{member_cache}{$member_id} = undef;
	return;
}

sub read_common_params {
	my ($this) = @_;
	if (my $member_id = $this->param('member')) {
		my $stuff = $this->member_info($member_id);
		if (!$stuff) {
			$this->die_fatal_badinput("Nonexistent member specified");
		}
		$this->{context_params} = "member=$stuff->{id}";
		$this->{member_info} = $stuff;
		$this->{clan_info} = $this->clan_info($stuff->{clan_id});
		$this->{period_info} = $this->period_info($this->{clan_info}{clanperiod});
		$this->{period_cache}{this} = $this->{period_info};
	} elsif (my $clan_id = $this->param('clan')) {
		my $stuff = $this->clan_info($clan_id);
		if (!$stuff) {
			$this->die_fatal_badinput("Nonexistent clan specified");
		}
		$this->{context_params} = "clan=$stuff->{id}";
		$this->{clan_info} = $stuff;
		$this->{period_info} = $this->period_info($stuff->{clanperiod});
		$this->{period_cache}{this} = $this->{period_info};
	} else {
		my $period_id = $this->param('period');
		my $stuff = $this->period_info($period_id);
		if (!$stuff) {
			$this->die_fatal_badinput("Nonexistent period specified");
		}
		$this->{context_params} = $period_id ? "period=$stuff->{id}" : "";
		$this->{period_info} = $stuff;
		$this->{period_cache}{this} = $this->{period_info};
	}
}

sub read_session {
	my $this = $_[0];
	my $sessid = $this->{cgi}->cookie('sessid');
	return unless $this->{dbi}; # Skip bad connects

	# Check PHPBB session!
	my $phpbbsessid = $this->{cgi}->cookie('phpbb3_lyix5_sid');
	if ($phpbbsessid) {
		my $sessuser = $this->db_selectrow("SELECT phpbb3_users.user_id, phpbb3_users.username FROM phpbb3_sessions INNER JOIN phpbb3_users ON phpbb3_users.user_id = phpbb3_sessions.session_user_id WHERE phpbb3_sessions.session_id = ?", {}, $phpbbsessid);
		if ($sessuser) {
			my $sessgroups = $this->db_select("SELECT phpbb3_groups.group_id, phpbb3_groups.group_name FROM phpbb3_user_group INNER JOIN phpbb3_groups ON phpbb3_user_group.group_id = phpbb3_groups.group_id WHERE phpbb3_user_group.user_id = ?", {}, $sessuser->[0]);
			my @groupids = $sessgroups ? map { $_->[0] } @$sessgroups : ();
			my @groupnames = $sessgroups ? map { $_->[1] } @$sessgroups : ();
			# Fetch group IDs, too.
			$this->{phpbbsess} = {
				id => $phpbbsessid,
				userid => $sessuser->[0],
				username => $sessuser->[1],
				groupids => \@groupids,
				groupnames => \@groupnames,
				summary => "$sessuser->[1] (".join(", ", @groupnames).")",
			};
			$this->{userid} = $sessuser->[0];
		} else {
			$this->{phpbbsess} = {
				id => $phpbbsessid,
				summary => "not logged in",
			};
		}
	}

	return $this->{sess};
}

# TODO hardcoded group numbers
sub is_admin {
	my ($c) = @_;
	my $isadmin;
	if ($c->{phpbbsess}{groupids}) {
		foreach my $groupid (@{$c->{phpbbsess}{groupids}}) {
			$isadmin = 1 if $groupid == 287;
		}
	}
	return $isadmin;
}
sub is_clan_leader {
	my ($c, $clan_id) = @_;
	my $isadmin;
	if ($c->{phpbbsess}{groupids}) {
		foreach my $groupid (@{$c->{phpbbsess}{groupids}}) {
			$isadmin = 1 if $groupid == 4 || $groupid == 287;
		}
	}
	return unless $isadmin;
	if ($clan_id) {
		return is_clan_moderator($c, $clan_id);
	} else {
		return 1;
	}
}

sub is_clan_moderator {
	my ($c, $clan_id) = @_;
	my $clan_info = $c->clan_info($clan_id);
	my $isadmin;
	if ($c->{phpbbsess}{groupids}) {
		foreach my $groupid (@{$c->{phpbbsess}{groupids}}) {
			$isadmin = 1 if $groupid == $clan_info->{forum_leader_group_id} || $groupid == 287;
		}
	}
	return $isadmin;
}

sub is_clan_member {
	my ($c, $clan_id) = @_;
	my $clan_info = $c->clan_info($clan_id);
	my $ismember;
	if ($c->{phpbbsess}{groupids}) {
		foreach my $groupid (@{$c->{phpbbsess}{groupids}}) {
			$ismember = 1 if $groupid == $clan_info->{forum_group_id} || $groupid == 287;
		}
	}
	return $ismember;
}

sub get_option {
	my ($this, $name, $period) = @_;
	$period ||= $this->{period_info}{id};
	return $this->db_selectone("SELECT value FROM options WHERE clanperiod = ? AND name = ?", {}, $period, $name);
}

sub log {
	my ($this, $action, $status, $message, $params) = @_;
	$this->db_do("INSERT INTO log SET action = ?, status = ?, message = ?, user_id = ?", {}, $action, $status, $message, $this->{userid});
	my $id = $this->lastid;
	for my $param_name (keys %$params) {
		$this->db_do("INSERT INTO log_params SET log_id = ?, param_name = ?, param_value = ?", {}, $id, $param_name, $params->{$param_name});
	}
}

sub baseurl {
	my $this = shift;
	my %vals = $this->{cgi}->Vars();
	delete $vals{$_} foreach (@_);
	if (keys %vals) {
		return '?'.(join '&amp;', map { "$_=$vals{$_}" } keys %vals).'&amp;';
	} else {
		return '?';
	}
}

sub hidden {
	return qq|<input type="hidden" name="$_[1]" value="$_[2]"/>|;
}

sub textarea {
	my $this = shift;
	return $this->{cgi}->textarea(@_);
}

sub textfield {
	my $this = shift;
	return $this->{cgi}->textfield(@_);
}

sub textfield_ {
	return qq|<input type="text" name="$_[1]" value="$_[2]" size="$_[3]" maxlength="$_[4]"/>|;
}

sub passfield {
	my $this = shift;
	return $this->{cgi}->password_field(@_);
}

sub param {
	my $this = shift;
	return $this->{cgi}->param(@_);
}

sub h1 {
	my $this = shift;
	return $this->{cgi}->h1(@_);
}

sub h2 {
	my $this = shift;
	return $this->{cgi}->h2(@_);
}

sub h3 {
	my $this = shift;
	return $this->{cgi}->h3(@_);
}

sub h4 {
	my $this = shift;
	return $this->{cgi}->h4(@_);
}

sub p {
	my $this = shift;
	return $this->{cgi}->p(@_);
}

sub submit {
	my $this = shift;
	return $this->{cgi}->submit(@_);
}

sub end_form {
	my $this = shift;
	return $this->{cgi}->end_form(@_);
}

sub escapeHTML {
	my $this = shift;
	return $this->{cgi}->escapeHTML(@_);
}

sub list {
	my $this = shift;
	print "<ul>";
	print "<li>$_</li>" foreach(@_);
	print "</ul>"
}

1;
