#!/usr/bin/perl

use strict;
use warnings;
use Clans;
use POSIX qw/strftime/;
use Carp qw/cluck/;
use Text::Textile;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = Clans->new;

$c->header;

if ($c->param('cols') || $c->param('sort')) {
	print $c->h1("Error.");
	print $c->p("Sorry, the table code is disabled due to excessive web spidering causing errors.\n");
	$c->footer;
	exit 0;
}

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
	$page = $c->db_selectrow("SELECT content, revision, phpbb3_users.username, created FROM content INNER JOIN phpbb3_users ON phpbb3_users.user_id = content.creator WHERE period_id = ? AND name = ? AND revision = ?", {}, $c->{period_info}{id}, $pagename, $c->param('revision'));
} else {
	$page = $c->db_selectrow("SELECT content, revision, phpbb3_users.username, created FROM content INNER JOIN phpbb3_users ON phpbb3_users.user_id = content.creator WHERE period_id = ? AND name = ? AND current = 1", {}, $c->{period_info}{id}, $pagename);
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
		print qq| <a href="admin.pl?form=change_page&amp;change_page_page_name=$pagename&amp;change_page_revision=$page->[1]">Edit</a>.|;
	}
	print "</p>";
} else {
	my $lqstring = $qstring;
	$lqstring .= "&amp;period=".$c->param('period') if $c->param('period');
	print qq|<p>This page is was not found. <a href="admin.pl?form=add_page&amp;add_page_name=$pagename">Create it</a>.</p>|;
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
			data => sub { $c->render_clan(@_[0,1]).($_[2] ? " (<a href=\"$_[2]\">web</a>)" : "") },
			totdata => sub { "" },
		},
		ct => { # clan_tag => {
			sqlcols => [qw/clans.id clans.tag/],
			title => "Tag",
			sort => 1,
			data => sub { $c->render_clan(@_[0,1]) },
		},
		ctb => { # clan_tag_bare => {
			sqlcols => [qw/clans.tag/],
			title => "Tag",
			data => sub { $_[0] },
		},
		cr => { # clan_recruiting => {
			sqlcols => [ "SUBSTRING_INDEX(clans.looking,'\n',1)" ],
			title => "Description",
			data => sub { $_[0] || "" },
		},
		cf => { # clan_forum => {
			sqlcols => [qw/clans.forum_id clans.forum_private_id clans.id/],
			title => "Clan Forum",
			init => sub { $persist{cf} = $c->is_clan_member || 0 },
			data => sub { ($_[0] ? "<a href=\"/forum/viewforum.php?f=$_[0]\">Public</a>" : "").($_[1] && $persist{cf} == $_[2] ? " / <a href=\"/forum/viewforum.php?f=$_[1]\">Private</a>" : "") }, # TODO
		},
		cl => { # clan_leader => {
			sqlcols => [qw/members.id members.name members.rank/],
			title => "Leader",
			joins => [ "LEFT OUTER JOIN members ON clans.leader_id = members.id" ],
			sort => 1,
			data => sub { $_[0] ? $c->render_member(@_[0,1,2]) : "" },
		},
		cmf => { # clan_members_full => {
			sqlcols => [qw/COUNT(mact.id) COUNT(mqual.id)/],
			title => "Members (Qualified)",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
				"LEFT OUTER JOIN members mqual ON mqual.clan_id = clans.id AND mqual.played + mqual.played_pure >= 7 AND mqual.id = mact.id AND mqual.active = 1",
			],
			init => sub { $persist{mall} = 0; $persist{mqual} = 0; },
			data => sub { $persist{mall} += $_[0]; $persist{mqual} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { "$persist{mall} ($persist{mqual})" },
		},
		cm => { # clan_members => {
			sqlcols => [qw/COUNT(mact.id)/],
			title => "Members",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
			],
			init => sub { $persist{mall1} = 0 },
			data => sub { $persist{mall1} += $_[0]; $_[0] },
			totdata => sub { $persist{mall1} },
		},
		cma => { # clan_members_active => {
			sqlcols => [qw/COUNT(mqual.id)/],
			title => "Qualified Members",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
				"LEFT OUTER JOIN members mqual ON mqual.clan_id = clans.id AND mqual.played + mqual.played_pure >= 7 AND mqual.id = mact.id AND mqual.active = 1",
			],
			init => sub { $persist{mqual1} = 0 },
			data => sub { $persist{mqual1} += $_[0]; $_[0] },
			totdata => sub { $persist{mqual1} },
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
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			init => sub { $persist{pall} = 0; $persist{ppure} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{pall} += $_[0]; $persist{ppure} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { my $pure = $persist{ppure} / 2; ($persist{pall} - $pure)." ($pure)" },
		},
		cpa => { # clan_played_all => {
			sqlcols => [qw/SUM(mall.played) SUM(mall.played_pure)/], # Pure needed for correction
			title => "Games",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			init => sub { $persist{pall2} = 0; $persist{ppure2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{pall2} += $_[0]; $persist{ppure2} += $_[1]; "$_[0]" },
			totdata => sub { my $pure = $persist{ppure2} / 2; $persist{pall2} - $pure },
		},
		cpp => { # clan_played_pure => {
			sqlcols => [qw/SUM(mall.played_pure)/],
			title => "Pure Games",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			init => sub { $persist{ppure1} = 0; },
			data => sub { $_[0] ||= 0; $persist{ppure1} += $_[0]; "$_[0]" },
			totdata => sub { $persist{ppure1} / 2 },
		},
		cpaf => { # clan_played_average_full => {
			sqlcols => [qw|SUM(mact.played)/COUNT(mact.id) SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Games per Active Member (Pure)",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
			],
			data => sub { $_[0] ||= 0; $_[1] ||= 0; sprintf("%0.2f (%0.2f)", $_[0], $_[1]) },
		},
		cpaa => { # clan_played_average_all => {
			sqlcols => [qw|SUM(mact.played)/COUNT(mact.id) SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Games per Active Member",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
			],
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{ppmall2} += $_[0]; $persist{ppmpure2} += $_[1]; sprintf("%0.2f", $_[0]) },
		},
		cpap => { # clan_played_average_pure => {
			sqlcols => [qw|SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Pure Games per Active Member",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
			],
			data => sub { $_[0] ||= 0; $persist{ppmpure1} += $_[0]; sprintf("%0.2f", $_[0]) },
		},
		cpqaf => { # clan_played_act_average_full => {
			sqlcols => [qw|SUM(mqual.played)/COUNT(mqual.id) SUM(mqual.played_pure)/COUNT(mqual.id)|],
			title => "Games per Qualified Member (Pure)",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
				"LEFT OUTER JOIN members mqual ON mqual.clan_id = clans.id AND mqual.played + mqual.played_pure >= 7 AND mqual.id = mact.id AND mqual.active = 1",
			],
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{ppmall} += $_[0]; $persist{ppmpure} += $_[1]; sprintf("%0.2f (%0.2f)", $_[0], $_[1]) },
		},
		cpqaa => { # clan_played_act_average_all => {
			sqlcols => [qw|SUM(mqual.played)/COUNT(mqual.id) SUM(mqual.played_pure)/COUNT(mqual.id)|],
			title => "Games per Qualified Member",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
				" LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1 AND mact.id = mall.id",
				"LEFT OUTER JOIN members mqual ON mqual.clan_id = clans.id AND mqual.played + mqual.played_pure >= 7 AND mqual.id = mact.id AND mqual.active = 1",
			],
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{ppmall2} += $_[0]; $persist{ppmpure2} += $_[1]; sprintf("%0.2f", $_[0]) },
		},
		cpqap => { # clan_played_act_average_pure => {
			sqlcols => [qw|SUM(mact.played_pure)/COUNT(mact.id)|],
			title => "Pure Games per Qualified Member",
			joins => [ " LEFT OUTER JOIN members mact ON mact.clan_id = clans.id AND mact.active = 1", "LEFT OUTER JOIN members mqual ON mqual.clan_id = clans.id AND mqual.played + mqual.played_pure >= 7 AND mqual.id = mact.id AND mqual.active = 1" ],
			data => sub { $_[0] ||= 0; $persist{ppmpure1} += $_[0]; sprintf("%0.2f", $_[0]) },
		},
		cwf => { # clan_won_full => {
			sqlcols => [qw/SUM(mall.won) SUM(mall.won_pure)/],
			title => "Games Won (Pure)",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			init => sub { $persist{wall} = 0; $persist{wpure} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{wall} += $_[0]; $persist{wpure} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { $persist{wall} - $persist{wpure} },
		},
		cwa => { # clan_won_all => {
			sqlcols => [qw/SUM(mall.won) SUM(mall.won_pure)/],
			title => "Games Won",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			init => sub { $persist{wall2} = 0; $persist{wpure2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{wall2} += $_[0]; $persist{wpure2} += $_[1]; "$_[0]" },
			totdata => sub { $persist{wall2} - $persist{wpure} },
		},
		cwp => { # clan_won_pure => {
			sqlcols => [qw/SUM(mall.won_pure)/],
			title => "Pure Games Won",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			init => sub { $persist{wpure1} = 0; },
			data => sub { $_[0] ||= 0; $persist{wpure1} += $_[0]; "$_[0]" },
			totdata => sub { "" },
		},
		cwpf => { # clan_win_percentage_full
			sqlcols => [qw#SUM(mall.won) SUM(mall.played) SUM(mall.won_pure) SUM(mall.played_pure) SUM(mall.won)/SUM(mall.played)#],
			title => "Games Won (Pure)",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			sort => 4,
			#sort => sub { ($b->[$_[1]] ? ($a->[$_[1]] ? $b->[$_[0]] / $b->[$_[1]] <=> $a->[$_[0]] / $a->[$_[1]] : -1) : 1) },
			init => sub { $persist{wpall} = 0; $persist{wppure} = 0; $persist{ppall} = 0; $persist{pppure} = 0; },
			data => sub { $persist{wpall2} += $_[0]; $persist{wppure2} += $_[2]; $persist{ppall2} += $_[1]; $persist{pppure2} += $_[3]; sprintf("%0.2d%% (%0.2d%%)", $_[1] ? $_[0] * 100 / $_[1] : 0, $_[3] ? $_[2] * 100 / $_[3] : 0) },
			totdata => sub { sprintf("%0.2d%%", ($persist{wpall} - $persist{ppall}) / ($persist{wppure} - $persist{pppure})) },
		},
		cwpa => { # clan_win_percentage_all
			sqlcols => [qw#SUM(mall.won) SUM(mall.played) SUM(mall.won_pure) SUM(mall.played_pure) SUM(mall.won)/SUM(mall.played)#],
			title => "Games Won",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			sort => 4,
			#sort => sub { ($b->[$_[1]] ? ($a->[$_[1]] ? $b->[$_[0]] / $b->[$_[1]] <=> $a->[$_[0]] / $a->[$_[1]] : -1) : 1) },
			init => sub { $persist{wpall2} = 0; $persist{wppure2} = 0; $persist{ppall2} = 0; $persist{pppure2} = 0; },
			data => sub { $persist{wpall2} += $_[0]; $persist{wppure2} += $_[2]; $persist{ppall2} += $_[1]; $persist{pppure2} += $_[3]; sprintf("%0.2d%%", $_[1] ? $_[0] * 100 / $_[1] : 0) },
			totdata => sub { sprintf("%0.2d%%", ($persist{wpall2} - $persist{ppall2}) / ($persist{wppure2} - $persist{pppure2})) },
		},
		cwpp => { # clan_win_percentage_pure
			sqlcols => [qw#SUM(mall.won_pure) SUM(mall.played_pure) SUM(mall.won_pure)/SUM(mall.played_pure)#],
			title => "Pure Games Won",
			joins => [
				"  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			],
			sort => 2,
			#sort => sub { ($b->[$_[1]] ? ($a->[$_[1]] ? $b->[$_[0]] / $b->[$_[1]] <=> $a->[$_[0]] / $a->[$_[1]] : -1) : 1) },
			data => sub { sprintf("%0.2d%%", $_[1] ? $_[0] * 100 / $_[1] : 0) },
		},
		ma => {
			sqlcols => [qw/members.id members.name members.rank/],
			title => "Name",
			sort => 1,
			data => sub { $_[0] ? $c->render_member(@_[0,1,2]) : "" },
		},
		mn => {
			sqlcols => [qw/members.id members.name/],
			title => "Name",
			sort => 1,
			data => sub { $_[0] ? $c->render_member(@_[0,1], "") : "" },
		},
		mu => {
			sqlcols => [qw/members.id/],
			title => "Updates",
			data => sub { qq#<a href="update.pl?mode=member&amp;id=$_[0]">Update!</a># },
		},
#		mm => {
#			sqlcols => [qw/members.id clans.id/],
#			title => "Miscelleneous",
#			data => sub { qq#<a href="?page=clanadmin&amp;alter=set_clan_leader&amp;clanid=$_[1]&amp;memberid=$_[0]">New Leader</a># },
#		},
		mk => {
			sqlcols => ["GROUP_CONCAT(CONCAT(kgs_usernames.nick,IF(kgs_usernames.rank IS NOT NULL,CONCAT(' [',IF(kgs_usernames.rank>0,CONCAT(kgs_usernames.rank,'k'),CONCAT(1-kgs_usernames.rank,'d')),']'),'')) ORDER BY kgs_usernames.nick ASC SEPARATOR ', ')"],
			joins => [ 'LEFT OUTER JOIN kgs_usernames ON members.id = kgs_usernames.member_id' ],
			title => "KGS Usernames",
			data => sub { $_[0] || "" },
		},
#		mke => {
#			sqlcols => ["GROUP_CONCAT(CONCAT(kgs_usernames.nick,IF(kgs_usernames.rank IS NOT NULL,CONCAT(' [',IF(kgs_usernames.rank>0,CONCAT(kgs_usernames.rank,'k'),CONCAT(1-kgs_usernames.rank,'d')),']'),'')) ORDER BY kgs_usernames.nick ASC SEPARATOR ', ')", qw/members.id clans.id/],
#			joins => [ 'LEFT OUTER JOIN kgs_usernames ON members.id = kgs_usernames.member_id' ],
#			title => "KGS Usernames",
#			data => sub { join(', ', map { my$a=$_;$a=~s/\s+.*//;"$_ (<a href=\"?page=clanadmin&amp;clanid=$_[2]&amp;alter=remove_member_alias&amp;memberid=$_[1]&amp;alias=$a\">X</a>)" } split /, /, $_[0]) },
#		},
#		mne => {
#			sqlcols => [qw/members.id members.name clans.id COUNT(kgs_usernames.id)/],
#			joins => [ 'LEFT OUTER JOIN kgs_usernames ON members.id = kgs_usernames.member_id' ],
#			title => "Name",
#			init => sub {},
#			sort => 1,
#			data => sub { qq#<form method="post" action="?"><input type="hidden" name="page" value="clanadmin"/><input type="hidden" name="clan" value="$_[2]"/><input type="hidden" name="alter" value="set_member_name"/><input type="hidden" name="memberid" value="$_[0]"/><input type="text" name="name" value="$_[1]"/><input type="submit" value="OK"/></form>#.($_[3] == 0 ? " (<a href=\"?page=clanadmin&amp;clanid=$_[2]&amp;alter=remove_clan_member&amp;memberid=$_[0]\">X</a>)" : "") },
#			totdata => sub { "" },
#		},
#		mre => {
#			sqlcols => [qw/members.id members.rank clans.id/],
#			title => "Rank",
#			init => sub {},
#			sort => 1,
#			data => sub { my $r = $_[1] || ""; qq#<form method="post" action="?"><input type="hidden" name="page" value="clanadmin"/><input type="hidden" name="clan" value="$_[2]"/><input type="hidden" name="alter" value="set_member_rank"/><input type="hidden" name="memberid" value="$_[0]"/><input type="text" name="rank" value="$r"/><input type="submit" value="OK"/></form># },
#			totdata => sub { "" },
#		},
		mpf => { # member_played_full
			sqlcols => [qw/members.played members.played_pure/],
			title => "Games (Pure)",
			init => sub { $persist{mpf} = 0; $persist{mpf_2} = 0; },
			data => sub { $_[0] ||= 0; $_[1] ||= 0; $persist{mpf} += $_[0]; $persist{mpf_2} += $_[1]; "$_[0] ($_[1])" },
			totdata => sub { "$persist{mpf} ($persist{mpf_2})" },
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
			totdata => sub { "$persist{mwf} ($persist{mwf_2})" },
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
			data => sub { ($_[4] =~ /\?rengo2$/ ? "Partner + " : "").($_[3] == -1 ? "<b>" : "").($_[0] ? $c->render_member($_[0], $_[1], $_[2]) : $_[1]).($_[3] == -1 ? "</b>" : "").($_[4] =~ /\?rengo1$/ ? " + partner" : "") },
			class => sub { ($_[3] == -1 ? "ahead" : ($_[3] ? "behind" : "")) },
		},
		wc => {
			sqlcols => [qw#cw.id cw.name games.result#],
			joins => [ "LEFT OUTER JOIN clans cw ON cw.id = mw.clan_id" ],
			title => "White Clan",
			sort => 1,
			data => sub { $_[0] ? $c->render_clan($_[0], $_[1]) : ""},
			class => sub { ($_[2] == -1 ? "ahead" : ($_[2] ? "behind" : "")) },
		},
		b => {
			sqlcols => [qw#mb.id games.black mb.rank games.result games.url#],
			joins => [ " LEFT OUTER JOIN members mb ON black_id = mb.id" ],
			title => "Black",
			sort => 1,
			data => sub { ($_[4] =~ /\?rengo2$/ ? "Partner + " : "").($_[3] == -1 ? "<b>" : "").($_[0] ? $c->render_member($_[0], $_[1], $_[2]) : $_[1]).($_[3] == -1 ? "</b>" : "").($_[4] =~ /\?rengo1$/ ? " + partner" : "") },
			class => sub { ($_[3] == 1 ? "ahead" : ($_[3] ? "behind" : "")) },
		},
		bc => {
			sqlcols => [qw#mb.id cb.name games.result#],
			joins => [ "LEFT OUTER JOIN clans cb ON cb.id = mb.clan_id" ],
			title => "Black Clan",
			sort => 1,
			data => sub { $_[0] ? $c->render_clan($_[0], $_[1]) : ""},
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
			sqlcols => [qw/clans.got100time/],
			joins => [ "  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			           "LEFT OUTER JOIN members ON clans.leader_id = members.id" ], # Ensure this happens
			init => sub { },
			class => sub { $_[0] ? " class=\"qualified\"" : "" },
		}
	);
	my @cols = split /,/, ($c->param('ctcols') || $cols || 'cn,ct,cl,cmf,cpf,cwf,cpaf,cr');
	&main_drawtable($c, \%period_clans_table, \@cols, $c->param('sort') || $sort, "clans", "period_id = ".$c->{period_info}{id}." AND clans.points > -50");
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
	&main_drawtable($c, \%period_topplayers_table, \@cols, "FIX:".$sort, "members", "clans.period_id = ".$c->{period_info}{id}." AND members.played >= 10", "LIMIT 10");
}

sub membertable {
	my ($c, $clan, $cols, $sort) = @_;
	my $clause;
	my $defcols;
	if ($clan && $clan eq 'all') {
		$defcols = 'ma,mpf,mwf,mk,cn';
		$clause = "clans.period_id = ".$c->{period_info}{id};
	} else {
		$defcols = 'ma,mpf,mwf,mk';
		if (!$clan || $clan =~ /[^0-9]/) {
			if ($c->{clan_info}) {
				$clause = "members.clan_id = ".$c->{clan_info}{id};
			} elsif ($clan) {
				return "\"$clan\" is not a valid clan ID.";
			} else {
				return "No clan specified.";
			}
		} else {
			$clause = "members.clan_id = ".$clan;
		}
	}
	my %persist;
	my $reqpoints = $c->get_option('BRAWLMEMBERPOINTS');
	my %clan_members_table = (
		%TABLEROWS,
		ROWINIT => {
			sqlcols => [ qw/members.played members.played_pure/ ],
			joins => [ "  INNER JOIN clans ON clans.id = members.clan_id" ], # Ensure this happens
			init => sub { },
			class => sub { $_[0] + $_[1] >= $reqpoints ? " class=\"qualified\"" : "" },
		},
	);
	my @cols = split /,/, ($c->param('cols') || $cols || $defcols);
	&main_drawtable($c, \%clan_members_table, \@cols, $c->param('sort') || $sort || 'ma', "members", $clause);
}

sub member_gametable {
	my ($c, $memberid, $cols, $sort) = @_;
	my $clause;
	if (!$memberid || $memberid !~ /^\d+(?:\.\d+)?$/) {
		if ($c->{member_info}) {
			$memberid = $c->{member_info}{id};
		} elsif ($memberid) {
			return "\"$memberid\" is not a valid member ID.";
		} else {
			return "No member specified";
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
	if (!$info) {
		print STDERR "SELECT $selcols FROM $maintable $joins WHERE $where GROUP BY $maintable.id $sqlsort $extra;\n";
	}

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

sub clan_teamlist {
	my ($c, $clanid) = @_;
	if (!$clanid || $clanid =~ /[^0-9]/) {
		if ($c->{clan_info}) {
			$clanid = $c->{clan_info}{id};
		} else {
			$clanid = "" if !defined $clanid;
			return "Clan ID \"$clanid\" is invalid";
		}
	}
	my $mod_of = $c->is_clan_moderator;
	my $teams = $c->db_select("SELECT teams.id, name, team_number, COUNT(member_id), teams.in_brawl FROM teams LEFT OUTER JOIN team_seats ON teams.id = team_seats.team_id AND seat_no >= 0 AND seat_no <= 4 WHERE clan_id = ? GROUP BY teams.id ORDER BY team_number", {}, $clanid);
	my $out = '<h3>Teams</h3>';
	if ($mod_of && $mod_of != $clanid && @$teams) {
		$out .= qq|<p><a href="admin.pl?form=add_challenge&amp;add_challenge_category=clan&amp;add_challenge_cclan_id=$clanid">Challenge this clan to a match</a>.</p>|;
	}
	if ($c->is_admin || ($mod_of && $mod_of == $clanid)) {
		my $challenges = $c->db_select("SELECT challenges.id, teams.name, clans.id, clans.name FROM challenges INNER JOIN teams ON teams.id = challenger_team_id INNER JOIN clans ON clans.id = teams.clan_id WHERE challenged_clan_id = ?", {}, $clanid);
		if (@$challenges) {
			$out .= "<p>Unanswered challenges:</p><ul>";
			$out .= qq|<li>From |.$c->escapeHTML($_->[1]).' ('.$c->render_clan($_->[2], $_->[3]).qq|): <a href="admin.pl?form=accept_challenge&amp;accept_challenge_category=clan&amp;accept_challenge_challenge_id=$_->[0]&amp;accept_challenge_changed=challenge_id">Accept</a> or <a href="admin.pl?form=decline_challenge&amp;decline_challenge_category=clan&amp;decline_challenge_challenge_id=$_->[0]&amp;decline_challenge_changed=challenge_id">decline</a>.</li>| for(@$challenges);
			$out .= "</ul>";
		}
	}
	if (@$teams) {
		my $count = 1;
		for(@$teams) {
			$out .= "<h4>Team $count: ";
			$count++;
			$out .= $_->[1] ? $_->[1] : "Main";
			if ($_->[3] != 5) {
				$out .= " (some seats unallocated)";
			} elsif (!$_->[4]) {
				$out .= " (team not marked as ready)";
			} else {
				$out .= " (ready for matches)";
			}
			$out .= "</h4>";
			if ($c->is_clan_member($clanid)) {
				$out .= clan_team_memberlist($c, $_->[0]);
			} else {
				$out .= clan_team_public_memberlist($c, $_->[0]);
			}
		}
	} else {
		$out .= "<p>No teams created!</p>";
	}
	return $out;
}

sub clan_team_memberlist {
	my ($c, $teamid) = @_;
	if (!$teamid) {
		return "Team ID \"$teamid\" is invalid";
	}
	my $results = $c->db_select("SELECT team_seats.seat_no, members.id, members.name, members.rank FROM team_seats INNER JOIN members ON members.id = team_seats.member_id WHERE team_seats.team_id = ? ORDER BY team_seats.seat_no", {}, $teamid);
	my $result = '';
	if (!$results || !@$results) {
		$result .= "<p>Team has no roster.</p>";
	} else {
		$result .= "<p>Current roster:</p>";
		$result .= "<ul>";
		for(@$results) {
			$result .= "<li>".($_->[0]+1).": ".$c->render_member($_->[1], $_->[2], $_->[3])."</li>";
		}
		$result .= "</ul>";
	}
	$results = $c->db_select("SELECT members.id, members.name, members.rank FROM team_members LEFT OUTER JOIN team_seats ON team_seats.team_id = team_members.team_id AND team_seats.member_id = team_members.member_id INNER JOIN members ON members.id = team_members.member_id WHERE team_members.team_id = ? AND team_seats.seat_no IS NULL ORDER BY members.name", {}, $teamid);
	if (!$results || !@$results) {
		$result .= "<p>Team has no reserves.</p>";
	} else {
		$result .= "<p>Reserves:</p>";
		$result .= "<ul>";
		for(@$results) {
			$result .= "<li>".$c->render_member($_->[0], $_->[1], $_->[2])."</li>";
		}
		$result .= "</ul>";
	}
	return $result;
}

sub clan_team_public_memberlist {
	my ($c, $teamid) = @_;
	if (!$teamid) {
		return "Team ID \"$teamid\" is invalid";
	}
	my $results = $c->db_select("SELECT members.id, members.name, members.rank FROM team_members INNER JOIN members ON members.id = team_members.member_id WHERE team_members.team_id = ? ORDER BY members.name", {}, $teamid);
	return "Team has no members." if !$results || !@$results;
	my $result = "<ul>";
	for(@$results) {
		$result .= "<li>".$c->render_member($_->[0], $_->[1], $_->[2])."</li>";
	}
	$result .= "</ul>";
	return $result;
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
	return 'No clan' unless $c->{clan_info};
	"<ul>".
		(join '', map{
			qq|<li><a href="/forum/profile.php?mode=viewprofile&amp;u=$_->[0]">$_->[1]</a></li>|
		}
		@{$c->db_select("SELECT phpbb3_users.user_id, phpbb3_users.username FROM phpbb3_users INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_group_id WHERE clans.id = ? ORDER BY username", {}, $c->{clan_info}{id})})
	."</ul>";
}

sub clan_forummoderators {
	my ($c, $name, @params) = @_;
	return 'No clan' unless $c->{clan_info};
	"<ul>".
		(join '', map{
			qq|<li><a href="/forum/profile.php?mode=viewprofile&amp;u=$_->[0]">$_->[1]</a></li>|
		}
		@{$c->db_select("SELECT phpbb3_users.user_id, phpbb3_users.username FROM phpbb3_users INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN clans ON phpbb3_user_group.group_id = clans.forum_leader_group_id WHERE clans.id = ? ORDER BY username", {}, $c->{clan_info}{id})})
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
		TEAMS => sub { &clan_teamlist(@_) },
		LOCALPAGE => sub {
			my ($c, $name, $text) = @_;
			my $url = $c->baseurl('page','alter')."page=$name";
			qq|<a href="$url">$text</a>|;
		},
		PERIODINFO => sub {
			my $c = $_[0];
			my $period_info = $c->period_info();
			my $next_period_info = $c->period_info($period_info->{id} + 1);
			my $prev_period_info = $c->period_info($period_info->{id} - 1);
			my $text = "This is period $period_info->{id}; it started at ".strftime("%c", gmtime($period_info->{startdate}))." and will end at ".strftime("%c", gmtime($period_info->{enddate})).". Go to ";
			if ($next_period_info) {
				$text .= qq|<a href="index.pl?$qstring&amp;period=|.($next_period_info->{id}).qq|">next</a>|;
				$text .= " or " if $prev_period_info;
			}
			if ($prev_period_info) {
				$text .= qq|<a href="index.pl?$qstring&amp;period=|.($prev_period_info->{id}).qq|">previous</a>|;
			}
			$text .= " clan period."
		},
		ADMINLIST => sub {
			my $c = $_[0];
			my $admins = $c->db_select("SELECT username FROM phpbb3_users INNER JOIN phpbb3_user_group ON phpbb3_users.user_id = phpbb3_user_group.user_id INNER JOIN phpbb3_groups ON phpbb3_groups.group_id = phpbb3_user_group.group_id WHERE group_name = ?", {}, "ADMINISTRATORS");
			return '<ul>'.(join '', map { "<li>$_->[0]</li>" } @$admins).'</ul>';
		},
		USERNAME => sub {
			my $c = $_[0];
			return ($c->{phpbbsess} ? "$c->{phpbbsess}{summary}" : "anonymous (no session)");
		},
		CHAMPION => sub {
			my $champ = $c->get_option('BRAWLCHAMPION');
			if ($champ) {
				return $_[0]->render_clan($champ);
			} else {
				return "unknown";
			}
		},
		CLAN => sub {
			if ($_[0]->{clan_info}) {
				return $_[0]->render_clan($_[0]->{clan_info}{id});
			} else {
				return "?";
			}
		},
		CLANINFO => sub {
			if ($_[0]->{clan_info}) {
				my $inf = $_[0]->db_selectone("SELECT looking FROM clans WHERE id = ?", {}, $_[0]->{clan_info}{id}) || '';
				$inf =~ s/^.*?\n//;
				my $textile = Text::Textile->new();
				$inf = $textile->process($inf);
				return $inf;
			} else {
				return "?";
			}
		},
		CLANS => sub {
			my $clans = $c->param("clans");
			if ($clans && $clans =~ /^(\d+).(\d+)$/) {
				return $_[0]->render_clan($1)." and ".$_[0]->render_clan($2);
			} else {
				return "? and ?";
			}
		},
		MEMBER => sub {
			if ($_[0]->{member_info}) {
				return $_[0]->render_member($_[0]->{member_info}{id});
			} else {
				return "?";
			}
		},
		CLANID => sub {
			if ($_[0]->{clan_info}) {
				return $_[0]->{clan_info}{id};
			} else {
				return "?";
			}
		},
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
			$content = "<tr><th>".$c->render_clan(@{$row}[0,1])."</th>";
			$header = "<tr><th></th>" if $firstrow;
			$cclan = $row->[0];
		}
		$header .= "<th>".$c->render_clan(@{$row}[2,3])."</th>" if $firstrow;
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
