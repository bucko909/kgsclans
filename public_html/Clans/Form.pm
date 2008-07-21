package Clans;

sub process_input {
	&Clans::Form::process_input(@_);
}

sub form_list {
	&Clans::Form::form_list(@_);
}

sub gen_form {
	&Clans::Form::gen_form(@_);
}

package Clans::Form;
use Clans;
use Clans::Form::Types;
use Clans::Form::Forms;
use strict;
use warnings;
our (%forms, %categories, %input_tests);

our $access_cache;
our $infer_cache;
our $check_cache;
sub process_input {
	my ($c) = @_;
	my @formnames = $c->param('process');
	for(@formnames) {
		&process_form($c, $_) if $_;
	}
}

sub process_form {
	my ($c, $name) = @_;

	if (!$forms{$name}) {
		$c->die_fatal_badinput("Invalid form /$name/");
	}

	# Standard stuff to read out the form's contents.
	my ($input_params, $input_params_info) = &parse_form_def($c, $name);
	if (!$input_params_info) {
		$c->die_fatal("Error in parse_form_def processing the $forms{$name}{brief} form ($input_params)");
	}
	my %reasons;
	my $ret = &fill_values($c, $name, $input_params, $input_params_info, \%reasons);
	if ($ret) {
		$c->die_fatal("Error in fill_values processing the $forms{$name}{brief} form ($ret)");
	}
	my %params;
	$params{$_} = $input_params_info->{$_}->{value} foreach (keys %$input_params_info);
	my $category = $c->escapeHTML($c->param($name.'_category') || 'admin');
	if (%reasons) {
		$c->log($name, 0, "Bad input.", \%params);
		print &output_form($c, $name, $category, $input_params, $input_params_info, \%reasons);
		$c->footer;
		exit 0;
	}
	if (my $reason = &no_access($c, $name, $input_params, $input_params_info)) {
		$c->log($name, 0, "Permission denied.", \%params);
		$c->die_fatal_permissions("Sorry, you do not have permission to access the $forms{$name}{brief} form ($reason)");
	}
	if (my $action = $forms{$name}{action}) {
		my ($success, $reason, $override, $override_reason) = $action->($c, \%params);
		$c->log($name, $success, $reason, \%params);
		if ($success) {
			print qq|<h3>|.$c->escapeHTML($forms{$name}{brief}).qq|</h3>|;
			print $c->p("Success: $reason");
		} else {
			if ($override && $c->is_admin) {
				$input_params_info->{$override}{value} = 0;
				$reasons{$override} = $override_reason;
				print &output_form($c, $name, $category, $input_params, $input_params_info, \%reasons, $reason);
				$c->footer;
				exit 0;
			} else {
				print qq|<h3>|.$c->escapeHTML($forms{$name}{brief}).qq|</h3>|;
				print $c->p("Failure: $reason");
			}
		}
		if ($params{member_id}) {
			print $c->p(qq|To member <a href="admin.pl?member_id=$params{member_id}">admin</a> or <a href="index.pl?page=games&amp;member=$params{member_id}">game list</a>.|);
		}
		if ($params{team_id}) {
			print $c->p(qq|To <a href="admin.pl?team_id=$params{team_id}">team admin</a>.|);
		}
		if ($params{clan_id}) {
			print $c->p(qq|To clan <a href="admin.pl?clan_id=$params{clan_id}">admin</a> or <a href="index.pl?page=clan&amp;clan=$params{clan_id}">member list</a>.|);
		}
		if ($c->is_admin) {
			print $c->p(qq|To <a href="admin.pl">overall admin</a>.|);
		}
		print $c->p(qq|To <a href="index.pl">summary</a>.|);
		print qq|<form name="$name" method="post">|;
		print qq|<input type="hidden" name="form" value="$name"/>|;
		print qq|<input type="hidden" name="$name\_category" value="$category"/>|;
		for my $param_name (keys %$input_params_info) {
			next if is('informational', $input_params_info->{$param_name}, $category);
			my $value = $input_params_info->{$param_name}{value};
			print qq|<input type="hidden" name="$name\_$param_name" value="|.$c->escapeHTML($value).qq|"/>| if $value;
		}
		print qq|</form><p>Or you can <a href="javascript:document.$name.submit()">do this form again</a>.</p>|;
		$c->footer;
		exit 0;
	} else {
		$c->die_fatal("Submitted form $name had no action.");
	}
}

sub no_access {
	my ($c, $name, $params, $params_info) = @_;
	my @checks = split /\|/, $forms{$name}{checks};
	for my $level_orig (@checks) {
		if ($access_cache && exists $access_cache->{$level_orig}) {
			return $access_cache->{$level_orig} if $access_cache->{$level_orig};
			next;
		}
		my $level = $level_orig;
		$level =~ s/\$(\w+)/my $val = $params_info->{$1}{value}; defined $val ? $val : ""/eg;
		my $message;
		if ($level eq 'admin' || $level =~ /clan_(leader|moderator)\(\)/) {
			if (!$c->is_admin()) {
				$message = "You are not an admin";
			}
		} elsif ($level =~ /clan_leader\((\d+)\)/) {
			if (!$c->is_clan_leader($1)) {
				$message = "You are not a clan leader";
			}
		} elsif ($level =~ /clan_moderator\((\d+)\)/) {
			if (!$c->is_clan_moderator($1)) {
				$message = "You are not a clan moderator";
			}
		} elsif ($level =~ /period_active\((\d+)\)/) {
			my $current_period = $c->db_selectone("SELECT id FROM clanperiods ORDER BY id DESC LIMIT 1");
			if ($current_period != $1 && !$c->is_admin()) {
				$message = "This period is no longer active";
			}
		} elsif ($level =~ /period_predraw\((\d+)\)/) {
			my $draw_made = $c->db_selectone("SELECT COUNT(*) FROM brawl WHERE period_id = ?", {}, $1);
			if ($draw_made) {
				$message = "Operation unavailable after draw has been made";
			}
		} elsif ($level =~ /period_prebrawl\((\d+)\)/) {
			my $brawl_begun = $c->db_selectone("SELECT COUNT(*) FROM brawl NATURAL JOIN team_match_players WHERE brawl.period_id = ?", {}, $1);
			if ($brawl_begun) {
				$message = "Operation unavailable after brawl has begun";
			}
		} else {
			$message = "This action required an unknown permission";
		}
		if ($message) {
			$access_cache->{$level_orig} = $message;
			return $message;
		}
		$access_cache->{$level_orig} = undef;
	}
}

sub gen_form {
	my ($c, $name, $category) = @_;
	return unless $forms{$name};
	$category ||= $forms{$name}{categories}[0];
	my ($output_params, $output_params_info) = &parse_form_def($c, $name);
	return $output_params unless $output_params_info;
	my %reasons;
	my $ret = &fill_values($c, $name, $output_params, $output_params_info, \%reasons);
	return $ret if $ret;
	if (my $reason = &no_access($c, $name, $output_params, $output_params_info)) {
		return "Sorry, you do not have permission to access the $forms{$name}{brief} form ($reason)";
	}
	return &output_form($c, $name, $category, $output_params, $output_params_info); #, \%reasons);
}

sub form_list {
	my ($c, $category) = @_;
	my @form_names = grep { grep { $_ eq $category } @{$forms{$_}{categories}} } keys %forms;
	my %param_cache;
	$access_cache = {};
	$infer_cache = {};
	$check_cache = {};
	my %category_forms;
	my %sort;
	for my $form_name (@form_names) {
		if ($forms{$form_name}{extra_category}) {
			$category_forms{$forms{$form_name}{extra_category}} ||= [];
			push @{$category_forms{$forms{$form_name}{extra_category}}}, $form_name;
			$sort{$form_name} = 0;
		}
		if ($forms{$form_name}{override_category}) {
			$category_forms{$forms{$form_name}{override_category}} ||= [];
			push @{$category_forms{$forms{$form_name}{override_category}}}, $form_name;
			$sort{$form_name} = 0;
		} elsif ($forms{$form_name}{acts_on}) {
			my @cats = split /,/, $forms{$form_name}{acts_on};
			for (@cats) {
				s/([+-]).*//;
				if ($1) {
					if ($1 eq '+') {
						$sort{$form_name} = -1;
					} else {
						$sort{$form_name} = 1;
					}
				} else {
					$sort{$form_name} = 0;
				}
				$category_forms{$_} ||= [];
				push @{$category_forms{$_}}, $form_name;
			}
		}
	}
	my $output = '';
	my $last_cat = '';
	for my $category_name (sort { $categories{$a}{sort} <=> $categories{$b}{sort} } keys %category_forms) {
		for my $form_name (sort { $sort{$a} <=> $sort{$b} || $forms{$a}{brief} cmp $forms{$b}{brief} } @{$category_forms{$category_name}}) {
			my @param_names = @{$forms{$form_name}{params}};
			my %param_hash;
			for my $param_name (@param_names) {
				if (!exists $param_cache{$param_name}) {
					$param_cache{$param_name} = $c->param($param_name);
				}
				$param_hash{$param_name} = $param_cache{$param_name} if defined $param_cache{$param_name};
			}
			my ($output_params, $output_params_info) = &parse_form_def($c, $form_name);
			next unless $output_params_info;
			if (&fill_values_mini($c, $form_name, $output_params, $output_params_info)) {
				#$output .= "<li>bad params for $form_name</li>";
				next;
			}
			if (&no_access($c, $form_name, $output_params, $output_params_info)) {
				#$output .= "<li>no access to $form_name</li>";
				next;
			}
			if ($last_cat ne $category_name) {
				if ($last_cat) {
					$output .= "</ul>";
				}
				$output .= "<h3>$categories{$category_name}{name}</h3>";
				$output .= "<ul>";
			}
			$last_cat = $category_name;
			my $params = "";
			if (keys %param_hash) {
				$params = "&amp;".join("&amp;", map { "$form_name\_$_=$param_hash{$_}" } keys %param_hash);
			}
			$output .= qq|<li><a href="?form=$form_name&amp;$form_name\_category=$category$params">$forms{$form_name}{brief}</a></li>|;
		}
		if ($last_cat) {
			$output .= "</ul>";
		}
	}
	return $output;
}

# Used only on the form list page. Ignores multi params, and can only take
# parameters which are directly input or inferred from directly input
# parameters. Accepts only use parameters.
sub fill_values_mini {
	my ($c, $name, $output_params, $output_params_info) = @_;
	my %reasons; # Track badness of parameters.

	# Investigate the parameter list we're meant to have, and include any
	# supplied values.
	my @given_params; # Things that passed checks.
	foreach my $param_name (@$output_params) {
		# We'll be filling this out
		my $info = $output_params_info->{$param_name};

		if (is('informational', $info, 'admin') || is('override', $info, 'admin')) {
			# We don't care. They don't affect form-wide permissions.
			next;
		}
		
		# Do we have a value for this param supplied by the form?
		my $value;
		if (defined($value = $c->param($param_name))) {
			$info->{value} = $value;
		}

		if (!&bad_value($c, $info, \$info->{value}, $output_params_info) && $info->{value}) {
			push @given_params, $param_name;
		}
	}

	# That's all of the user-visible form input parsed. Now, if the user
	# happened to select an item in a dropdown which implies changes to other
	# items, we must ensure this has happened.
	# These choices will change any user_value as well as set auto_value.
	for my $user_updated (@given_params) {
		my $info = $output_params_info->{$user_updated};

		# There may be several inferences, so we must parse the type string
		$infer_cache->{$user_updated} ||= {};
		foreach my $type_info (@{$info->{types}}) {
			# At this point, we got a positive inference on our parameter list.
			if ($type_info->{definition}{infer} && @{$type_info->{params}}) {
				my $inferred;
				if (exists $infer_cache->{$user_updated}{$info->{value}}) {
					$inferred = $infer_cache->{$user_updated}{$info->{value}};
				} else {
					local $_ = $info->{value};
					$inferred = $type_info->{definition}{infer}->($c);
					$infer_cache->{$user_updated}{$_} = $inferred;
				}
				next unless $inferred;
				$inferred = $inferred->[0] if (ref $inferred->[0]);
				foreach my $idx (0..$#{$type_info->{params}}) {
					next unless defined $inferred->[$idx];
					if ($type_info->{params}[$idx] =~ /^\$(\w+)$/) {
						$output_params_info->{$1}{value} = $inferred->[$idx];
					} elsif ($type_info->{params}[$idx] ne $inferred->[$idx]) {
						# Undefined behaviour; error for now
						next;
					}
				}
			}
		}
	}
}

sub fill_values {
	my ($c, $name, $output_params, $output_params_info, $reason_hash) = @_;
	my $qname = $c->escapeHTML($name);
	my %reasons; # Track badness of parameters.
	# Investigate the parameter list we're meant to have, and include any
	# supplied values.
	foreach my $param_name (@$output_params) {
		# We'll be filling this out
		my $info = $output_params_info->{$param_name};

		if (is('informational', $info, 'admin')) {
			# Informational parameters cannot be passed.
			next;
		}
		
		# Do we have a value which was automatically supplied to the form in the
		# first place? (If this is equal to the below, we know the user did not
		# change the value.)
		my $value;
		if (defined($value = $c->param($name.'_auto_'.$param_name))) {
			if (is('multi', $info, 'admin')) {
				$info->{auto_value} = [ $c->param($name.'_auto_'.$param_name) ];
			} else {
				$info->{auto_value} = $value;
			}
		}

		# Do we have a value for this param supplied by the form?
		if (defined($value = $c->param($name.'_'.$param_name))) {
			if (!exists $info->{auto_value} || $info->{auto_value} ne $value) {
				if (is('multi', $info, 'admin')) {
					$info->{user_value} = [ $c->param($name.'_'.$param_name) ];
				} else {
					$info->{user_value} = $value;
				}
			}
		}

		if (is('override', $info, 'admin')) {
			# Overrides have no auto_value and are always valid null.
			if (!exists $info->{user_value}) {
				delete $info->{auto_value};
				next;
			}
			
			# Overrides can be set only by admins.
			if (!$c->is_admin) {
				delete $info->{auto_value};
				delete $info->{user_value};
				next;
			}
		}

		$info->{value} = exists $info->{user_value} ? $info->{user_value} : $info->{auto_value};
		$info->{value} ||= [] if is('multi',$info,'admin');
		if (my $reason = &bad_value($c, $info, \$info->{value}, $output_params_info)) {
			$reasons{$param_name} = "Value for $param_name was invalid ($reason).";
		}
	}

	# That's all of the user-visible form input parsed. Now, if the user
	# happened to select an item in a dropdown which implies changes to other
	# items, we must ensure this has happened.
	# These choices will change any user_value as well as set auto_value.
	my $user_updated = $c->param($name.'_changed');
	if ($user_updated) {
		my $info = $output_params_info->{$user_updated};
		$info->{focus} = 1;

		# There may be several inferences, so we must parse the type string
		foreach my $type_info (@{$info->{types}}) {
			# At this point, we got a positive inference on our parameter list.
			if ($type_info->{definition}{infer} && @{$type_info->{params}}) {
				local $_ = $info->{value};
				my $inferred = $type_info->{definition}{infer}->($c);
				next unless $inferred;
				$inferred = $inferred->[0] if (ref $inferred->[0]);
				foreach my $idx (0..$#{$type_info->{params}}) {
					next unless defined $inferred->[$idx];
					if ($type_info->{params}[$idx] =~ /^\$(\w+)$/) {
						$output_params_info->{$1}{auto_value} = $inferred->[$idx];
						$output_params_info->{$1}{value} = $inferred->[$idx];
						delete $output_params_info->{$1}{user_value};
					} elsif ($type_info->{params}[$idx] ne $inferred->[$idx]) {
						# Undefined behaviour; error for now
						return qq|Form $qname updated |.$c->escapeHTML($user_updated).qq|, and inferred a mismatch from the new value.|;
					}
				}
			}
		}
	}

	# At this point, then, we know the "rigid" values for all elements.
	# We must now work out value ranges for every element if we can.
	foreach my $param_name (@$output_params) {
		my $info = $output_params_info->{$param_name};
		my $multi = is('multi', $info, 'admin');
		foreach my $type_info (@{$info->{types}}) {
			# If the user updated any of our checking parameters, take this as
			# an indication that any default parameter should override even
			# user-set form data?
			# TODO maybe bad behaviour.
			my $infer = $user_updated && grep { $_ eq "\$$user_updated" } @{$type_info->{params}};
			if ($infer) {
				delete $info->{user_value};
				delete $info->{auto_value};
				delete $info->{value};
				$reasons{$param_name} ||= 'Inferred value from another choice.';
			}

			my @params = @{$type_info->{params}};

			# Replace all $ params with user-supplied values, if we have them.
			s/\$(\w+)/my $val = $output_params_info->{$1}{value}; $val = ref $val ? $val->[0] : $val; defined $val ? $val : ""/eg foreach(@params);


			# If we have enough information at this point to determine the DB
			# value of this field, we fill it in, but don't override
			# user-supplied params if they exist. (This is normally just
			# pre-filling text fields).
			if (my $get_fn = $type_info->{definition}{get}) {
				if ($multi) {
					$info->{auto_value} = [];
					if (my $multi_col = $info->{forms_info}{multi_col}) {
						for my $temp_val (@{$output_params_info->{$multi_col}{value}||[]}) {
							local $output_params_info->{$multi_col}{value} = $temp_val;
							my @params = @{$type_info->{params}};
							s/\$(\w+)/my $val = $output_params_info->{$1}{value}; defined $val ? $val : ""/eg foreach(@params);
							push @{$info->{auto_value}}, $get_fn->($c, @params);
						}
					}
					$info->{value} = $info->{auto_value} unless exists $info->{user_value};
				} else {
					my $getval = $get_fn->($c, @params);
					if ($getval) {
						$info->{auto_value} = $multi ? [ $getval ] : $getval;
						$info->{value} = $info->{auto_value} unless exists $info->{user_value};
					}
				}
			}

			if (is('hidden',$info,'admin') || is('informational',$info,'admin') || is('readonly',$info,'admin')) {
				# These param types cannot be pulled from the nth in a list,
				# and no list will ever be displayed, so we can stop here.
				next;
			}

			# It may be that we have enough information to produce a list of
			# possibilities. (This is pretty normal for ids.) If we can, get
			# that list now. If the list already exists, we must union it.
			my @value_list;
			if ((my $list_fn = $type_info->{definition}{list}) && !$type_info->{valid_new}) {
				@value_list = @{$list_fn->($c, @params)||[]};
				if (@{$type_info->{filter}}) {
					for my $filter_name (@{$type_info->{filter}}) {
						my $filter = $type_info->{definition}{$filter_name};
						@value_list = grep { $filter->($c, \@params, [ @$_[0,2..$#$_] ]) } @value_list if $filter;
					}
				}
				# If null is valid, we can place it in the list at the top.
				unshift @value_list, [ "", "None" ] if $type_info->{null_valid};
			}

			if ($type_info->{list_default}) {
				# Use this as the defaults.
				if ($multi && !$info->{value} || !@{$info->{value}}) {
					$info->{auto_value} = [map { $_->[0] } @value_list];
					$info->{value} = $info->{auto_value};
				}
			} else {
				# Intersect the results.
				if ($info->{value_list} && @value_list) {
					my %temp;
					$temp{$_->[0]} = -1 foreach(@{$info->{value_list}});
					my @list_vals;
					push @list_vals, $_ foreach(grep { $temp{$_->[0]} } @value_list);
					$info->{value_list} = \@list_vals;
				} elsif (@value_list) {
					$info->{value_list} = \@value_list;
				}
			}

			# Finally, if there's no value and we can find a default, use it.
			if (!$info->{value}) {
				if (my $def_fn = $type_info->{definition}{default}) {
					$info->{auto_value} = $multi ? [ $def_fn->($c, @params) ] : $def_fn->($c, @params);
					$info->{value} = $info->{auto_value};
				}
			}
		}

		# If this has a list and the current value isn't in it, remove it now.
		if ($info->{value_list} && defined $info->{value}) {
			if ($multi) {
				my $oldsize = scalar @{$info->{user_value}||[]};
				@{$info->{user_value}} = grep { my $v = $_; grep { $_->[0] eq $v } @{$info->{value_list}} } @{$info->{user_value}} if $info->{user_value};
				@{$info->{auto_value}} = grep { my $v = $_; grep { $_->[0] eq $v } @{$info->{value_list}} } @{$info->{auto_value}} if $info->{auto_value};
				$reasons{$param_name} ||= "$oldsize invalid value(s) detected; removing." if $oldsize != scalar @{$info->{user_value}||[]};
			} else {
				if (!grep { $_->[0] eq $info->{value} } @{$info->{value_list}}) {
					delete $info->{user_value};
					delete $info->{auto_value};
					undef $info->{value};
					$reasons{$param_name} ||= 'Invalid value detected; removing.';
				}
			}
		}

		if (!defined $info->{value}) {
			# If, by now, we /still/ didn't get a value for the field, we just
			# pick the top of the list if there is one.
			if ($info->{value_list}) {
				$info->{auto_value} = $info->{value_list}[0][0];
				$info->{value} = $info->{auto_value};

			# If it's hidden, and has no value, and that's not valid, drop out
			# before we generate an invalid form.
			} elsif ($info->{hidden} && !$info->{null_valid}) {
				return qq|Form $qname had a hidden param |.$c->escapeHTML($param_name).qq| which was initialised to null.|;
			}

			$reasons{$param_name} ||= "No value specified for $param_name." unless $info->{null_valid} or is('override', $info, 'admin');
		}
	}
	if ($reason_hash) {
		%$reason_hash = %reasons;
	}
	return;
}

sub output_form {
	my ($c, $name, $category, $output_params, $output_params_info, $reasons, $error) = @_;
	my $qname = $c->escapeHTML($name);
	my $output = "";

	# Given the filled form definition, output a form.
	$output .= qq|<h3>|.$c->escapeHTML($forms{$name}{brief}).qq|</h3>|;
	if (my $form_description = $forms{$name}{description}) {
		$form_description = $c->escapeHTML($form_description);
		$form_description =~ s/\n/<br\/>/g;
		$output .= qq|<p class="form">$form_description</p>|;
	}
	if ($error) {
		$output .= qq|<p class="form_error">Input is invalid ($error).</p>|;
	} elsif ($reasons) {
		$output .= qq|<p class="form_error">Input is invalid (see below).</p>|;
	}
	$output .= qq|<form name="$qname" method="post">|;
	$output .= qq|<input type="hidden" name="form" value="$qname"/>|;
	$output .= qq|<input type="hidden" name="$qname\_changed" value=""/>|;
	$output .= qq|<input type="hidden" name="$qname\_category" value="$category"/>|;
	$output .= qq|<input type="hidden" name="process" value="$qname"/>|;
	$output .= qq|<table class="form">|;
	my $hidden_output = "";
	foreach my $param_name (@$output_params) {
		my $info = $output_params_info->{$param_name};
		my $qparam_name = $c->escapeHTML($param_name);
		my $value = $info->{value};
		my $hidden = is('hidden', $info, $category);
		my $informational = is('informational', $info, $category);
		my $override = is('override', $info, $category);
		my $multi = is('multi', $info, $category);
		if ($override && !exists $info->{value}) {
			# Overrides are only visible once they are enabled.
			next;
		}
		if (!$informational && defined $info->{auto_value}) {
			if ($multi) {
				for my $value (@{$info->{auto_value}}) {
					$hidden_output .= qq|<input type="hidden" name="$qname\_auto_$qparam_name" value="|.$c->escapeHTML($value).qq|"/>|;
				}
			} else {
				$hidden_output .= qq|<input type="hidden" name="$qname\_auto_$qparam_name" value="|.$c->escapeHTML($info->{auto_value}).qq|"/>|;
			}
		}
		my $html = is('html', $info, $category);
		if ($hidden) {
			# This element is hidden at this level. Informational elements need no content generating at all.
			if (!$informational) {
				if ($multi) {
					for my $value (@{$value||[]}) {
						$hidden_output .= qq|<input type="hidden" name="$qname\_$qparam_name" value="|.$c->escapeHTML($value).qq|"/>|;
					}
				} else {
					$hidden_output .= qq|<input type="hidden" name="$qname\_$qparam_name" value="|.$c->escapeHTML($value).qq|"/>|;
				}
			}
		} else {
			# Visible form element
			$output .= qq|<tr>|;
			my $brief = $info->{forms_info}{brief} || $info->{type_defaults}{brief};
			my $description = $info->{forms_info}{description} || $info->{type_defaults}{description};
			$output .= qq|<td class="name">|;
			if ($brief) {
				$output .= $c->escapeHTML($brief);
			} else {
				$output .= $qparam_name;
			}
			if ($description) {
				$description = $c->escapeHTML($description);
				$description =~ s/\n/<br\/>/g;
				$output .= qq|<p>$description</p>|;
			}
			$output .= qq|</td>|;
			my $readonly = is('readonly', $info, $category);
			if ($readonly || $informational) {
				my $value_display;
				if ($value && $info->{value_list}) {
					my @res = grep { $value eq $_->[0] } @{$info->{value_list}};
					$value_display = $res[0][1] if @res;
				}
				$value_display ||= $value || 'None';
				if ($html) {
					$output .= qq|<td class="readonly">$value_display</td></tr>|;
				} else {
					$output .= qq|<td class="readonly">|.$c->escapeHTML($value_display).qq|</td></tr>|;
				}
				if (!$informational) {
					if ($multi) {
						for my $value (@{$value||[]}) {
							$hidden_output .= qq|<input type="hidden" name="$qname\_$qparam_name" value="|.$c->escapeHTML($value).qq|"/>|;
						}
					} else {
						$hidden_output .= qq|<input type="hidden" name="$qname\_$qparam_name" value="|.$c->escapeHTML($value).qq|"/>|;
					}
				}
				next;
			}
			$output .= qq|<td class="edit">|;
			my $input_type = $info->{forms_info}{input_type} || $info->{type_defaults}{input_type} || 'edit';
			if ($input_type eq 'textarea') {
				$output .= qq|<textarea name="$qname\_$qparam_name" type="text" cols="80" rows="15">$value</textarea>|;
			} elsif ($input_type eq 'checkbox') {
				if ($value) {
					$output .= qq|<input type="checkbox" name="$qname\_$qparam_name" value="1" checked="checked"/>|;
				} else {
					$output .= qq|<input type="checkbox" name="$qname\_$qparam_name" value="1"/>|;
				}
			} elsif ($info->{value_list}) {
				# Since we have a list of valid values, we make a <select>
				my $update_str = $info->{force_update} ? qq| onchange="document.$qname.process.value='';document.$qname.$qname\_changed.value='$qparam_name';document.$qname.submit();"| : "";
				if ($multi) {
					my $size = $info->{size} || int(@{$info->{value_list}||[]} / 2)+1;
					$size = 3 if $size < 3;
					$output .= qq|<select multiple="multiple" size="$size" name="$qname\_$qparam_name"$update_str>|;
				} else {
					$output .= qq|<select name="$qname\_$qparam_name"$update_str>|;
				}
				# TODO getting undef in names here...
				foreach my $valid_item (@{$info->{value_list}}) {
					my $selected;
					if ($multi) {
						$selected = (grep { $_ eq $valid_item->[0] } @$value) ? qq| selected="selected"| : "";
					} else {
						$selected = ($value && $value eq $valid_item->[0]) ? qq| selected="selected"| : "";
					}
					$output .= qq|<option value="|.$c->escapeHTML($valid_item->[0]).qq|"$selected>|.$c->escapeHTML($valid_item->[1]).qq|</option>| if $valid_item->[1];
				}
				$output .= "</select>";

			} else {
				# No list of valid values. Make a text box.
				# We may still be able to get the value based on our known
				# params, though.
				my $size = $info->{size} ? qq| size="$info->{size}"| : "";
				print "$param_name $info->{size}\n";
				my $value = $value ? qq| value="|.$c->escapeHTML($value).qq|"| : "";
				$output .= qq|<input name="$qname\_$qparam_name" type="text"$value$size/>|;
			}
			if ($info->{focus}) {
				$output .= qq|<script>set_focus=document.$qname.$qname\_$qparam_name;</script>|;
			}
			if ($reasons && $reasons->{$param_name}) {
				$output .= qq|</td><td class="form_error">|.$c->escapeHTML($reasons->{$param_name});
				delete $reasons->{$param_name};
			}
			$output .= qq|</td></tr>|;
		}
	}
	$output .= qq|</table>|;
	$output .= $hidden_output;
	for my $param_name (keys %$reasons) {
		$output .= "<p>Internal error: $param_name was bad for reason: $reasons->{$param_name}</p>";
	}
	$output .= qq|<input type="submit" name="$qname\_submit" value="Submit"/>|;
	$output .= qq|</form>|;
	return $output;
}

sub parse_form_def {
	my ($c, $name) = @_;
	my $qname = $c->escapeHTML($name);
	my @output_params;
	my %output_params_info;
	my $num_params = @{$forms{$name}{params}} / 2 - 1;

	# Loop the array, parsing any encoded stuff.
	foreach my $paramno (0..$num_params) {
		my $param_name = $forms{$name}{params}[$paramno*2];
		push @output_params, $param_name;

		# We'll be filling this out
		$output_params_info{$param_name} ||= {};
		my $info = $output_params_info{$param_name};
		
		# This is the form def's info
		my $forms_info = $forms{$name}{params}[$paramno*2+1];
		$info->{forms_info} = $forms_info;

		my @types = split /:/, $forms_info->{type};
		$info->{types} = [];

		# Parse the checks
		foreach my $type_str (@types) {
			my $type_info = {};
			push @{$info->{types}}, $type_info;

			# The final entry in this list is the type itself.
			my @mods = split /\|/, $type_str;
			my $type = pop @mods;

			# Pull off the parameter list.
			my @params;
			if ($type =~ s/\((.*)\)//) {
				@params = split /,/, $1;
			}

			# Before we treat them destructively, copy the parameters.
			$type_info->{params} = [@params];
			$type_info->{type} = $type;
			$type_info->{type_str} = $type_str;
			$type_info->{definition} = $input_tests{$type};


			# If we have any checks depending on other parameters, those
			# parameters will cause the form to update. Make sure we note this.
			# Of course, if they're informational, we don't really care.
			if (!is('informational',$info,'admin')) { 
				foreach (@params) {
					while (/\$(\w+)/g) {
						$output_params_info{$1} ||= {};
						$output_params_info{$1}{force_update} ||= {};
						$output_params_info{$1}{force_update}{$param_name} = 1;
					}
				}
			}

			# Set up some flags.
			$type_info->{null_valid} = 1 if grep /^null_valid$/, @mods;
			$type_info->{valid_new} = 1 if grep /^valid_new$/, @mods;
			$type_info->{valid} = 1 if grep /^valid$/, @mods;
			$type_info->{list_default} = 1 if grep /^list_default$/, @mods;
			$type_info->{filter} = [ grep /^filter_/, @mods ];

			if (my @sizes = grep /^size\((\d+)\)$/, @mods) {
				$sizes[0] =~ /size\((\d+)\)/;
				$info->{size} = $type_info->{size} = $1;
			}

			# Null is valid if it's valid for /all/ types.
			if (!$type_info->{null_valid}) {
				undef $info->{null_valid};
			} elsif (!exists $info->{null_valid}) {
				$info->{null_valid} = 1;
			}

			return qq|Form $qname had invalid input type |.$c->escapeHTML($type) unless $type_info->{definition};
		}

		delete $info->{null_valid} if exists $info->{null_valid} && !defined $info->{null_valid};

		$info->{type_defaults} = $info->{types}[0]{definition}{defaults};
	}
	return (\@output_params, \%output_params_info);
}

sub bad_value {
	my ($c, $info, $value, $params_info) = @_;

	for my $type (@{$info->{types}}) {

		my $check_exists = !$type->{valid};
		my $must_exist = !$type->{valid_new};
		my $must_not_exist = $type->{valid_new};

		my @params = @{$type->{params}};
		s/\$(\w+)/my $val = $params_info->{$1}{value}; defined $val ? $val : ""/eg foreach(@params);
		if ($check_cache) {
			if (exists $check_cache->{$type->{type_str}}) {
				return $check_cache->{$type->{type_str}} if $check_cache->{$type->{type_str}};
				next;
			}
		}

		my ($no_cache, $message);
		for my $value (ref $$value ? map { \$_ } @$$value : $value) {
			if ($type->{list_default}) {
				# This type is used only to default lists, so skip it.
				next;
			}

			if (my $modify = $type->{definition}{modify}) {
				local $_ = $$value;
				$modify->($c, @params);
				$$value = $_;
				$no_cache = 1;
			}

			# Null values are trivial to deal with. However, must check after above
			# since, for instance, the default type will set defaults.
			if (!$type->{null_valid}) {
				if (!$$value) {
					if (my $default = $type->{definition}{default}) {
						$$value = $default->($c, @params);
						# Special case; ignore cache.
						$no_cache = 1;
						$message = "no value specified; default picked";
						next;
					}
				}

				if (!$$value) {
					$message = "must not be empty";
					next;
				}
			} elsif (!$$value) {
				next;
			}

			if (my $check = $type->{definition}{check}) {
				local $_ = $$value;
				my $ret = $check->($c, @params);
				if (!$ret) {
					$message = "invalid value";
					next;
				}
			}

			if ($check_exists) {
				if (my $exists = $type->{definition}{exists}) {
					local $_ = $$value;
					my $ret = $exists->($c, @params);
					if ($ret && $must_not_exist) {
						$message = "cannot use an existing value";
						next;
					} elsif (!$ret && $must_exist) {
						$message = "must use an existing value ($_)";
						next;
					}
				} elsif (!exists $type->{definition}{exists}) {
					$message = "existence check requested but none available";
					next;
				}
			}
		} continue {
			if ($check_cache && !$no_cache) {
				$check_cache->{$type->{type_str}} = $message;
			}
			if ($message) {
				return $message;
			}
			undef $no_cache;
		}
	}

	return;
}

sub is {
	my ($test, $info, $category) = @_;
	my $value = $info->{forms_info}{$test} || $info->{type_defaults}{$test};
	if (ref $value) {
		return scalar grep { $_ eq $category } @$value;
	} else {
		return $value;
	}
}

1;
