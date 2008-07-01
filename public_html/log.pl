#!/usr/bin/perl

use warnings;
use strict;
use Clans;
use Clans::Log;
use Carp qw/cluck/;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = new Clans;

$c->header;

exit unless $c->is_admin;

my $category;
if ($c->{member_info}) {
	$category = 'member';
} elsif ($c->{team_info}) {
	$category = 'team';
} elsif ($c->{clan_info}) {
	$category = 'clan';
} else {
	$category = 'period';
}

my $log_lines;
if ($category eq 'member') {
	$log_lines = $c->get_log_lines_member($c->{member_info}->{id});
} elsif ($category eq 'team') {
	$log_lines = $c->get_log_lines_team($c->{team_info}->{id});
} elsif ($category eq 'clan') {
	$log_lines = $c->get_log_lines_clan($c->{clan_info}->{id});
} elsif ($category eq 'period') {
	$log_lines = $c->get_log_lines_period($c->{period_info}->{id});
}

print $c->format_log_lines_debug($log_lines);

$c->footer;
