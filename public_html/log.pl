#!/usr/bin/perl

use warnings;
use strict;
use Clans;
use Clans::Log;
use Carp qw/cluck/;
use POSIX qw/strftime/;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = new Clans;

$c->header;

my $start = $c->param('start');
$start = 0 if (!$start || $start =~ /[^0-9]/);
my $count = $c->param('count');
$count = 200 if (!$count || $count =~ /[^0-9]/);

my $show_failures = $c->param('show_fail');

my $category;
my $private;
my $cols;
my $log_lines;
if (my $id = $c->param('log_id')) {
	my $log_line = $c->get_log_line($id);
	if (!$log_line) {
		print $c->h2("Log line $id not found");
		$c->footer;
		exit;
	}
	$private = $log_line->[7]{clan_id} ? $c->is_clan_member($log_line->[7]{clan_id}) || $c->is_admin : 1;
	if (!$private) {
		print $c->h2("Log line $id");
		print $c->p("Entry has private info, so only summary is given here. You may have better luck logging into the forum as a member of the clan if you are one.");
		print $c->format_log_lines([$log_line], [qw/status period clan team member/], 0);
	} else {
		print $c->h2("Log line $id");
		print $c->p("All parameters:");
		print "<table>";
		print "<tr><th>Forum User</th><td>$log_line->[5]</td></tr>";
		print "<tr><th>Time</th><td>".strftime("%c", localtime $log_line->[6])."</td></tr>";
		print "<tr><th>Status</th><td>".($log_line->[2] ? "Success" : "Failure")."</td></tr>";
		print "<tr><th>Message</th><td>".($log_line->[3] || "")."</td></tr>";
		for(sort keys %{$log_line->[7]}) {
			print "<tr><th>$_</th><td>$log_line->[7]{$_}</td></tr>";
		}
		print "</table>";
	}
	$c->footer;
	exit;
} elsif ($c->{member_info}) {
	$log_lines = $c->get_log_lines_member($c->{member_info}->{id}, $start, $count+1, $show_failures);
	$private = $c->is_clan_member($c->{clan_info}{id});
	$cols = [qw/team/];
	print $c->h2("Log for ".$c->render_member($c->{member_info}));
} elsif ($c->{team_info}) {
	$log_lines = $c->get_log_lines_team($c->{team_info}->{id}, $start, $count+1, $show_failures);
	$private = $c->is_clan_member($c->{clan_info}{id});
	$cols = [qw/member/];
	print $c->h2("Log for ".$c->render_team($c->{team_info}));
} elsif ($c->{clan_info}) {
	$log_lines = $c->get_log_lines_clan($c->{clan_info}->{id}, $start, $count+1, $show_failures);
	$category = 'clan';
	$private = $c->is_clan_member($c->{clan_info}{id});
	$cols = [qw/team member/];
	print $c->h2("Log for ".$c->render_clan($c->{clan_info}));
} else {
	$log_lines = $c->get_log_lines_period($c->{period_info}->{id}, $start, $count+1, $show_failures);
	$category = 'period';
	$private = 0;
	$cols = [qw/clan team member/];
	print $c->h2("Log for period ".$c->{period_info}{id});
}

if ($show_failures) {
	print qq|<p><a href="log.pl?$c->{context_params}&amp;start=$start&amp;show_fail=0">Hide failures</a></p>|;
	unshift @$cols, "status";
} else {
	print qq|<p><a href="log.pl?$c->{context_params}&amp;start=$start&amp;show_fail=1">Show failures</a></p>|;
}

if ($start > 0) {
	$start = $count if $start < $count;
	print "<p>";
	print qq|<a href="log.pl?$c->{context_params}&amp;start=|.($start-$count).qq|">Newer</a>|;
	if (@$log_lines <= $count) {
		print "</p>";
	}
}
if (@$log_lines > $count) {
	if ($start > 0) {
		print " | ";
	} else {
		print "<p>";
	}
	print qq|<a href="log.pl?$c->{context_params}&amp;start=|.($start+$count).qq|">Older</a>|;
	print "</p>";
}

if (@$log_lines) {
	print $c->format_log_lines($log_lines, $cols, $private);
} else {
	print "Sorry, there are no logged lines!";
}

$c->footer;
