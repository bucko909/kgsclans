#!/usr/bin/perl

use warnings;
use strict;
use Clans;
use Clans::Form;
use Carp qw/cluck/;
$SIG{__WARN__} = sub { cluck $_[0] };

my $c = new Clans;

$c->header;


$c->process_input();

if (!$c->param('form')) {
	my $category = $c->param('category');
	if ($category) {
		if (!$c->param('member_id')) {
			if ($category eq 'member') {
				print "Asked for member admin, but no member given. Dropping to clan admin.";
				$category = 'clan';
			}
		}
		if (!$c->param('team_id')) {
			if ($category eq 'brawl') {
				print "Asked for brawl admin, but no team given. Dropping to clan admin.";
				$category = 'clan';
			}
		}
		if (!$c->param('clan_id')) {
			if ($category eq 'clan') {
				print "Asked for clan admin, but no clan given. Dropping to overall admin.";
				$category = 'admin';
			}
		}
	} else {
		if ($c->param('member_id')) {
			$category = 'member';
		} elsif ($c->param('team_id')) {
			$category = 'brawl';
		} elsif ($c->param('clan_id')) {
			$category = 'clan';
		} else {
			$category = 'admin';
		}
	}
	if ($category eq 'admin') {
		print $c->h2("Overall Admin Page");
	} elsif ($category eq 'clan') {
		print $c->h2("Clan Admin Page for ".$c->render_clan($c->param('clan_id')));
	} elsif ($category eq 'member') {
		print $c->h2("Member Admin Page for ".$c->render_member($c->param('member_id')));
	} elsif ($category eq 'brawl') {
		print $c->h2("Brawl Team Admin Page for ".$c->render_team($c->param('team_id')));
	}

	print "<p>Available actions:</p>";

	print $c->form_list($category);
} else {
	print $c->gen_form($c->param('form'), $c->param($c->param('form').'_category'));
}

$c->footer;
