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
our (%forms, %input_tests);

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
	if (%reasons) {
		$c->log($name, 0, "Bad input.", \%params);
		print &output_form($c, $name, $c->param($name.'_category') || 'admin', $input_params, $input_params_info, \%reasons);
		$c->footer;
		exit 0;
	}
	if (my $reason = &no_access($c, $name, $input_params, $input_params_info)) {
		$c->log($name, 0, "Permission denied.", \%params);
		$c->die_fatal_permissions("Sorry, you do not have permission to access the $forms{$name}{brief} form ($reason)");
	}
	if (my $action = $forms{$name}{action}) {
		my ($success, $reason) = $action->($c, \%params);
		$c->log($name, $success, $reason, \%params);
		print qq|<h3>|.$c->escapeHTML($forms{$name}{brief}).qq|</h3>|;
		if ($success) {
			print $c->p("Success: $reason");
		} else {
			print $c->p("Failure: $reason");
		}
		if ($params{member_id}) {
			print $c->p(qq|To member <a href="admin.pl?member_id=$params{member_id}">admin</a> or <a href="index.pl?page=games&amp;memberid=$params{member_id}">game list</a>.|);
		}
		if ($params{team_id}) {
			print $c->p(qq|<a href="admin.pl?team_id=$params{team_id}">To team admin</a>.|);
		}
		if ($params{clan_id}) {
			print $c->p(qq|To clan <a href="admin.pl?clan_id=$params{clan_id}">admin</a> or <a href="index.pl?page=clan&amp;clanid=$params{clan_id}">member list</a>.|);
		}
		if ($c->is_admin) {
			print $c->p(qq|<a href="admin.pl">To overall admin</a>.|);
		}
		$c->footer;
		exit 0;
	} else {
		$c->die_fatal("Submitted form $name had no action.");
	}
}

sub no_access {
	my ($c, $name, $params, $params_info) = @_;
	my $level = $forms{$name}{level};
	$level =~ s/\$(\w+)/my $val = $params_info->{$1}{value}; defined $val ? $val : ""/eg;
	if ($level eq 'admin' || $level =~ /clan_(leader|moderator)\(\)/) {
		return $c->is_admin() ? undef : "You are not an admin";
	} elsif ($level =~ /clan_leader\((\d+)\)/) {
		return $c->is_clan_leader($1) ? undef : "You are not a clan leader";
	} elsif ($level =~ /clan_moderator\((\d+)\)/) {
		return $c->is_clan_moderator($1) ? undef : "You are not a clan moderator";
	} else {
		return "This action required an unknown permission";
	}
}

sub gen_form {
	my ($c, $name, $category) = @_;
	return unless $forms{$name};
	$category ||= $forms{$name}{category}[0];
	my ($output_params, $output_params_info) = &parse_form_def($c, $name);
	return $output_params unless $output_params_info;
	my $ret = &fill_values($c, $name, $output_params, $output_params_info);
	return $ret if $ret;
	if (my $reason = &no_access($c, $name, $output_params, $output_params_info)) {
		return "Sorry, you do not have permission to access the $forms{$name}{brief} form ($reason)";
	}
	return &output_form($c, $name, $category, $output_params, $output_params_info);
}

sub form_list {
	my ($c, $category) = @_;
	my @form_names = sort grep { grep { $_ eq $category } @{$forms{$_}{category}} } keys %forms;
	my %param_cache;
	my %access_cache;
	my $output = "<ul>";
	for my $form_name (@form_names) {
		my @param_names = @{$forms{$form_name}{params}};
		my %param_hash;
		for my $param_name (@param_names) {
			if (!exists $param_cache{$param_name}) {
				$param_cache{$param_name} = $c->param($param_name);
			}
			$param_hash{$param_name} = $param_cache{$param_name} if defined $param_cache{$param_name};
		}
		# TODO check access
		my $params = "";
		if (keys %param_hash) {
			$params = "&amp;".join("&amp;", map { "$form_name\_$_=$param_hash{$_}" } keys %param_hash);
		}
		$output .= qq|<li><a href="?form=$form_name&amp;$form_name\_category=$category$params">$forms{$form_name}{brief}</a></li>|;
	}
	$output .= "</ul>";
	return $output;
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
		
		# Do we have a value which was automatically supplied to the form in the
		# first place? (If this is equal to the below, we know the user did not
		# change the value.)
		my $value;
		if (defined($value = $c->param($name.'_auto_'.$param_name))) {
			$info->{auto_value} = $value;
		}

		# Do we have a value for this param supplied by the form?
		if (defined($value = $c->param($name.'_'.$param_name))) {
			if (!exists $info->{auto_value} || $info->{auto_value} ne $value) {
				$info->{user_value} = $value;
			}
		}

		$info->{value} = exists $info->{user_value} ? $info->{user_value} : $info->{auto_value};
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
			}

			my @params = @{$type_info->{params}};

			# Replace all $ params with user-supplied values, if we have them.
			s/\$(\w+)/my $val = $output_params_info->{$1}{value}; defined $val ? $val : ""/eg foreach(@params);

			# If we have enough information at this point to determine the DB
			# value of this field, we fill it in, but don't override
			# user-supplied params if they exist. (This is normally just
			# pre-filling text fields).
			if (my $get_fn = $type_info->{definition}{get}) {
				my $getval = $get_fn->($c, @params);
				if ($getval) {
					$info->{auto_value} = $getval;
					$info->{value} = $info->{auto_value} unless exists $info->{user_value};
				}
			}

			# It may be that we have enough information to produce a list of
			# possibilities. (This is pretty normal for ids.) If we can, get
			# that list now. If the list already exists, we must union it.
			if ((my $list_fn = $type_info->{definition}{list}) && !$type_info->{valid_new}) {
				my $new_vals = $list_fn->($c, @params);
				# If null is valid, we can place it in the list at the top.
				unshift @$new_vals, [ "", "None" ] if $new_vals && $type_info->{null_valid};
				if ($info->{value_list} && $new_vals) {
					my %temp;
					$temp{$_->[0]} = -1 foreach(@{$info->{value_list}});
					my @list_vals;
					push @list_vals, $_ foreach(grep { $temp{$_->[0]} } @$new_vals);
					$info->{value_list} = \@list_vals;
				} elsif ($new_vals) {
					$info->{value_list} = $new_vals;
				}
			}
		}

		# If this has a list and the current value isn't in it, remove it now.
		if ($info->{value_list} && defined $info->{value}) {
			if (!grep { $_->[0] eq $info->{value} } @{$info->{value_list}}) {
				delete $info->{user_value};
				delete $info->{auto_value};
				undef $info->{value};
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

			$reasons{$param_name} ||= "No value specified for $param_name." unless $info->{null_valid};
		}
	}
	if ($reason_hash) {
		%$reason_hash = %reasons;
	}
	return;
}

sub output_form {
	my ($c, $name, $category, $output_params, $output_params_info, $reasons) = @_;
	my $qname = $c->escapeHTML($name);
	my $output = "";

	# Given the filled form definition, output a form.
	$output .= qq|<h3>|.$c->escapeHTML($forms{$name}{brief}).qq|</h3>|;
	if (my $form_description = $forms{$name}{description}) {
		$form_description = $c->escapeHTML($form_description);
		$form_description =~ s/\n/<br\/>/g;
		$output .= qq|<p class="form">$form_description</p>|;
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
		$output .= qq|<input type="hidden" name="$qname\_auto_$qparam_name" value="|.$c->escapeHTML($info->{auto_value}||"").qq|"/>|;
		my $value = $info->{value};
		my $hidden = grep { $_ eq $category } @{$info->{forms_info}{hidden} || $info->{type_defaults}{hidden} || []};
		if ($hidden) {
			# This element is hidden at this level.
			$hidden_output .= qq|<input type="hidden" name="$qname\_$qparam_name" value="|.$c->escapeHTML($value).qq|"/>|;
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
			my $readonly = grep { $_ eq $category } @{$info->{forms_info}{readonly} || $info->{type_defaults}{readonly} || []};
			if ($readonly) {
				my $value_display;
				if ($value && $info->{value_list}) {
					my @res = grep { $value eq $_->[0] } @{$info->{value_list}};
					$value_display = $res[0][1] if @res;
				}
				$value_display ||= $value || 'None';
				$output .= qq|<td class="readonly">|.$c->escapeHTML($value_display).qq|</td></tr>|;
				$hidden_output .= qq|<input type="hidden" name="$qname\_$qparam_name" value="|.$c->escapeHTML($value).qq|"/>|;
				next;
			}
			$output .= qq|<td class="edit">|;
			my $input_type = $info->{forms_info}{input_type} || $info->{type_defaults}{input_type} || 'edit';
			if ($input_type eq 'textarea') {
				$output .= qq|<textarea name="$qname\_$qparam_name" type="text" cols="80" rows="15">$value</textarea>|;
			} elsif ($info->{value_list}) {
				# Since we have a list of valid values, we make a <select>
				my $update_str = $info->{force_update} ? qq| onchange="document.$qname.process.value='';document.$qname.$qname\_changed.value='$qparam_name';document.$qname.submit();"| : "";
				$output .= qq|<select name="$qname\_$qparam_name"$update_str>|;
				foreach my $valid_item (@{$info->{value_list}}) {
					my $selected = ($value && $value eq $valid_item->[0]) ? qq| selected="selected"| : "";
					$output .= qq|<option value="|.$c->escapeHTML($valid_item->[0]).qq|"$selected>|.$c->escapeHTML($valid_item->[1]).qq|</option>|;
				}
				$output .= "</select>";

			} else {
				# No list of valid values. Make a text box.
				# We may still be able to get the value based on our known
				# params, though.
				my $value = $value ? qq| value="|.$c->escapeHTML($value).qq|"| : "";
				$output .= qq|<input name="$qname\_$qparam_name" type="text"$value/>|;
			}
			if ($info->{focus}) {
				$output .= qq|<script>set_focus=document.$qname.$qname\_$qparam_name;</script>|;
			}
			if ($reasons && $reasons->{$param_name}) {
				$output .= qq|</td><td class="form_error">|.$c->escapeHTML($reasons->{$param_name});
			}
			$output .= qq|</td></tr>|;
		}
	}
	$output .= qq|</table>|;
	$output .= $hidden_output;
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

			# If we have any checks depending on other parameters, those
			# parameters will cause the form to update. Make sure we note this.
			foreach (@params) {
				while (/\$(\w+)/g) {
					$output_params_info{$1} ||= {};
					$output_params_info{$1}{force_update} ||= {};
					$output_params_info{$1}{force_update}{$param_name} = 1;
				}
			}

			$type_info->{type} = $type;
			$type_info->{definition} = $input_tests{$type};

			# Set up some flags.
			$type_info->{null_valid} = 1 if grep /^null_valid$/, @mods;
			$type_info->{valid_new} = 1 if grep /^valid_new$/, @mods;
			$type_info->{valid} = 1 if grep /^valid$/, @mods;

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

		if (my $modify = $type->{definition}{modify}) {
			local $_ = $$value;
			$modify->($c, @params);
			$$value = $_;
		}

		# Null values are trivial to deal with. However, must check after above
		# since, for instance, the default type will set defaults.
		if (!$type->{null_valid}) {
			if (!$$value) {
				if (my $default = $type->{definition}{default}) {
					$$value = $default->($c, @params);				
				}
			}

			if (!$$value) {
				return "must not be empty";
			}
		} elsif (!$$value) {
			return undef;
		}

		if (my $check = $type->{definition}{check}) {
			local $_ = $$value;
			my $ret = $check->($c, @params);
			if (!$ret) {
				return "invalid value";
			}
		}

		if ($check_exists) {
			if (my $exists = $type->{definition}{exists}) {
				local $_ = $$value;
				my $ret = $exists->($c, @params);
				if ($ret && $must_not_exist) {
					return "cannot use an existing value";
				} elsif (!$ret && $must_exist) {
					return "must use an existing value ($_)";
				}
			} elsif (!exists $type->{definition}{exists}) {
				return "existence check requested but none available";
			}
		}
	}

	return;
}