#!/usr/bin/perl

use Clans;
use Clans::Form;

my $c = new Clans;

$c->header;


$c->process_input();

if (!$c->param('form')) {
	my $category = 'admin';
	if ($c->param('category')) {
		$category = $c->param('category');
	} elsif ($c->param('clan_id')) {
		$category = 'clan';
	} elsif ($c->param('member_id')) {
		$category = 'member';
	} elsif ($c->param('team_id')) {
		$category = 'brawl';
	}
	print $c->h2("Available Forms");
	print $c->form_list($category);
} else {
	print $c->gen_form($c->param('form'), $c->param($c->param('form').'_category'));
}

$c->footer;
