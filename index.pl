#!/usr/bin/perl

use strict;
use warnings;
use Clans;
use POSIX qw/strftime/;
use Carp qw/cluck/;
use Text::Textile;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = Clans->new;
my $sess = $c->getsession;

$c->header;

# ===========================================================
# STANDARD PARAM PARSING STUFF
# ===========================================================
{
	# Fetch clan period
	my $periodid = $c->param('period');
	if ($periodid && $periodid !~ /[^0-9]/) {
		$c->setperiod($periodid);
	}

	# Fetch clan, if any
	my $stuff;
	my $try = 0;
	if ($c->param("clanid")) {
		if (!$c->setclan_fromid($c->param("clanid"))) {
			$c->die_fatal_badinput("Clan ".($c->param("clanid"))." does not exist!");
		}
	}

	# Fetch member, if any (implies clan)
	$try = 0;
	if ($c->param("memberid")) {
		if (!$c->setmember_fromid($c->param("memberid"))) {
			$c->die_fatal_badinput("Member ".($c->param("memberid"))." does not exist!");
		}
	} elsif ($c->param("membername") && $c->{clanid}) {
		if (!$c->setmember_fromname_and_clanid($c->param("membername"), $c->{clanid})) {
			$c->die_fatal_badinput("Member ".($c->param("membername"))." does not exist!");
		}
	}

	if (!$c->{period}) {
		$c->setperiod($c->getperiod);
	}
}

our ($periodid, $clanid, $memberid) = ($c->{periodid}, $c->{clanid}, $c->{memberid});

my $pagename = $c->param("page");
$pagename = "index" unless $pagename && $pagename =~ /^\w+$/;
my $qstring = "page=$pagename";
for(qw/clanid memberid membername/) {
	$qstring .= "&amp;$_=".$c->param($_) if $c->param($_);
}

# ===========================================================
# PAGE RENDERING STUFF
# ===========================================================
my $page;
if ($c->param('revision')) {
	$page = $c->db_selectrow("SELECT content, revision, phpbb3_users.username, created FROM content INNER JOIN phpbb3_users ON phpbb3_users.user_id = content.creator WHERE clanperiod = ? AND name = ? AND revision = ?", {}, $c->{periodid}, $pagename, $c->param('revision'));
} else {
	$page = $c->db_selectrow("SELECT content, revision, phpbb3_users.username, created FROM content INNER JOIN phpbb3_users ON phpbb3_users.user_id = content.creator WHERE clanperiod = ? AND name = ? AND current = 1", {}, $c->{periodid}, $pagename);
}

if (!$page) {
	$page = [
		"h2. Page not found!\n\nThe page you are looking for ($pagename) did not exist...",
		0,
		"bucko",
		0,
	];
}

print &main_renderpage($c, $page->[0]);

# ===========================================================
# PAGE EDITING STUFF
# ===========================================================

if ($page->[1]) {
	print "<p>This page was created on ".strftime("%c", gmtime($page->[3]))." by $page->[2], and is revision $page->[1].";
	my $lqstring = $qstring;
	$lqstring .= "&amp;period=".$c->param('period') if $c->param('period');
	if ($page->[1] > 1) {
		print " Old revisions: ".join(' ', map { qq|<a href="index.pl?$lqstring&amp;revision=$_">$_</a>| } reverse (1..$page->[1]-1)).".";
	}
	if ($c->is_admin) {
		print qq| <a href="admin.pl?form=edit_page&amp;edit_page_name=$pagename&amp;edit_page_revision=$page->[1]">Edit</a>.|;
	}
	print "</p>";
} else {
	my $lqstring = $qstring;
	$lqstring .= "&amp;period=".$c->param('period') if $c->param('period');
	print qq|<p>This page is was not found. <a href="index.pl?$lqstring&amp;edit=1">Create it</a> (admin only).</p>|;
}

$c->footer;

our %persist;
our (%TABLEROWS, %GAMEROWS);
BEGIN {
	%TABLEROWS = (
		cn => { # clan_name
			sqlcols => [qw/clans.id clans.name clans.url/],
			title => "Clan",
			init => sub {},
			sort => 1,
			data => sub { $c->renderclan(@_[0,1]).($_[2] ? " (<a href=\"$_[2]\">web</a>)" : "") },
			totdata => sub { "" },
		},
		ct => { # clan_tag => {
			sqlcols => [qw/clans.id clans.tag/],
			title => "Tag",
			sort => 1,
			data => sub { $c->renderclan(@_[0,1]) },
		},
		ctb => { # clan_tag_bare => {
			sqlcols => [qw/clans.tag/],
			title => "Tag",
			data => sub { $_[0] },
		},
		cr => { # clan_recruiting => {
			sqlcols => [qw/clans.looking/],
			title => "Recruitment Info",
			data => sub { $_[0] || "" },
		},
		cf => { # clan_forum => {
			sqlcols => [qw/clans.forum_id clans.forum_private_id/],
			title => "Clan Forum",
			data => sub { ($_[0] ? "<a href=\"/forum/viewforum.php?f=$_[0]\">Public</a>" : "").($_[1] && 0 ? "<a href=\"/forum/viewforum.php?f=$_[1]\">Private</a>" : "") }, # TODO
		},
		cl => { # clan_leader => {
			sqlcols => [qw/members.id members.name members.rank/],
			title => "Leader",
			joins => [ "LEFT OUTER JOIN members ON clans.leader_id = members.id" ],
			sort => 1,
			data => sub { $_[0] ? $c->rendermember(@_[0,1,2]) : "" },
		},
		cmf => { # clan_members_full => {
			sqlcols => [qw/COUNT(mall.id) COUNT(mact.id)/],
			title => "Members (Active)",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id", "LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.played > 0 AND mact.id = mall.id" ],
			init => sub { $persist{mall} = 0; $persist{mact} = 0; },
			data => sub { $persist{mall} += $_[0]; $persist{mact} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { "$persist{mall} ($persist{mact})" },
		},
		cm => { # clan_members => {
			sqlcols => [qw/COUNT(mall.id)/],
			title => "Members",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{mall1} = 0 },
			data => sub { $persist{mall1} += $_[0]; $_[0] },
			totdata => sub { $persist{mall1} },
		},
		cma => { # clan_members_active => {
			sqlcols => [qw/COUNT(mact.id)/],
			title => "Active Members",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id", "LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.played > 0 AND mact.id = mall.id" ],
			init => sub { $persist{mact1} = 0 },
			data => sub { $persist{mact1} += $_[0]; $_[0] },
			totdata => sub { $persist{mact1} },
		},
		cp => { # clan_played_full => {
			sqlcols => [qw/points/],
			title => "Points",
			init => sub { $persist{points} = 0 },
			data => sub { $_[0] ||= 0; $persist{points} += $_[0]; $_[0] },
			totdata => sub { $persist{points} },
		},
		cpf => { # clan_played_full => {
			sqlcols => [qw/SUM(mall.played) SUM(mall.played_pure)/],
			title => "Games (Pure)",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{pall} = 0; $persist{ppure} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{pall} += $_[0]; $persist{ppure} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { my $pure = $persist{ppure} / 2; ($persist{pall} - $pure)." ($pure)" },
		},
		cpa => { # clan_played_all => {
			sqlcols => [qw/SUM(mall.played) SUM(mall.played_pure)/], # Pure needed for correction
			title => "Games",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{pall2} = 0; $persist{ppure2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{pall2} += $_[0]; $persist{ppure2} += $_[1]; "$_[0]" },
			totdata => sub { my $pure = $persist{ppure2} / 2; $persist{pall2} - $pure },
		},
		cpp => { # clan_played_pure => {
			sqlcols => [qw/SUM(mall.played_pure)/],
			title => "Pure Games",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{ppure1} = 0; },
			data => sub { $_[0] ||= 0; $persist{ppure1} += $_[0]; "$_[0]" },
			totdata => sub { $persist{ppure1} / 2 },
		},
		cpaf => { # clan_played_average_full => {
			sqlcols => [qw|SUM(mact.played)/COUNT(mact.id) SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Games per Active Member (Pure)",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{ppmall} = 0; $persist{ppmpure} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{ppmall} += $_[0]; $persist{ppmpure} += $_[1]; sprintf("%0.2f (%0.2f)", $_[0], $_[1]) },
			totdata => sub { my $pure = $persist{ppmpure} / 2; sprintf("%0.2f (%0.2f)", $persist{ppmall} - $pure, $pure) },
		},
		cpaa => { # clan_played_average_all => {
			sqlcols => [qw|SUM(mact.played)/COUNT(mact.id) SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Games per Active Member",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{ppmall2} = 0; $persist{ppmpure2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{ppmall2} += $_[0]; $persist{ppmpure2} += $_[1]; sprintf("%0.2f", $_[0]) },
			totdata => sub { my $pure = $persist{ppmpure} / 2; sprintf("%0.2f", $persist{ppmall2} - $pure) },
		},
		cpap => { # clan_played_average_pure => {
			sqlcols => [qw|SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Pure Games per Active Member",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{ppmpure1} = 0; },
			data => sub { $_[0] ||= 0; $persist{ppmpure1} += $_[0]; sprintf("%0.2f", $_[0]) },
			totdata => sub { sprintf("%0.2f", $persist{ppmpure1} / 2) },
		},
		cpaaf => { # clan_played_act_average_full => {
			sqlcols => [qw|SUM(mact.played)/COUNT(mact.id) SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Games per Active Member (Pure)",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id", "LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.played > 0 AND mact.id = mall.id" ],
			init => sub { $persist{ppmall} = 0; $persist{ppmpure} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{ppmall} += $_[0]; $persist{ppmpure} += $_[1]; sprintf("%0.2f (%0.2f)", $_[0], $_[1]) },
			totdata => sub { my $pure = $persist{ppmpure} / 2; sprintf("%0.2f (%0.2f)", $persist{ppmall} - $pure, $pure) },
		},
		cpaaa => { # clan_played_act_average_all => {
			sqlcols => [qw|SUM(mact.played)/COUNT(mact.id) SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Games per Active Member",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id", "LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.played > 0 AND mact.id = mall.id" ],
			init => sub { $persist{ppmall2} = 0; $persist{ppmpure2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{ppmall2} += $_[0]; $persist{ppmpure2} += $_[1]; sprintf("%0.2f", $_[0]) },
			totdata => sub { my $pure = $persist{ppmpure} / 2; sprintf("%0.2f", $persist{ppmall2} - $pure) },
		},
		cpaap => { # clan_played_act_average_pure => {
			sqlcols => [qw|SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Pure Games per Active Member",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id", "LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.played > 0 AND mact.id = mall.id" ],
			init => sub { $persist{ppmpure1} = 0; },
			data => sub { $_[0] ||= 0; $persist{ppmpure1} += $_[0]; sprintf("%0.2f", $_[0]) },
			totdata => sub { sprintf("%0.2f", $persist{ppmpure1} / 2) },
		},
		cwf => { # clan_won_full => {
			sqlcols => [qw/SUM(mall.won) SUM(mall.won_pure)/],
			title => "Games Won (Pure)",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{wall} = 0; $persist{wpure} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{wall} += $_[0]; $persist{wpure} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { $persist{wall} - $persist{wpure} },
		},
		cwa => { # clan_won_all => {
			sqlcols => [qw/SUM(mall.won) SUM(mall.won_pure)/],
			title => "Games Won",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{wall2} = 0; $persist{wpure2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{wall2} += $_[0]; $persist{wpure2} += $_[1]; "$_[0]" },
			totdata => sub { $persist{wall2} - $persist{wpure} },
		},
		cwp => { # clan_won_pure => {
			sqlcols => [qw/SUM(mall.won_pure)/],
			title => "Pure Games Won",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			init => sub { $persist{wpure1} = 0; },
			data => sub { $_[0] ||= 0; $persist{wpure1} += $_[0]; "$_[0]" },
			totdata => sub { "" },
		},
		cwpf => { # clan_win_percentage_full
			sqlcols => [qw#SUM(mall.won) SUM(mall.played) SUM(mall.won_pure) SUM(mall.played_pure) SUM(mall.won)/SUM(mall.played)#],
			title => "Games Won (Pure)",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			sort => 4,
			#sort => sub { ($b->[$_[1]] ? ($a->[$_[1]] ? $b->[$_[0]] / $b->[$_[1]] <=> $a->[$_[0]] / $a->[$_[1]] : -1) : 1) },
			init => sub { $persist{wpall} = 0; $persist{wppure} = 0; $persist{ppall} = 0; $persist{pppure} = 0; },
			data => sub { $persist{wpall2} += $_[0]; $persist{wppure2} += $_[2]; $persist{ppall2} += $_[1]; $persist{pppure2} += $_[3]; sprintf("%0.2d%% (%0.2d%%)", $_[1] ? $_[0] * 100 / $_[1] : 0, $_[3] ? $_[2] * 100 / $_[3] : 0) },
			totdata => sub { sprintf("%0.2d%%", ($persist{wpall} - $persist{ppall}) / ($persist{wppure} - $persist{pppure})) },
		},
		cwpa => { # clan_win_percentage_all
			sqlcols => [qw#SUM(mall.won) SUM(mall.played) SUM(mall.won_pure) SUM(mall.played_pure) SUM(mall.won)/SUM(mall.played)#],
			title => "Games Won",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			sort => 4,
			#sort => sub { ($b->[$_[1]] ? ($a->[$_[1]] ? $b->[$_[0]] / $b->[$_[1]] <=> $a->[$_[0]] / $a->[$_[1]] : -1) : 1) },
			init => sub { $persist{wpall2} = 0; $persist{wppure2} = 0; $persist{ppall2} = 0; $persist{pppure2} = 0; },
			data => sub { $persist{wpall2} += $_[0]; $persist{wppure2} += $_[2]; $persist{ppall2} += $_[1]; $persist{pppure2} += $_[3]; sprintf("%0.2d%%", $_[1] ? $_[0] * 100 / $_[1] : 0) },
			totdata => sub { sprintf("%0.2d%%", ($persist{wpall2} - $persist{ppall2}) / ($persist{wppure2} - $persist{pppure2})) },
		},
		cwpp => { # clan_win_percentage_pure
			sqlcols => [qw#SUM(mall.won_pure) SUM(mall.played_pure) SUM(mall.won_pure)/SUM(mall.played_pure)#],
			title => "Pure Games Won",
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id" ],
			sort => 2,
			#sort => sub { ($b->[$_[1]] ? ($a->[$_[1]] ? $b->[$_[0]] / $b->[$_[1]] <=> $a->[$_[0]] / $a->[$_[1]] : -1) : 1) },
			data => sub { sprintf("%0.2d%%", $_[1] ? $_[0] * 100 / $_[1] : 0) },
		},
		ma => {
			sqlcols => [qw/members.id members.name members.rank/],
			title => "Name",
			sort => 1,
			data => sub { $_[0] ? $c->rendermember(@_[0,1,2]) : "" },
		},
		mn => {
			sqlcols => [qw/members.id members.name/],
			title => "Name",
			sort => 1,
			data => sub { $_[0] ? $c->rendermember(@_[0,1], "") : "" },
		},
		mu => {
			sqlcols => [qw/members.id/],
			title => "Updates",
			data => sub { qq#<a href="update.pl?mode=member&amp;id=$_[0]">Update!</a># },
		},
		mm => {
			sqlcols => [qw/members.id clans.id/],
			title => "Miscelleneous",
			data => sub { qq#<a href="?page=clanadmin&amp;alter=set_clan_leader&amp;clanid=$_[1]&amp;memberid=$_[0]">New Leader</a># },
			#data => sub { qq#<a href="?page=clanadmin&amp;alter=set_clan_leader&amp;clanid=$_[1]&amp;memberid=$_[0]">New Leader</a> / Set Brawl Pos #.join(' ', map { qq#<a href="?page=clanadmin&amp;alter=set_member_brawl&amp;clanid=$_[1]&amp;memberid=$_[0]&amp;pos=$_">$_</a># } (1..5)).qq# <a href="?page=clanadmin&amp;alter=set_member_brawl&amp;clanid=$_[1]&amp;memberid=$_[0]&amp;pos=6">Reserve</a># },
		},
		mk => {
			sqlcols => ["GROUP_CONCAT(CONCAT(aliases.nick,IF(aliases.rank IS NOT NULL,CONCAT(' [',IF(aliases.rank>0,CONCAT(aliases.rank,'k'),CONCAT(1-aliases.rank,'d')),']'),'')) ORDER BY aliases.nick ASC SEPARATOR ', ')"],
			joins => [ 'LEFT OUTER JOIN aliases ON members.id = aliases.member_id' ],
			title => "KGS Usernames",
			data => sub { $_[0] },
		},
		mke => {
			sqlcols => ["GROUP_CONCAT(CONCAT(aliases.nick,IF(aliases.rank IS NOT NULL,CONCAT(' [',IF(aliases.rank>0,CONCAT(aliases.rank,'k'),CONCAT(1-aliases.rank,'d')),']'),'')) ORDER BY aliases.nick ASC SEPARATOR ', ')", qw/members.id clans.id/],
			joins => [ 'LEFT OUTER JOIN aliases ON members.id = aliases.member_id' ],
			title => "KGS Usernames",
			data => sub { join(', ', map { my$a=$_;$a=~s/\s+.*//;"$_ (<a href=\"?page=clanadmin&amp;clanid=$_[2]&amp;alter=remove_member_alias&amp;memberid=$_[1]&amp;alias=$a\">X</a>)" } split /, /, $_[0]) },
		},
		mne => {
			sqlcols => [qw/members.id members.name clans.id COUNT(aliases.id)/],
			joins => [ 'LEFT OUTER JOIN aliases ON members.id = aliases.member_id' ],
			title => "Name",
			init => sub {},
			sort => 1,
			data => sub { qq#<form method="post" action="?"><input type="hidden" name="page" value="clanadmin"/><input type="hidden" name="clan" value="$_[2]"/><input type="hidden" name="alter" value="set_member_name"/><input type="hidden" name="memberid" value="$_[0]"/><input type="text" name="name" value="$_[1]"/><input type="submit" value="OK"/></form>#.($_[3] == 0 ? " (<a href=\"?page=clanadmin*amp;clanid=$_[2]&amp;alter=remove_clan_member&amp;memberid=$_[0]\">X</a>)" : "") },
			totdata => sub { "" },
		},
		mre => {
			sqlcols => [qw/members.id members.rank clans.id/],
			title => "Rank",
			init => sub {},
			sort => 1,
			data => sub { my $r = $_[1] || ""; qq#<form method="post" action="?"><input type="hidden" name="page" value="clanadmin"/><input type="hidden" name="clan" value="$_[2]"/><input type="hidden" name="alter" value="set_member_rank"/><input type="hidden" name="memberid" value="$_[0]"/><input type="text" name="rank" value="$r"/><input type="submit" value="OK"/></form># },
			totdata => sub { "" },
		},
		mpf => { # member_played_full
			sqlcols => [qw/members.played members.played_pure/],
			title => "Games (Pure)",
			init => sub { $persist{mpf} = 0; $persist{mpf_2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{mpf} += $_[0]; $persist{mpf_2} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { "$persist{mpf} ($persist{mpf})" },
		},
		mpa => { # member_played_all
			sqlcols => [qw/members.played/], # Pure needed for correction
			title => "Games",
			init => sub { $persist{mpa} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{mpa} += $_[0]; "$_[0]" },
			totdata => sub { "$persist{mpa}" },
		},
		mpp => { # member_played_pure
			sqlcols => [qw/members.played_pure/],
			title => "Pure Games",
			init => sub { $persist{mpp} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{mpp} += $_[0]; "$_[0]" },
			totdata => sub { "$persist{mpp}" },
		},
		mwf => { # member_played_full
			sqlcols => [qw/members.won members.won_pure/],
			title => "Games Won (Pure)",
			init => sub { $persist{mwf} = 0; $persist{mwf_2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{mwf} += $_[0]; $persist{mwf_2} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { "$persist{mwf} ($persist{mwf})" },
		},
		mwa => { # member_played_all
			sqlcols => [qw/members.won/], # Pure needed for correction
			title => "Games Won",
			init => sub { $persist{mwa} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{mwa} += $_[0]; "$_[0]" },
			totdata => sub { "$persist{mwa}" },
		},
		mwp => { # member_played_pure
			sqlcols => [qw/members.won_pure/],
			title => "Pure Games Won",
			init => sub { $persist{mwp} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{mwp} += $_[0]; "$_[0]" },
			totdata => sub { "$persist{mwp}" },
		},
		mwpf => { # member_win_percentage_full
			sqlcols => [qw#members.played members.won members.played_pure members.won_pure members.won/members.played#],
			title => "% Games Won (Pure)",
			sort => 4,
			init => sub { $persist{mwpf} = 0; $persist{mwpf_2} = 0; $persist{mwpf_3} = 0; $persist{mwpf_4} = 0; },
			data => sub { $persist{mwpf} += $_[0]; $persist{mwpf_2} += $_[2]; $persist{mwpf_3} += $_[1]; $persist{mwpf_4} += $_[3]; sprintf("%0.2d%% (%0.2d%%)", $_[0] ? $_[1] * 100 / $_[0] : 0, $_[2] ? $_[3] * 100 / $_[2] : 0) },
			totdata => sub { sprintf("%0.2d%% (%0.2d%%)", $persist{mwpf} ? ($persist{mwpf2} * 100) / $persist{mwpf} : 0, $persist{mwpf3} ? ($persist{mwpf4} * 100) / $persist{mwpf3} : 0) },
		},
		mwpa => { # member_win_percentage_all
			sqlcols => [qw#members.played members.won members.won/members.played#],
			title => "% Games Won",
			sort => 2,
			init => sub { $persist{mwpa} = 0; $persist{mwpa_2} = 0; },
			data => sub { $persist{mwpa} += $_[0]; $persist{mwpa_2} += $_[2]; sprintf("%0.2d%%", $_[0] ? $_[1] * 100 / $_[0] : 0) },
			totdata => sub { sprintf("%0.2d%%", $persist{mwpa} ? ($persist{mwpa_2} * 100) / $persist{mwpa} : 0) },
		},
		mwpp => { # member_win_percentage_pure
			sqlcols => [qw#members.played_pure members.won_pure members.won_pure/members.played_pure#],
			title => "% Games Won",
			sort => 2,
			init => sub { $persist{mwpp} = 0; $persist{mwpp_2} = 0; },
			data => sub { $persist{mwpp} += $_[0]; $persist{mwpp_2} += $_[2]; sprintf("%0.2d%%", $_[0] ? $_[1] * 100 / $_[0] : 0) },
			totdata => sub { sprintf("%0.2d%%", $persist{mwpp} ? ($persist{mwpp_2} * 100) / $persist{mwpp} : 0) },
		},
#		mpr => { # member_win_percentage_pure
#			sqlcols => [qw#members.played*/MIN(games. members.won_pure members.won_pure/members.played_pure#],
#			title => "% Games Won",
#			sort => 2,
#			init => sub { $persist{mwpp} = 0; $persist{mwpp_2} = 0; },
#			data => sub { $persist{mwpp} += $_[0]; $persist{mwpp_2} += $_[2]; sprintf("%0.2d%%", $_[0] ? $_[1] * 100 / $_[0] : 0) },
#			totdata => sub { sprintf("%0.2d%%", $persist{mwpp} ? ($persist{mwpp2} * 100) / $persist{mwpp} : 0) },
#		},
	);
	%GAMEROWS = (
		w => {
			sqlcols => [qw#mw.id games.white mw.rank games.result games.url#],
			joins => [ " LEFT OUTER JOIN members mw ON white_id = mw.id" ],
			title => "White",
			sort => 1,
			data => sub { ($_[4] =~ /\?rengo2$/ ? "Partner + " : "").($_[3] == -1 ? "<b>" : "").($_[0] ? $c->rendermember($_[0], $_[1], $_[2]) : $_[1]).($_[3] == -1 ? "</b>" : "").($_[4] =~ /\?rengo1$/ ? " + partner" : "") },
			class => sub { ($_[3] == -1 ? "ahead" : ($_[3] ? "behind" : "")) },
		},
		wc => {
			sqlcols => [qw#cw.id cw.name games.result#],
			joins => [ "LEFT OUTER JOIN clans cw ON cw.id = mw.clan_id" ],
			title => "White Clan",
			sort => 1,
			data => sub { $_[0] ? $c->renderclan($_[0], $_[1]) : ""},
			class => sub { ($_[2] == -1 ? "ahead" : ($_[2] ? "behind" : "")) },
		},
		b => {
			sqlcols => [qw#mb.id games.black mb.rank games.result games.url#],
			joins => [ " LEFT OUTER JOIN members mb ON black_id = mb.id" ],
			title => "Black",
			sort => 1,
			data => sub { ($_[4] =~ /\?rengo2$/ ? "Partner + " : "").($_[3] == -1 ? "<b>" : "").($_[0] ? $c->rendermember($_[0], $_[1], $_[2]) : $_[1]).($_[3] == -1 ? "</b>" : "").($_[4] =~ /\?rengo1$/ ? " + partner" : "") },
			class => sub { ($_[3] == 1 ? "ahead" : ($_[3] ? "behind" : "")) },
		},
		bc => {
			sqlcols => [qw#mb.id cb.name games.result#],
			joins => [ "LEFT OUTER JOIN clans cb ON cb.id = mb.clan_id" ],
			title => "Black Clan",
			sort => 1,
			data => sub { $_[0] ? $c->renderclan($_[0], $_[1]) : ""},
			class => sub { ($_[2] == 1 ? "ahead" : ($_[2] ? "behind" : "")) },
		},
		k => {
			sqlcols => [qw#games.komi#],
			title => "Komi",
			sort => 0,
			data => sub { $_[0] },
		},
		h => {
			sqlcols => [qw#games.handicap#],
			title => "Handicap",
			sort => 0,
			data => sub { $_[0] },
		},
		r => {
			sqlcols => [qw#games.result games.result_by games.url#],
			title => "Result",
			sort => 0,
			data => sub { "<a href=\"$_[2]\">".($_[0] ? ($_[0] == -1 ? "W" : "B").$_[1] : "Draw")."</a>" },
		},
		t => {
			sqlcols => [qw#games.time#],
			title => "Time",
			sort => 0,
			data => sub { strftime("\%c", gmtime $_[0]) },
		}
	);
}

sub period_clantable {
	my ($c, $cols, $sort) = @_;
	my %persist;
	my %period_clans_table = (
		%TABLEROWS,
		ROWINIT => {
			sqlcols => [qw/got100time/],
			joins => [ " LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			           "LEFT OUTER JOIN members ON clans.leader_id = members.id" ], # Ensure this happens
			init => sub { },
			class => sub { $_[0] ? " class=\"qualified\"" : "" },
		}
	);
	my @cols = split /,/, ($c->param('ctcols') || $cols || 'cn,ct,cl,cmf,cpf,cwf,cpaf,cr');
	&main_drawtable($c, \%period_clans_table, \@cols, $c->param('sort') || $sort, "clans", "clanperiod = ".$c->{periodid});
}

sub period_topplayers {
	my ($c, $cols, $sort) = @_;
	my %persist;
	my %period_topplayers_table = (
		%TABLEROWS,
		ROWINIT => {
			joins => [ "LEFT OUTER JOIN clans ON clans.id = members.clan_id" ], # Ensure this happens
		},
	);
	my @cols = split /,/, $cols || 'mn,cn,mpf';
	&main_drawtable($c, \%period_topplayers_table, \@cols, "FIX:".$sort, "members", "clans.clanperiod = ".$c->{periodid}." AND members.played >= 10", "LIMIT 10");
}

sub membertable {
	my ($c, $clan, $cols, $sort) = @_;
	my $clause;
	if ($clan eq 'all') {
		$clause = "clans.clanperiod = ".$c->{periodid};
	} else {
		if (!$clan || $clan =~ /[^0-9]/) {
			if ($c->{clanid}) {
				$clause = "members.clan_id = ".$c->{clanid};
			} else {
				return "Invalid clan ID: \"$clanid\".";
			}
		} else {
			$clause = "members.clan_id = ".$clan;
		}
	}
	my %persist;
	my $reqpoints = $c->getoption('BRAWLMEMBERPOINTS');
	my %clan_members_table = (
		%TABLEROWS,
		ROWINIT => {
			sqlcols => [ qw/played played_pure/ ],
			joins => [ "INNER JOIN clans ON clans.id = members.clan_id" ], # Ensure this happens
			init => sub { },
			class => sub { $_[0] + $_[1] >= $reqpoints ? " class=\"qualified\"" : "" },
		},
	);
	my @cols = split /,/, ($c->param('cols') || $cols || 'ma,mpf,mwf');
	&main_drawtable($c, \%clan_members_table, \@cols, $c->param('sort') || $sort, "members", $clause);
}

sub member_gametable {
	my ($c, $memberid, $cols, $sort) = @_;
	my $clause;
	if (!$memberid || $memberid !~ /^\d+(?:\.\d+)?$/) {
		if ($c->{memberid}) {
			$memberid = $c->{memberid};
		} else {
			$memberid ||= "";
			return "Member ID \"$memberid\" is invalid.";
		}
		$clause = "games.white_id = $memberid OR games.black_id = $memberid";
	} else {
		$clause = "games.white_id = $memberid OR games.black_id = $memberid";
	}
	my @cols = split /,/, ($c->param('cols') || $cols || 't,w,b,k,h,r');
	&main_drawtable($c, \%GAMEROWS, \@cols, $c->param('sort') || $sort, "games", $clause);
}

sub period_gametable {
	my ($c, $clans, $cols, $sort) = @_;
	my $clause;
	if ($clans && $clans =~ /^(\d+)\.(\d+)$/) {
		$clause = "(cw.id = $1 AND cb.id = $2) OR (cw.id = $2 AND cb.id = $1)";
	} else {
		$clans ||= "";
		return "Clan IDs \"$clans\" are invalid.";
	}
	my @cols = split /,/, ($c->param('cols') || $cols || 't,wc,w,b,bc,k,h,r');
	&main_drawtable($c, \%GAMEROWS, \@cols, $c->param('sort') || $sort, "games", $clause);
}

sub main_drawtable {
	my ($c, $defs, $cols, $sort, $maintable, $where, $extra) = @_;

	my @cols = grep { $defs->{$_} && $defs->{$_}{data} } @$cols;
	my @allcols = ( $defs->{ROWINIT} ? ('ROWINIT', @cols) : (@cols) );

	my $joins = do {
		my %jointemp;
		$jointemp{$_} = 1 foreach map { @{$defs->{$_}{joins} || []} } @allcols;
		join ' ', sort keys %jointemp;
	};

	my @sqlcolidx = (0);
	my %colidx = ();
	my $selcols = do {
		my $sqlcolcount = 0;
		my $colcount = 0;
		my @sqlcols;
		foreach (@allcols) {
			$defs->{$_}{init}->() if $defs->{$_}{init};
			$colidx{$_} = $colcount;
			push @sqlcols, map { "$_ AS c".$sqlcolcount++ } @{$defs->{$_}{sqlcols}};
			#$sqlcolcount += scalar(@{$defs->{$_}{sqlcols}});
			push @sqlcolidx, $sqlcolcount;
			$colcount++;
		}
		join ',', @sqlcols;
	};

	# Modify sort to be column name, /and/ set sortrev to 1 if sort is reversed
	$sort ||= "";
	my $sortfix = $sort =~ s/FIX://;
	my $sortrev = $sort =~ s/^-//;
	unless ($sort && $defs->{$sort} && exists $colidx{$sort}) {
		$sort = "$cols[0]";
		$sortfix = 1;
		$sortrev = 0;
	}

	my $sqlsort = "";
	my $sortrule = $defs->{$sort}->{sort};
	if (!$sortrule) {
		$sqlsort = "ORDER BY c".$sqlcolidx[$colidx{$sort}]." ".($sortrev ? "DESC" : "ASC");
	} elsif (!ref $sortrule && $sortrule !~ /[^0-9]/) {
		$sqlsort = "ORDER BY c".($sqlcolidx[$colidx{$sort}] + $sortrule)." ".($sortrev ? "DESC" : "ASC");
	}

	# Note GROUP BY is a bit of a hack atm.
	$extra ||= "";
#	return("SELECT $selcols FROM $maintable $joins WHERE $where GROUP BY $maintable.id $sqlsort $extra;");
	my $info = $c->db_select("SELECT $selcols FROM $maintable $joins WHERE $where GROUP BY $maintable.id $sqlsort $extra;");

#	# Do sort.
#	{
#		my $col1 = $sqlcolidx[$colidx{$sort}];
#		my $col2 = $sqlcolidx[$colidx{$sort}+1]-1;
#		my $sret = $defs->{$sort}{sort};
#		my @info = (sort { $sret->($col1..$col2) } @$info);
#		@info = reverse @info if $sortrev;
#		$info = \@info;
#	}

	# Title row.
	my $table = "<table class=\"clans\"><tr>".(join '', map { $defs->{$_}{data} ? "<th>$defs->{$_}{title}</th>" : '' } @allcols)."</tr>";

	# Navigation row.
	$table .= "<tr class=\"nav\">";
	my $baseurl1 = $c->baseurl('cols');
	my $baseurl2 = $c->baseurl('sort');
	foreach my $col (0..$#cols) {
		next unless $defs->{$cols[$col]}{data};
		my $delset = "<a href=\"${baseurl1}cols=".(join ',', @cols[0..$col-1,$col+1..$#cols])."\">X</a>";
		my $lset = $col != 0 ? "<a href=\"${baseurl1}cols=".(join ',', @cols[0..$col-2,$col,$col-1,$col+1..$#cols])."\">&lt;</a>" : '';
		my $rset = $col != $#cols ? "<a href=\"${baseurl1}cols=".(join ',', @cols[0..$col-1,$col+1,$col,$col+2..$#cols])."\">&gt;</a>" : '';
		$table .= "<td><a href=\"${baseurl2}sort=$cols[$col]\">sort</a>&nbsp;(<a href=\"${baseurl2}sort=-$cols[$col]\">rev</a>)<br/>$lset&nbsp;$delset&nbsp;$rset</td>";
	}
	$table .= "</tr>";

	# Data rows.
	foreach my $row (@$info) {
		my $start;
		if ($allcols[0] eq 'ROWINIT' && $defs->{ROWINIT}{class}) {
			$start = 1;
			$table .= "<tr ".$defs->{ROWINIT}{class}->(@$row[$sqlcolidx[0]..$sqlcolidx[1]-1]).">";
		} else {
			$start = 0;
			$table .= "<tr>";
		}
		#local $SIG{__WARN__} = sub { };
		foreach my $colno ($start .. $#allcols) {
			my $col = $allcols[$colno];
			my $class = "";
			if ($defs->{$col}{class}) {
				$class = " class=\"".$defs->{$col}{class}->(@$row[$sqlcolidx[$colno]..$sqlcolidx[$colno+1]-1])."\"";
			}
			if ($defs->{$col}{data}) {
				#print STDERR "$col $sqlcolidx[$colno] $sqlcolidx[$colno+1]".$defs->{$col}{data}->(@$clan[$sqlcolidx[$colno]..$sqlcolidx[$colno+1]])."\n";
				$table .= "<td$class>".$defs->{$col}{data}->(@$row[$sqlcolidx[$colno]..$sqlcolidx[$colno+1]-1])."</td>";
			}
		}
		$table .= "</tr>";
	}

	# Total rows.
	$table .= "<tr>";
	foreach my $col (@cols) {
		next unless $defs->{$col}{data};
		$table .= $defs->{$col}{totdata} ? "<td>".$defs->{$col}{totdata}->()."</td>" : "<td></td>";
	}
	$table .= "</tr>";

	$table .= "</table>";

	# Add rows.
	#{
	#	my	$baseurl = $c->baseurl('cols');
	#	my @add = grep { !exists $colidx{$_} } keys %$defs;
	#	print "<p>Add: ".(join ' ', map { "<a href=\"${baseurl}cols=".(join ',', @cols, $_ )."\">$_</a>" } sort @add)."</p>";
	#}
	return $table;
}

sub clan_brawllist {
	my ($c, $clanid) = @_;
	$clanid = $c->{clanid} if !$clanid || $clanid =~ /[^0-9]/;
	if (!$clanid) {
		return "Clan ID \"$clanid\" is invalid";
	}
	my $teams = $c->db_select("SELECT team_id, name FROM brawl_teams WHERE clan_id = ?", {}, $clanid);
	if (!$teams || !@$teams) {
		return "<h3>Brawl Teams</h3><p>No brawl teams created!</p>";
	}
	my $out = '<h3>Brawl Teams</h3>';
	for(@$teams) {
		$out .= "<h4>";
		$out .= $_->[1] ? $_->[1] : "Main";
		$out .= "</h4>";
		$out .= clan_brawl_memberlist($c, $_->[0]);
	}
	return $out;
}

sub clan_brawl_memberlist {
	my ($c, $teamid) = @_;
	if (!$teamid) {
		return "Team ID \"$teamid\" is invalid";
	}
	my $results = $c->db_select("SELECT members.id, members.name, members.rank, brawl.position FROM brawl INNER JOIN members ON members.id = brawl.member_id WHERE brawl.team_id = ?", {}, $teamid);
	my @brawl;
	return "No brawl positions defined" if !$results;
	$brawl[5] = undef;
	$brawl[$_->[3]-1] = $_ foreach (@$results);
	my $result = "<ol>";
	for(0..4) {
		$result .= "<li value=\"".($_+1)."\">".($brawl[$_] ? $c->rendermember($brawl[$_][0], $brawl[$_][1], $brawl[$_][2]) : "Not set.")."</li>";
	}
	$result .= "</ol>";
	$result .= "<p>Reserve: ".$c->rendermember($brawl[5][0], $brawl[5][1], $brawl[5][2])."</p>" if $brawl[5];
	return $result;
}

our @brawl_available;
sub clan_brawl_memberadmin {
	my ($c, $teamid, $clanid) = @_;
	if (!$teamid) {
		return "Team ID \"$teamid\" is invalid";
	}
	my $results = $c->db_select("SELECT members.id, members.name, members.rank, brawl.position FROM brawl INNER JOIN members ON members.id = brawl.member_id WHERE brawl.team_id = ?", {}, $teamid);

	my @brawl;
	return "No brawl positions defined" if !$results;
	$brawl[5] = undef;
	$brawl[$_->[3]-1] = $_ foreach (@$results);
	my $result;
	$result .= "<ol>";
	for(0..4) {
		$result .= "<li value=\"".($_+1)."\">".($brawl[$_] ? $c->rendermember($brawl[$_][0], $brawl[$_][1], $brawl[$_][2]) : "Not set.");
		$result .= qq|<form method="post" action="?"><input type="hidden" name="clanid" value="$clanid"/><input type="hidden" name="periodid" value="5"/><input type="hidden" name="team_id" value="$teamid"/><input type="hidden" name="page" value="clanadmin"/><input type="hidden" name="alter" value="set_member_brawl"/><input type="hidden" name="pos" value="@{[$_+1]}"/><select name="memberid">|;
		$result .= qq|<option value="$_->[0]">$_->[1]</option>| foreach(@brawl_available);
		$result .= qq|</select><input type="submit" value="Submit"/></form></p>|;
		$result .= qq|(<a href="?clanid=$clanid&amp;team_id=$teamid&amp;page=clanadmin&amp;alter=clear_brawl_team_pos&amp;pos=@{[$_]}">X</a>)|;
		$result .= "</li>";
	}
	$result .= "</ol>";
	$result .= "<p>Reserve: ".$c->rendermember($brawl[5][0], $brawl[5][1], $brawl[5][2])."</p>" if $brawl[5];
	return $result;
}

sub clan_brawladmin {
	my ($c, $clanid) = @_;
	$clanid = $c->{clanid} if !$clanid || $clanid =~ /[^0-9]/;
	if (!$clanid) {
		return "Clan ID \"$clanid\" is invalid";
	}
	#@brawl_available = @{ $c->db_select("SELECT members.id, members.name FROM members LEFT OUTER JOIN brawl ON brawl.member_id = members.id WHERE members.clan_id = ? AND brawl.team_id IS NULL",
	@brawl_available = @{ $c->db_select("SELECT members.id, members.name FROM members WHERE members.clan_id = ?", {}, $clanid) || [] }; 
	my $teams = $c->db_select("SELECT team_id, name FROM brawl_teams WHERE clan_id = ?", {}, $clanid);
	if (!$teams || !@$teams) {
		return "<p>No brawl teams created!</p>";
	}
	my $out = '<h3>Brawl Teams</h3>';
	for(@$teams) {
		$out .= "<h4>";
		$out .= $_->[1] ? $_->[1] : "Main";
		$out .= "</h4>";
		$out .= qq|<p>Change team name to: <form method="get" action="?"><input type="hidden" name="clanid" value="$clanid"/><input type="hidden" name="team_id" value="$_->[0]"/><input type="hidden" name="page" value="clanadmin"/><input type="hidden" name="alter" value="set_clan_brawl_team_name"/><input type="text" name="teamname" value=""/> <input type="submit" value="Submit"/></form></p>|;
		$out .= clan_brawl_memberadmin($c, $_->[0], $clanid);
		$out .= qq|<p><a href="?clanid=$clanid&amp;team_id=$_->[0]&amp;page=clanadmin&amp;alter=delete_clan_brawl_team">Delete this team</a>.</p>|;
	}
	return $out;
}


sub main_newperiod {
	# Does not work yet, but here is SQL I used last time:
	my $SQL = '
	INSERT INTO clanperiods VALUES($newid, $starttime, $endtime);
	INSERT INTO front_page SELECT text, $newid, textid FROM front_page WHERE clanperiod = $oldid;
	INSERT INTO clans SELECT NULL, clans.name, clans.regex, 0, clans.userid, clans.tag, clans.url, clans.looking, $newid, 0 FROM clans INNER JOIN members ON clans.id = members.clan_id WHERE clanperiod = $oldid GROUP BY clans.id HAVING SUM(played) >= $clanthreshold;
	DELETE FROM users USING users LEFT OUTER JOIN clans ON clans.userid = users.id AND clans.clanperiod = $newid WHERE users.adminlevel = 0 AND users.id != 1 AND clans.id IS NULL;
	INSERT INTO members SELECT NULL, members.name, c2.id, 0, 0, 0, 0, NULL FROM members INNER JOIN clans c1 ON members.clan_id = c1.id AND c1.clanperiod = $oldid INNER JOIN clans c2 ON c1.tag = c2.tag AND c2.clanperiod = $newid WHERE played > $memberthreshold;
	INSERT INTO aliases SELECT NULL, 0, m2.id, aliases.nick, NULL, $newid, $time FROM aliases INNER JOIN members m1 ON aliases.member_id = m1.id INNER JOIN clans c1 ON m1.clan_id = c1.id AND c1.clanperiod = $oldid INNER JOIN clans c2 ON c1.tag = c2.tag AND c2.clanperiod = $newid INNER JOIN members m2 ON m2.name = m1.name AND m2.clan_id = c2.id;
	CREATE TEMPORARY TABLE temp SELECT c2.id, c1.leader_id FROM clans c1 INNER JOIN clans c2 ON c1.tag = c2.tag AND c1.clanperiod = 2 AND c2.clanperiod = 3 INNER JOIN members m1 on m1.id = c1.leader_id INNER JOIN members m2 ON m2.name = m1.name AND m2.clan_id = c2.id;
	UPDATE clans INNER JOIN temp ON clans.id = temp.id SET clans.leader_id = temp.leader_id;';
}

sub main_renderpage {
	my ($c, $content) = @_;

	my $textile = Text::Textile->new();
	my $formatted = $textile->process($content);
	$formatted =~ s#%%([A-Z0-9_]+)(?::(.*?))?%%#&main_format($c, $1, split /:/, ($2||""))#eg;
	return $formatted;
}

sub clan_forummembers {
	my ($c, $name, @params) = @_;
	return 'No clan' unless $c->{clanid};
	"<ul>".
		(join '', map{
			qq|<li><a href="/forum/profile.php?mode=viewprofile&amp;u=$_->[0]">$_->[1]</a></li>|
		}
		@{$c->db_select("SELECT phpbb3_users.user_id, phpbb3_users.username FROM phpbb3_users INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_group_id WHERE clans.id = ? ORDER BY username", {}, $c->{clanid})})
	."</ul>";
}

sub clan_forummoderators {
	my ($c, $name, @params) = @_;
	return 'No clan' unless $c->{clanid};
	"<ul>".
		(join '', map{
			qq|<li><a href="/forum/profile.php?mode=viewprofile&amp;u=$_->[0]">$_->[1]</a></li>|
		}
		@{$c->db_select("SELECT phpbb3_users.user_id, phpbb3_users.username FROM phpbb3_users INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_leader_group_id WHERE clans.id = ? ORDER BY username", {}, $c->{clanid})})
	."</ul>";
}

sub main_format {
	my ($c, $name, @params) = @_;
	my %main_formats = (
		CLANTABLE => sub { &period_clantable(@_) },
		MEMBERTABLE => sub { &membertable(@_) },
		GAMETABLE => sub { &member_gametable(@_) },
		FORUMMEMBERS => sub { &clan_forummembers(@_) },
		FORUMMODERATORS => sub { &clan_forummoderators(@_) },
		CLANVCLANTABLE => sub { &period_gametable($_[0], $c->param("clans"), $_[2], $_[3]) },
		TOPPLAYERS => sub { &period_topplayers(@_) },
		CLANGRID => sub { &period_clangrid(@_) },
		BRAWL => sub { &clan_brawllist(@_) },
		BRAWLADMIN => sub { &clan_brawladmin(@_) },
		LOCALPAGE => sub {
			my ($c, $name, $text) = @_;
			my $url = $c->baseurl('page','alter')."page=$name";
			qq|<a href="$url">$text</a>|;
		},
		PERIODINFO => sub {
			my $c = $_[0];
			my $periodinfo = $c->db_selectrow("SELECT id, startdate, enddate FROM clanperiods WHERE id = ?", {}, $c->{periodid});
			my $nextperiodinfo = $c->db_selectrow("SELECT id, startdate, enddate FROM clanperiods WHERE id = ?", {}, $c->{periodid} + 1);
			my $text = "This is period $periodinfo->[0]; it started at ".strftime("%c", gmtime($periodinfo->[1]))." and will end at ".strftime("%c", gmtime($periodinfo->[2])).". Go to ";
			if ($nextperiodinfo) {
				$text .= qq|<a href="index.pl?$qstring&amp;period=|.($c->{periodid}+1).qq|">next</a>|;
				$text .= " or " if $periodinfo->[0] > 1;
			}
			if ($periodinfo->[0] > 1) {
				$text .= qq|<a href="index.pl?$qstring&amp;period=|.($c->{periodid}-1).qq|">previous</a>|;
			}
			$text .= " clan period."
		},
		ADMINLIST => sub {
			my $c = $_[0];
			my $admins = $c->db_select("SELECT name FROM users WHERE adminlevel = 127");
			return '<ul>'.(join '', map { "<li>$_->[0]</li>" } @$admins).'</ul>';
		},
		USERNAME => sub {
			my $c = $_[0];
			#return $c->{sess}{username}.($c->{phpbbsess} ? " (BB: $c->{phpbbsess}{username})" : " (BB: no session)");
			return ($c->{phpbbsess} ? "$c->{phpbbsess}{summary}" : "anonymous (no session)");
		},
		CLAN => sub {
			return $_[0]->renderclan($_[0]->{clan});
		},
		CLANS => sub {
			my $clans = $c->param("clans");
			if ($clans && $clans =~ /^(\d+).(\d+)$/) {
				return $_[0]->renderclan($1)." and ".$_[0]->renderclan($2);
			} else {
				return "? and ?";
			}
		},
		MEMBER => sub {
			return $_[0]->rendermember($_[0]->{member});
		},
		CLANID => sub {
			return $_[0]->{clan}{id};
		},
#		LOGINFORM => sub {
#			my $c = $_[0];
#			return $c->loginform;
#		},
		BEGIN_FORM => sub {
			my $c = $_[0];
			my $meth = $_[3] || "get";
			my $form = qq#<form method="$meth" action="?">#;
			$form .= qq#<input type="hidden" name="clanid" value="#.$c->{clanid}.qq#"/># if $_[1] eq 'clan';
			$form .= qq#<input type="hidden" name="periodid" value="#.$c->{periodid}.qq#"/># if $_[1] eq 'period' || $_[1] eq 'clan';
			$form .= qq#<input type="hidden" name="page" value="#.$c->param('page').qq#"/># if $c->param('page');
			$form .= qq#<input type="hidden" name="alter" value="$_[2]"/># if $_[2];
			return $form;
		},
		TEXTFIELD => sub {
			my $c = $_[0];
			my $value = "";
			if ($_[2]) {
				if ($_[2] =~ /clan\.(.*)/) {
					$value = $c->{clan}{$1} || "";
				}
			}
			return qq|<input type="text" name="$_[1]" value="$value"/>|;
		},
		SUBMIT => sub {
			my $text = $_[1] || "Submit";
			return qq|<input type="submit" value="$text"/>|;
		},
		END_FORM => sub {
			return "</form>";
		}
	);
	if ($main_formats{$name}) {
		return $main_formats{$name}->($c, @params);
	}
	return "Unknown format...";
}

sub period_clangrid {
	my ($c) = @_;
	# =========
	# CLAN GRID
	# =========
	my $info = $c->db_select("SELECT c1.id, c1.tag, c2.id, c2.tag, clangrid.played, clangrid.won FROM clangrid INNER JOIN clans c1 ON c1.id = clangrid.x INNER JOIN clans c2 ON c2.id = clangrid.y ORDER BY c1.tag, c2.tag;");
	my $cclan = 0;
	my $firstrow = 1;
	my ($content, $header);
	my $out = "<table class=\"clangrid\">";
	foreach my $row (@$info) {
		if ($row->[0] != $cclan) {
			if ($cclan != 0) {
				$out .= $header."</tr>" if $firstrow;
				$out .= $content."</tr>";
				$firstrow = 0;
			}
			$content = "<tr><th>".$c->renderclan(@{$row}[0,1])."</th>";
			$header = "<tr><th></th>" if $firstrow;
			$cclan = $row->[0];
		}
		$header .= "<th>".$c->renderclan(@{$row}[2,3])."</th>" if $firstrow;
		if ($row->[4]) {
			my $class;
			if ($row->[5] * 2 > $row->[4]) {
				$class = "ahead";
			} elsif ($row->[5] * 2 < $row->[4]) {
				$class = "behind";
			} else {
				$class = "equal";
			}
			$content .= "<td class=\"$class\"><a href=\"?page=clanvclan&amp;clans=$row->[0].$row->[2]\">$row->[4]</a> ($row->[5])</td>";
		} else {
			$content .= "<td class=\"nogames\"></td>";
		}
	}
	$out .= $header."</tr>" if $firstrow;
	$out .= $content."</tr>";
	$out .= "</table>";
}

__DATA__
} elsif ($mode eq 'brawl') {
# Fetch clan period
my $periodid = $c->param('period');
my $periodspecified = $periodid ? 1 : 0;
$periodid ||= $c->getperiod;

$c->header("Brawl");

my $brawldraw = $c->db_select("SELECT round, position, clan_id, clans.name, nextround_pos FROM brawldraw LEFT OUTER JOIN clans ON clan_id = clans.id WHERE brawldraw.clanperiod = ?", {}, $periodid);
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

foreach(0..$#draw) {
print $c->h4("Round ".($_+1));
my @rounddraw = @{$draw[$_]};
my @roundresults = @{$results[$_] || []};
foreach(0..$#rounddraw) {
if ($_ % 2 == 1 && (!$rounddraw[$_][2] || !$rounddraw[$_-1][2])) {
next;
} elsif ($_ % 2 == 0 && !$rounddraw[$_][2]) {
if (!$rounddraw[$_+1][2]) {
# WTF?!
next;
}
print $c->p("Bye for ".$c->renderclan($rounddraw[$_+1][2], $rounddraw[$_+1][3]));
next;
} elsif ($_ % 2 == 0 && !$rounddraw[$_+1][2]) {
print $c->p("Bye for ".$c->renderclan($rounddraw[$_][2], $rounddraw[$_][3]));
next;
}
my $clan = $c->renderclan($rounddraw[$_][2], $rounddraw[$_][3]);
my $class = defined $rounddraw[$_][4] ? "clan_won" : "clan_lost";
if ($_ % 2 == 0) {
print "<table class=\"brawldraw\">";
print "<tr><td colspan=\"5\" class=\"$class\">$clan</td></tr>";
}
my $rowclass = $_ % 2 ? "players_bottom" : "players_top";
print "<tr class=\"$rowclass\">";
my @games = @{$roundresults[$_]};
foreach(0..4) {
					my $class = ($games[$_][6] ? "player_black" : "player_white")." ".($games[$_][7] ? "player_won" : "player_lost");
					print "<td class=\"$class\">".$c->rendermember($games[$_][3], $games[$_][4], $games[$_][5])."</td>";
				}
				print "</tr>";
				if ($_ % 2) {
					print "<tr><td colspan=\"5\" class=\"$class\">$clan</td></tr>";
					print "</table>";
				} else {
					# Games, too!
					print "<tr class=\"games\">";
					foreach(0..4) {
						print "<td>(<a href=\"".$c->escapeHTML($games[$_][8])."\">Game</a>)</td>";
					}
					print "</tr>";
				}
			}
		}
	} else {
		print $c->h3("Teams");
		my $info = $c->db_select("SELECT clans.id AS id, clans.name AS name, GROUP_CONCAT(CONCAT(position,',',mb.id,',',mb.name,',',IF(mb.rank IS NULL,'',mb.rank),',',mb.played) ORDER BY brawl.position ASC SEPARATOR ';') FROM clans LEFT OUTER JOIN brawl ON brawl.clan_id = clans.id LEFT OUTER JOIN members mb ON mb.id = brawl.member_id WHERE clanperiod = ? AND got100time IS NOT NULL AND ((position > 0 AND position < 6) OR position IS NULL) GROUP BY clans.id ORDER BY clans.got100time", {}, $periodid);
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
} elsif ($mode eq 'votes') {
	$c->header("Votes");

	if ($c->param("add") && $sess->{adminlevel} >= 2) {
		my $text = $c->param("votetext");
		if (length $text < 20) {
			$c->die_fatal_badinput("Vote text too short");
		}
		$c->db_do("INSERT INTO votes SET started = ?, text = ?", {}, time(), $text);
		print $c->h3("Vote added.");
	}
	if ($c->param("vote") && $sess->{adminlevel} >= 1) {
		my $vote = $c->param("vote");
		my $choice = $c->param("choice") ? 1 : 0;
		my $vid = $c->db_selectone("SELECT id FROM votes WHERE id = ? AND started > ?", {}, $vote, time() - 60*60*24*14);
		if (!$vid) {
			$c->die_fatal_badinput("Can't find that vote!");
		}
		$c->db_do("REPLACE INTO vote_voters SET vote_id = ?, voter_id = ?, choice = ?", {}, $vid, $sess->{userid}, $choice);
		print $c->h3("Vote registered.");
	}

	my $votes = $c->db_select("SELECT id, text, started, SUM(choice)+0 AS yes, COUNT(vote_voters.voter_id)+0 AS total FROM votes LEFT OUTER JOIN vote_voters ON vote_voters.vote_id = votes.id GROUP BY votes.id ORDER BY started");
	my $votes_mine = $c->db_select("SELECT vote_id, choice FROM vote_voters WHERE voter_id = ?", {}, $sess->{userid});
	my %votes_mine;
	$votes_mine{$_->[0]} = $_->[1] foreach(@$votes_mine);

	print $c->p(<<END);
Here, clan leaders can vote on proposed rule changes etc.
END

	print $c->h3("Finished Votes");
	print $c->p(<<END);
These votes can no longer be voted on. They will remain here until bucko deals with their implications.
END

	my $counter = 0;
	while ( my $vote = $votes->[$counter++] ) {
		if ($vote->[2] > time() - 60*60*24*14) {
			$counter--;
			last;
		}
		my $res = "got ".($vote->[3]||"0")." yes votes out of $vote->[4]";
		my $time = strftime("%c", gmtime $vote->[2]);
		print $c->p("<b>The following vote, started on $time, $res</b>: $vote->[1]");
	}

	my $firstactive = $counter;
	if (@$votes == 0 || $counter == 0) {
		print $c->p("There are no finished votes.");
	}

	print $c->h3("Active votes");
	print $c->p(<<END);
These votes can still be voted on by clan leaders. They will last for 2 weeks after they start, then they'll be moved to "finished".
END
	if ($sess->{adminlevel} >= 1) {
		print $c->p(<<END);
If the vote button is italic, you already voted for that option. You can change your vote by clicking the other one. If not, please make your vote.
END
	}
	while ( my $vote = $votes->[$counter++] ) {
		my $time = strftime("%c", gmtime $vote->[2]);
		print $c->p("<b>The following vote was started on $time</b>: $vote->[1]");
		if ($sess->{adminlevel} == 1) {
			my $choice1 = qq|<a href="?mode=votes&amp;vote=$vote->[0]&amp;choice=1">Yes</a>|;
			my $choice2 = qq|<a href="?mode=votes&amp;vote=$vote->[0]&amp;choice=0">No</a>|;
			if (exists $votes_mine{$vote->[0]}) {
				$choice1 = "<i>Yes</i>" if $votes_mine{$vote->[0]} == 1;
				$choice2 = "<i>No</i>" if $votes_mine{$vote->[0]} == 0;
			}
			print $c->p("Vote: $choice1 / $choice2.");
		}
	}
	if (@$votes == 0 || ($counter == $firstactive + 1 && $firstactive == @$votes)) {
		print $c->p("There are no active votes.");
	}

	if ($sess->{adminlevel} >= 2) {
		print $c->h3("Create a new vote.");
		$c->begin_form('post', 'mode', 'votes', 'add', '1');
		print $c->p($c->textarea('votetext', '', 10, 80));
		print $c->submit("OK");
		print $c->end_form;
	}
} elsif ($mode eq 'members') {
	# =========
	# MEMBERS
	# =========
	my $clanid = $c->param('id') || '';
	my $info;
	if ($clanid) {
		$info = $c->db_selectrow("SELECT name, userid, url, looking, tag, regex, email, clanperiod FROM clans WHERE id = ?", {}, $clanid);
		if ($info) {
			if ($info->[7] == $periodid && !$periodspecified) {
				$c->header("Clan info for ".$c->renderclan($clanid, $info->[0]));
			} else {
				$periodid = $info->[7];
				$c->header("Clan info for ".$c->renderclan($clanid, $info->[0]), $periodid);
			}

			# ===================
			# CLAN ALTERATIONS
			# ===================
			my $alter = $c->param("alter");

			# =========
			# TOOLBOX
			# =========
			if ($sess->{adminlevel} >= 1) {
				print $c->h3("Clan Leader's Toolbox");

				$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "renameclan");
				print $c->p("Rename Clan: ", $c->textfield_('name', $info->[0], 30, 50), $c->submit("OK"));
				print $c->end_form;

				$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "changeemail");
				print $c->p("Change email address (not visible to non-admins on this page) to: ", $c->textfield_('email', $info->[6] || "", 30, 50), $c->submit("OK"));
				print $c->end_form;

				$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "clanurl");
				print $c->p("Set web page: ", $c->textfield_('url', $info->[2] || "", 30, 50), $c->submit("OK"));
				print $c->end_form;

				$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "changelooking");
				print $c->p("Advertise for new members fitting this description: ", $c->textfield_('looking', $info->[3] || "", 30, 100), $c->submit("OK"));
				print $c->end_form;

				$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "addmember");
				print $c->p("Add a new member: ", $c->textfield_('newmembername', '', 15, 10), $c->submit("OK"));
				print $c->end_form;

				$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "addalias");
				print $c->p("Add a new KGS username", $c->textfield_('alias', '', 15, 10), "for member", $c->textfield_('membername', '', 15, 10), $c->submit("OK"));
				print $c->end_form;

				$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "renamemember");
				print $c->p("Rename member ", $c->textfield_('membername', '', 30, 30), "to", $c->textfield_('newname', '', 30, 30), $c->submit("OK"));
				print $c->end_form;

				if ($sess->{adminlevel} >= 10) {
					$c->begin_form('get', "mode", "members", "id", $clanid, "alter", "changetag");
					print $c->p("Change tag to ", $c->textfield_('tag', $info->[4], 30, 30), "and regex to", $c->textfield_('regex', $info->[5], 30, 30), $c->submit("OK"));
					print $c->end_form;
				}

				$c->begin_form('post', "mode", "members", "id", $clanid, "alter", "setpass");
				print $c->p("Change password to", $c->textfield_('pass', '', 30, 30), $c->submit("OK"));
				print $c->end_form;

				print $c->p("Hit the \"X\" next to any KGS username below to remove it.");

				print $c->p("If you put a % in the rank, that indicates the position of the member's name, eg \"% the Seamonster\".");

			}
		} else {
			$c->die_fatal_badinput("No such clan ID: $clanid");
		}
		print $c->h3("Clan Brawl Lineup");
		my $brawl = $c->db_select("SELECT position, member_id, members.name, members.rank FROM brawl INNER JOIN members ON members.id = brawl.member_id WHERE brawl.clan_id = ?", {}, $clanid);
		my @brawl = ((undef) x 6);
		@brawl[$_->[0]] = [@{$_}[1,2,3]] foreach(@$brawl);
		print "Clan brawl lineup:<ol>";
		foreach(@brawl[1..5]) {
			if ($_) {
				print "<li>".$c->rendermember(@{$_}[0,1,2]);
				if ($sess->{adminlevel} > 0) {
					print " (<a href=\"?mode=members&amp;id=$clanid&amp;alter=changebrawl&amp;pos=0&amp;memberid=$_->[0]\">X</a>)";
				}
				print "</li>";
			} else {
				print "<li><i>(none)</i></li>";
			}
		}
		print "</ol>";

		print $c->h3("Members");
		print $c->p("<a href=\"update.pl?mode=clan&amp;id=$clanid\">Update all members!</a>") if $sess->{adminlevel} >= 10;
		print $c->p("<a href=\"?mode=games&amp;clan1id=$clanid\">List all clan games.</a>");
		$info = $c->db_select("SELECT members.id AS id, members.name AS name, members.won AS won, members.played AS played, GROUP_CONCAT(CONCAT(aliases.nick,IF(aliases.rank IS NOT NULL,CONCAT(' [',IF(aliases.rank>0,CONCAT(aliases.rank,'k'),CONCAT(1-aliases.rank,'d')),']'),'')) ORDER BY aliases.nick ASC SEPARATOR ', '), members.played_pure AS played_pure, members.won_pure AS won_pure, members.rank AS rank FROM members LEFT OUTER JOIN aliases ON members.id = aliases.member_id INNER JOIN clans ON clans.id = members.clan_id WHERE clan_id = ? GROUP BY members.id ORDER BY members.name", {}, $clanid);
	} else {
		$c->header("List of all clan members");
		print $c->p("<a href=\"?\">Up to clan list.</a>");
		$info = $c->db_select("SELECT clans.name AS clan, clans.id AS clanid, members.id AS id, members.name AS name, members.won AS won, members.played AS played, GROUP_CONCAT(CONCAT(aliases.nick,IF(aliases.rank IS NOT NULL,CONCAT(' [',IF(aliases.rank>0,CONCAT(aliases.rank,'k'),CONCAT(1-aliases.rank,'d')),']'),'')) ORDER BY aliases.nick ASC SEPARATOR ', '), members.played_pure AS played_pure, members.won_pure AS won_pure, members.rank AS rank FROM members LEFT OUTER JOIN aliases ON members.id = aliases.member_id INNER JOIN clans ON clans.id = members.clan_id AND clans.clanperiod = ? GROUP BY members.id ORDER BY members.name", {}, $periodid);
	}

	my $clanstuff = $clanid ? "" : "<th>Clan</th>";
	print "<table class=\"members\"><tr><th>Member</th>";
	print "<th>Rank Editor</th>" if $sess->{adminlevel} != 0;
	print "<th>Played (Pure)</th><th>Won (Pure)</th><th>KGS Usernames</th>$clanstuff</tr>";
	foreach my $member (@$info) {
		if (!$clanid) {
			my $clan = shift @$member;
			my $clanid = shift @$member;
			$clanstuff = "<td>".$c->renderclan($clanid, $clan)."</td>";
		}
		my $aliases = $member->[4] || "(none)";
		my $class = $member->[4] ? "" : " class=\"nonmember\"";
		my $dellink = $member->[3] || $sess->{adminlevel} == 0 ? "" : " (<a href=\"?mode=members&amp;id=$clanid&amp;alter=removemember&amp;memberid=$member->[0]\">X</a>)";
		print "<tr$class><td>";
		my $memberinfo = $c->rendermember(@{$member}[0,1,7]);
		print "$memberinfo$dellink</td>";
		if ($sess->{adminlevel} != 0) {
			print "<td>";
			$c->begin_form('get', 'mode', 'members', 'alter', 'changerank', 'id', $clanid, 'memberid', $member->[0]);
			print $c->textfield_('rank', $member->[7] || '', 10, 30);
			print $c->submit("Go");
			print $c->end_form;
			print "</td>";
		}
		print "<td>$member->[3] ($member->[5])</td><td>$member->[2] ($member->[6])</td>";
		if ($sess->{adminlevel} == 0) {
			print "<td>$aliases</td>";
		} else {
			my @aliases = split /, /, $aliases;
			print "<td>".join(', ', map { my$a=$_;$a=~s/\s+.*//;"$_ (<a href=\"?mode=members&amp;id=$clanid&amp;alter=removealias&amp;memberid=$member->[0]&amp;alias=$a\">X</a>)" } @aliases)."</td>";
		}
		my $leaderlinks = "";
		if ($sess->{adminlevel} != 0 && $clanid) {
			$leaderlinks = " <a href=\"?mode=members&amp;id=$clanid&amp;alter=changeleader&amp;memberid=$member->[0]\">New Leader</a>";
#			$leaderlinks .= " / Set Brawl Pos";
#			$leaderlinks .= " <a href=\"?mode=members&amp;id=$clanid&amp;alter=changebrawl&amp;pos=$_&amp;memberid=$member->[0]\">$_</a>" for(1..5);
		}
		print "<td><a href=\"update.pl?mode=member&amp;id=$member->[0]\">Update!</a>$leaderlinks</td>" if $member->[4];
		print "<td>$leaderlinks</td>" if !$member->[4];
		print "$clanstuff</tr>";
	}
	print "</table>";
} elsif ($mode eq 'games') {
	my $info;
	my $memberid = $c->param('id');
	if ($memberid) {
		$info = $c->db_selectrow("SELECT members.name AS name, members.rank AS rank, clans.name as clan, clans.id as clan_id, clanperiod FROM members INNER JOIN clans ON clans.id = members.clan_id WHERE members.id = ?", {}, $memberid);
		if (@$info) {
			$c->header("Member info for ".$c->rendermember($memberid, @{$info}[0, 1]), $info->[4]);
			print $c->p($c->rendermember($memberid, @{$info}[0, 1])." is in clan ".$c->renderclan(@{$info}[3,2])."</a>");
			print $c->p("<a href=\"update.pl?mode=member&amp;id=$memberid\">Update this member!</a>");
			print $c->p("<a href=\"?mode=allgames&amp;id=$memberid\">Show all games on file for this member.</a>");
			$info = $c->db_select("SELECT url, white, white_id, mw.rank, black, black_id, mb.rank, result, result_by, komi, handicap, time FROM games LEFT OUTER JOIN members mb ON mb.id = black_id LEFT OUTER JOIN members mw ON mw.id = white_id WHERE white_id = ? OR black_id = ? ORDER BY time", {}, $c->param('id'), $memberid);
		} else {
			$c->die_fatal_badinput("No such member ID: $memberid");
		}
	} else {
		my $clan1id = $c->param('clan1id');
		my $clan2id = $c->param('clan2id');
		my $lim = $c->param('lim') ? ' LIMIT 99, 1' : '';
		my ($clan1name, $clanperiod) = $c->db_selectone("SELECT name, clanperiod FROM clans WHERE id = ?", {}, $clan1id);
		if ($clan1name) {
			if ($clan2id) {
				my $clan2name = $c->db_selectone("SELECT name FROM clans WHERE id = ?", {}, $clan2id);
				if ($clan2name) {
					$c->header("Clan games for ".$c->renderclan($clan1id, $clan1name)." vs. ".$c->renderclan($clan2id, $clan2name), $clanperiod);
					$info = $c->db_select("SELECT url, white, white_id, mw.rank, black, black_id, mb.rank, result, result_by, komi, handicap, time FROM games INNER JOIN members mb ON mb.id = black_id INNER JOIN members mw ON mw.id = white_id WHERE (mw.clan_id = ? AND mb.clan_id = ?) OR (mb.clan_id = ? AND mw.clan_id = ?) ORDER BY time$lim", {}, $clan1id, $clan2id, $clan1id, $clan2id);
				} else {
					$info = [];
					$c->die_fatal_badinput("No such clan ID: $clan2id");
				}
			} else {
				$c->header("Clan games for ".$c->renderclan($clan1id, $clan1name), $clanperiod);
				$info = $c->db_select("SELECT url, white, white_id, mw.rank, black, black_id, mb.rank, result, result_by, komi, handicap, time FROM games LEFT OUTER JOIN members mb ON mb.id = black_id LEFT OUTER JOIN members mw ON mw.id = white_id WHERE mw.clan_id = ? OR mb.clan_id = ? ORDER BY time$lim", {}, $clan1id, $clan1id);
			}
		} else {
			$info = [];
			$c->die_fatal_badinput("No such clan ID: $clan1id");
		}
	}
	if (@$info) {
		print "<table class=\"games\"><tr><th>Time (GMT)</th><th>White</th><th>Black</th><th>Komi</th><th>Handicap</th><th>Result</th></tr>";
		foreach my $game (@$info) {
			my $class = $memberid ? (($game->[7] == -1 ? ($game->[2] || 0) == $memberid : ($game->[5] || 0) == $memberid) ? "won" : "lost") : "";
			print "<tr class=\"$class\"><td>";
			print strftime("%Y/%m/%d %H:%M", gmtime $game->[11]);
			print "</td><td>";
			my ($mark, $emark);
			if ($game->[7] == -1) {
				$mark = "<b>";
				$emark = "</b>";
			} else {
				$mark = '';
				$emark = '';
			}
			if ($game->[2]) {
				print $mark.$c->rendermember(@{$game}[2, 1, 3]).$emark;
			} else {
				print "$mark$game->[1]$emark";
			}
			print "</td><td>";
			if ($game->[7] == 1) {
				$mark = "<b>";
				$emark = "</b>";
			} else {
				$mark = '';
				$emark = '';
			}
			if ($game->[5]) {
				print $mark.$c->rendermember(@{$game}[5, 4, 6]).$emark;
			} else {
				print "$mark$game->[4]$emark";
			}
			print "</td><td>$game->[9]</td><td>$game->[10]</td><td><a href=\"$game->[0]\">";
			if ($game->[7] == 0) {
				print "Jigo";
			} elsif ($game->[7] == 1) {
				print "B$game->[8]";
			} else {
				print "W$game->[8]";
			}
			print "</a></td></tr>";
		}
		print "</table>";
	}
} elsif ($mode eq 'allgames') {
	my $memberid = $c->param('id');
	my ($periodid, $periodstart, $periodend) = $c->getperiod;
	my $info = $c->db_selectrow("SELECT members.name AS name, clans.name as clan, clans.id as clan_id FROM members INNER JOIN clans ON clans.id = members.clan_id WHERE members.id = ?", {}, $memberid);
	if (@$info) {
		$c->header("All games for $info->[0]");
		print $c->p("<a href=\"?mode=members&amp;id=$info->[2]\">Up to member list for $info->[1].</a>");
		print $c->p("<a href=\"update.pl?mode=member&amp;id=$memberid\">Update this member!</a>");
		$info = $c->db_select("SELECT url, white, white_id, black, black_id, result, result_by, komi, handicap, games.time, white_decision, black_decision, games.id FROM games LEFT OUTER JOIN aliases AS a1 ON white = a1.nick LEFT OUTER JOIN aliases AS a2 ON black = a2.nick WHERE (a1.member_id = ? OR a2.member_id = ?) AND games.time > ? ORDER BY games.time", {}, $memberid, $memberid, $periodstart);
		print "<table><tr><th>Time (GMT)</th><th>White</th><th>Black</th><th>Komi</th><th>Handicap</th><th>Result</th><th>White Decision</th><th>Black Decision</th><th></th></tr>";
		foreach my $game (@$info) {
			print "<tr><td>";
			print strftime("%Y/%m/%d %H:%M", gmtime $game->[9]);
			print "</td><td>";
			my ($mark, $emark);
			if ($game->[5] == -1) {
				$mark = "<b>";
				$emark = "</b>";
			} else {
				$mark = '';
				$emark = '';
			}
			if ($game->[2]) {
				print "<a href=\"?mode=games&amp;id=$game->[2]\">$mark$game->[1]$emark</a>";
			} else {
				print "$mark$game->[1]$emark";
			}
			print "</td><td>";
			if ($game->[5] == 1) {
				$mark = "<b>";
				$emark = "</b>";
			} else {
				$mark = '';
				$emark = '';
			}
			if ($game->[4]) {
				print "<a href=\"?mode=games&amp;id=$game->[4]\">$mark$game->[3]$emark</a>";
			} else {
				print "$mark$game->[3]$emark";
			}
			print "</td><td>$game->[7]</td><td>$game->[8]</td><td><a href=\"$game->[0]\">";
			if ($game->[5] == 0) {
				print "Jigo";
			} elsif ($game->[5] == 1) {
				print "B$game->[6]";
			} else {
				print "W$game->[6]";
			}
			my $white_decision = defined $game->[10] ? $game->[10] : '?';
			$white_decision =~ s/,/, /g;
			my $black_decision = defined $game->[11] ? $game->[11] : '?';
			$black_decision =~ s/,/, /g;
			print "</a></td><td>$white_decision</td><td>$black_decision</td><td><a href=\"update.pl?mode=game&amp;id=$game->[12]\">Recheck...</td></tr>";
		}
		print "</table>";
	} else {
		$c->die_fatal_badinput("No such member ID: $memberid");
	}
}
