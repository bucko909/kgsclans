package Clans::Tables;

use strict;
use warnings;
use Clans;
use POSIX qw/strftime/;
use Carp qw/cluck/;
use Text::Textile;
$SIG{__WARN__} = sub { cluck $_[0] };


# Each table column is a hashref.
#	Whenever array values are implied, it's acceptable to use a singleton as a
# one element array.
#	Whenever subrefs are permitted, the parameters are all 2-D arrays. $_[0] is
# the columns in order, $_[$i] is the $i'th param's columns. The variable
# $persist is scoped to be local to each column. $c is a reference to the Clans
# object.
#	Entries marked * are required.

# params => columns names which are used as params to this column
#				([ string, ... ]; default [])
# *tables => the table names which the column selects from; if the column takes
#           params, table_name(param_num) will use the same data set as that
#           param. Specifying two words will alias the table.
#				([ string, ... ])
# *cols => the column names within the tables which the column selects from. Can
#          use SQL functions, but if so, column names must be ${[table.]name}.
#				([ string, ... ])
# *description => description of the column (string)
# *title => column heading (string)
# *fulltitle => column short description (string)
# where => WHERE clause to use. (string, or subref returning
#          ( string, bindvalues )).
# sort => 'string' (sub { lc $_[0][0] cmp lc $_[0][0] }),
#         'numeric' (sub { $_[0][0] <=> $_[0][0] }),
#         or a subref for use with sort(). Default 'string'.
# init => subref to execute before any data arrives. Default: do nothing.
# row => subref to parse data. May return a hashref with key 'class' containing
#        an arrayref of classes to add to row. Default: do nothing.
# cell => subref to define cell properties. Return value same as row.
#         Default: do nothing.
# data => subref to use to render data. Executed after row and cell. Returns
#         HTML to put in cell. Default: escapeHTML the first column.
# tot{row,cell,data} => same as above, but for the totals row. Default: blank.
# hidden => boolean value to determine if column is never rendered.

sub get_array {
	my ($depth, $param, $alias) = @_; # TODO $depth
	if (!defined $param) {
		return ();
	} elsif (!ref $param) {
		return ($param);
	} elsif (ref $param eq 'ARRAY') {
		return (@$param);
	} elsif ($alias && ref $param eq 'HASH') {
		return get_array($depth, $param->{$alias});
	} else {
		return ($param);
	}
}

sub deep_copy {
	my ($data) = @_;
	if (!$data || !ref $data) {
		return $data;
	} elsif (ref $data eq 'ARRAY') {
		return [ map { deep_copy($_) } @$data ];
	} elsif (ref $data eq 'HASH') {
		return { map { deep_copy($_) } %$data };
	} else {
		return $data;
	}
}

our (%col_types);
sub parse_col_string {
	my ($full_col_string) = @_;
	my $col_string = $full_col_string; # For manipulation.
	my (@params, $col_type_name, $col_name);
	my %extra;
	if ($col_string =~ s/<([^>]*)>//) {
		# Extra settings
		for(split /\s*,\s*/, $1) {
			$extra{$1} = $2 if /(.*?)=(.*)/;
		}
	}
	if ($col_string =~ s/\((.*?)\)//) {
		@params = split /\s*,\s*/, $1;
	}
	if ($col_string =~ /^(\S*)\s(\S*)$/) {
		$col_type_name = $1;
		$col_name = $2;
	} else {
		$col_type_name = $col_string;
	}

	my $col_type = $col_types{$col_type_name};
	return unless $col_type;

	# We don't want to modify the root type!
	$col_type = deep_copy($col_type);

	# Import local definitions
	$col_type->{$_} = $extra{$_} for keys %extra;
	$col_type->{name} = $col_type_name;
	return ($col_type, $col_name, @params);
}

our ($persist, $c);
sub render_table {
	my ($cptr, $cols) = @_;
	local $c = $cptr;
	my $output = "";

	my $sql_parse_data = {
		select_col_sql_array => [],
		select_col_sql_lookup => {},
		tables => [], # array of hash with keys alias, joins, grouped
		where => [], # AND together to make WHERE clause
		where_bind => [], # Bind values for WHERE clause
		group_col_array => [],
		group_col_lookup => {},
		named_columns => {},
		output_columns => [],
	};
	my @input_cols = split /;/, $cols;
	my @output_cols;

	my (@structure_cols, @data_cols);
	# Sort columns into structure and nonstructure. This is a seperate pass to allow data columns to add extra structure columns.
	my $on_structure = 1;
out:
	for my $full_col_string (@input_cols) {
		my ($col_type, $col_name, @params) = parse_col_string($full_col_string);

		# Check the column is of a valid type
		if (!$col_type) {
			$output .= qq|<p class="error">Unknown column type |.$c->escapeHTML($full_col_string).qq|.</p>|;
			next;
		}

		my ($ret, $data) = merge_col($sql_parse_data, $col_type, $full_col_string, @params);
		if (!$ret) {
			$output .= $data;
			next;
		}

		if ($col_name) {
			$sql_parse_data->{named_columns}{$col_name} = $data;
		}
	}

	# Build the FROM clause
	my $from_clause = "$sql_parse_data->{tables}[0]{sql_name} $sql_parse_data->{tables}[0]{sql_alias}";
	my @join_bind;
	for(1..$#{$sql_parse_data->{tables}}) {
		my $join_type = 'INNER';
		if ($sql_parse_data->{tables}[$_]{sql_name} =~ s/^\[outer\]//) {
			$join_type = 'LEFT OUTER';
		}
		$from_clause .= " $join_type JOIN $sql_parse_data->{tables}[$_]{sql_name} $sql_parse_data->{tables}[$_]{sql_alias}";
		if (@{$sql_parse_data->{tables}[$_]{joins}}) {
			$from_clause .= " ON ".join(' AND ', @{$sql_parse_data->{tables}[$_]{joins}});
			push @join_bind, @{$sql_parse_data->{tables}[$_]{join_bind}}
		}
	}

	my $select_clause = join(', ', @{$sql_parse_data->{select_col_sql_array}});
	my $where_clause = @{$sql_parse_data->{where}} ? " WHERE ".join(' AND ', @{$sql_parse_data->{where}}) : "";
	my @where_bind = @{$sql_parse_data->{where_bind}};
	my $group_clause = @{$sql_parse_data->{group_col_array}} ? " GROUP BY ".join(', ', @{$sql_parse_data->{group_col_array}}) : "";

	# Execute our query.
	my $stop = $output;
	# TODO sort, limit
	my $SQL = "SELECT $select_clause FROM $from_clause$where_clause$group_clause";
	$output .= "<p>$cols</p>";
	$output .= "<p>$SQL</p>";
	my $results = $stop ? [] : $c->db_select($SQL, {}, @join_bind, @where_bind);

	$output .= "<table>";
	$output .= "<tr>";

	# Header
	my @rowinit_cols;
	for my $col_data (@{$sql_parse_data->{output_columns}}) {
		if ($col_data->{type_data}{rowinit}) {
			push @rowinit_cols, $col_data;
		}
		my $title = $col_data->{type_data}{title};
		$title = $title->() if ($title && ref $title && ref $title eq 'CODE');
		$output .= "<th>$title</th>";
		if ($col_data->{type_data}{init}) {
			local $persist;
			$col_data->{type_data}{init}->();
			$col_data->{persist} = $persist;
		}
	}
	$output .= "</tr>";

	# Data
	for my $row (@$results) {
		my $col_data;
		for $col_data (@rowinit_cols) {
			my @params = map { [ map { $row->[$_] } @{$_->{sql_columns}} ] } ($col_data, @{$col_data->{params}});
			$col_data->{type_data}{rowinit}->(@params);
			# TODO class
		}
		$output .= "<tr>";
		for my $col_data (@{$sql_parse_data->{output_columns}}) {
			my @params = map { [ map { $row->[$_] } @{$_->{sql_columns}} ] } ($col_data, @{$col_data->{params}});
			# TODO cellinit
			$output .= "<td>";
			if ($col_data->{type_data}{data}) {
				$output .= $col_data->{type_data}{data}->(@params);
			} else {
				$output .= $c->escapeHTML($params[0][0] || "");
			}
			$output .= "</td>";
		}
		$output .= "</tr>";
	}

	# TODO - totals

	$output .= "</table>";
	return $output;
}

=pod

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
=cut

sub merge_col {
	my ($sql_parse_data, $col_type, $full_col_string, @params) = @_;

	# Start building a return value.
	my $data = {
		type => ($col_type->{is_a} || $col_type->{name}),
		type_data => $col_type,
		tables => {},
	};

	local $sql_parse_data->{named_columns} = $sql_parse_data->{named_columns};
	if ($col_type->{structure}) {
		# This column implies some table structure.
		for my $full_structure_col_string (@{$col_type->{structure}}) {
			my ($s_col_type, $s_col_name, @s_params) = parse_col_string($full_structure_col_string);
			if (!$s_col_type) {
				return (0, qq|<p class="internal error">Unknown structure column type: |.$c->escapeHTML($full_structure_col_string).qq| in |.$c->escapeHTML($full_col_string).qq|.</p>|);
			}

			# Replace our parameters into the param strings.
			s/^\$(\d+)$/$params[$1]/g for(@s_params);

			# Recursive merge.
			my ($ret, $s_data) = merge_col($sql_parse_data, $s_col_type, "$full_structure_col_string in $full_col_string", @s_params);
			return (0, $s_data) if !$ret;

			$sql_parse_data->{named_columns}{$s_col_name} = $s_data if $s_col_name;
		}
	}

	# Now pull any tables from the just-parsed structure.
	for my $table_def (get_array(1, $col_type->{structure_tables})) {
		my $alias;
		if ($table_def =~ s/\s+(\S+)$//) {
			$alias = $1;
		}
		if ($table_def =~ /^(\S+)\((\S+)\)$/) {
			$alias ||= $1;
			$data->{tables}{$alias} = $sql_parse_data->{named_columns}{$2}{tables}{$1};
		} else {
			return (0, qq|<p class="internal error">Structure table with no parameter: |.$c->escapeHTML($full_col_string).qq|.</p>|);
		}
	}

	# Parse the parameter data, if any.
	my @req_params = get_array(1, $col_type->{params});
	if (@req_params != @params) {
		return (0, qq|<p class="error">Bad parameter count: |.$c->escapeHTML($full_col_string).qq|.</p>|);
	} elsif (@req_params) {
		# Params required.
		$data->{params} = [];
		for (0..$#req_params) {
			# For each param, we need to parse the value (it's just a name for now) and check it (just check it exists and is of the right type for now).
			my $target_column;
			if ($sql_parse_data->{named_columns}{$params[$_]}) {
				$target_column = $sql_parse_data->{named_columns}{$params[$_]};
			} else {
				return (0, qq|<p class="error">Parameter $_ ($params[$_]) did not exist: |.$c->escapeHTML($full_col_string).qq|.</p>|);
			}
			if ($req_params[$_] ne 'string' &&
				(
					($req_params[$_] eq '*' && !$target_column)
					|| ($req_params[$_] ne '*' && $target_column->{type} ne $req_params[$_]))) {
				return (0, qq|<p class="error">Parameter $_ ($params[$_]) had bad type $data->{$params[$_]}{type} ne $req_params[$_]: |.$c->escapeHTML($full_col_string).qq|.</p>|);
			}
			$data->{params}[$_] = $target_column;
		}
	}

	# Now arrange for tables to be linked.
	for my $table_name (get_array(1, $col_type->{tables})) {
		my $alias;
		if ($table_name =~ s/\s+(\S+)$//) {
			$alias = $1;
		}
		my $table_data;
		if ($table_name =~ /^(\S*)\((\d+)\)$/) {
			# It's being copied from a parameter.
			my ($param_table_name, $param_num) = ($1, $2);
			$alias ||= $param_table_name;
			my $param_data = $data->{params}[$param_num];
			if ($param_table_name) {
				$table_data = $param_data->{tables}{$param_table_name};
			} else {
				$table_data = $param_data->{main_table};
			}
			if (!defined $table_data) {
				# Since at this point the parameter has been verified, we're in a sticky situation if it's missing a table we're after.
				return (0, qq|<p class="internal_error error">Parameter table $param_table_name did not exist in parameter $param_num: |.$c->escapeHTML($full_col_string).qq|.</p>|);
			}
		} else {
			if ($table_name =~ /^\[[^\]]+\](.*)/) {
				$alias ||= $1;
			} else {
				$alias ||= $table_name;
			}
			# It's a new join. Pick the next index and use it as our "data".
			my $table_num = @{$sql_parse_data->{tables}};
			$table_data = {};
			$table_data->{sql_name} = $table_name;
			$table_data->{sql_alias} = "table_".$table_num; # TODO prettify

			$table_data->{joins} = [];
			$table_data->{join_bind} = [];

			# Add the new table to the running list.
			push @{$sql_parse_data->{tables}}, $table_data;
		}

		# Is the table going to be grouped?
		for my $group_clause (get_array(1, $col_type->{group}, $alias)) {
			my ($table_used, $column);
			if ($group_clause =~ /^(\w+)$/) {
				# It's a raw column name.
				$column = $table_data->{sql_alias}.'.'.$1;
				$table_used = $table_data->{sql_alias};
			} elsif ($group_clause =~ /^(\w+)\.(\w+)$/) {
				# It's got a table alias.
				$column = $data->{tables}{$1}{sql_alias}.'.'.$2;
				$table_used = $data->{tables}{$1}{sql_alias};
			} else {
				# Since at this point the parameter has been verified, we're in a sticky situation if it's missing a table we're after.
				return (0, qq|<p class="internal_error error">Group clause must be plain column: |.$c->escapeHTML($full_col_string).qq|.</p>|);
			}

			# Add the GROUP BY clause (if it's not already there).
			if (!$sql_parse_data->{group_col_lookup}{$column}) {
				$sql_parse_data->{group_col_lookup}{$column} = @{$sql_parse_data->{group_col_array}};
				push @{$sql_parse_data->{group_col_array}}, $column;
			}

			# Mark the column as grouped. This means any filter will apply to the JOIN, not the WHERE.
			$table_data->{grouped} = 1;
		}

		# Any WHERE clauses on this table? It's important to do this here, as if a column is grouped, the WHERE clause becomes an ON clause.
		for my $where_clause (get_array(1, $col_type->{where}, $alias)) {
			my @bind;
			# Some clauses will have executable segments so that they can eg. select on provided period.
			if (ref $where_clause && ref $where_clause eq 'CODE') {
				($where_clause, @bind) = $where_clause->();
			}
			my $clause;
			if ($where_clause =~ /^(\w+)$/) {
				# It's a raw column name.
				$clause = $table_data->{alias}.'.'.$1;
			} elsif ($where_clause =~ /^(\w+)\.(\w+)$/) {
				# It's got a table alias.
				$clause = $data->{tables}{$1}{alias}.'.'.$2;
			} else {
				$where_clause =~ s[\$\{(\w+)\.(\w+)\}][$data->{tables}{$1}{sql_alias}.'.'.$2]eg;
				$where_clause =~ s[\$\{(\w+)\}][$table_data->{sql_alias}.'.'.$1]eg;
				$clause = $where_clause;
			}
			if ($table_data->{grouped}) {
				# This table is marked as grouped, so the clause becomes a part of the table's ON, not the overall WHERE
				push @{$table_data->{joins}}, $clause;
				push @{$table_data->{join_bind}}, @bind;
			} else {
				# It's just a where clause.
				push @{$sql_parse_data->{where}}, $clause;
				push @{$sql_parse_data->{where_bind}}, @bind;
			}
		}

		$data->{main_table} = $table_data if !defined $data->{main_table};
		$data->{tables}{$alias} = $table_data;
	}

	# We now know what tables this input column referenced. Assuming there's any at all, we now need to see what SQL columns it needs adding, and add their
	# column numbers so we can pull them out of the results later.
	# sql_columns ends up as a list of SQL columns corresponding to the requested columns.
	$data->{sql_columns} = [];
	for (get_array(1, $col_type->{cols})) {
		my $sqlcol_content;
		if (/^(\w+)$/) {
			# It's a raw column name.
			$sqlcol_content = $data->{main_table}{sql_alias}.'.'.$1;
		} elsif (/^(\w+)\.(\w+)$/) {
			# It's got a table alias.
			$sqlcol_content = $data->{tables}{$1}{sql_alias}.'.'.$2;
		} elsif (/\{/ || /\s/) {
			# It's got SQL stuff in it.
			s[\$\{(\w+)\.(\w+)\}][$data->{tables}{$1}{sql_alias}.'.'.$2]eg;
			s[\$\{(\w+)\}][$data->{main_table}{sql_alias}.'.'.$1]eg;
			$sqlcol_content = $_;
		}
		my $sqlcol;
		if (defined $sql_parse_data->{select_col_sql_lookup}{$sqlcol_content}) {
			# We've seen this column in this table already.
			$sqlcol = $sql_parse_data->{select_col_sql_lookup}{$sqlcol_content};
		} else {
			# New column. Add it to the list.
			$sqlcol = @{$sql_parse_data->{select_col_sql_array}};
			push @{$sql_parse_data->{select_col_sql_array}}, $sqlcol_content;
			$sql_parse_data->{select_col_sql_lookup}{$sqlcol_content} = $sqlcol;
		}
		push @{$data->{sql_columns}}, $sqlcol;
	}

	# If the column is not purely structural, slap the data onto the output columns list.
	if (!$col_type->{structural}) {
		push @{$sql_parse_data->{output_columns}}, $data;
	}
	return (1, $data);
}


BEGIN {
	%col_types = (
		clan => {
			tables => 'clans',
			title => "Clan",
			fulltitle => "Clans for Period",
			where => sub { "\${period_id} = ?", $c->period_info()->{id} },
			col_order => -2,
			description => "Virtual column to select clans for the given period.",
			structural => 1,
		},
		clan_name_web => {
			params => 'clan',
			tables => 'clans(0)',
			cols => [qw/id name url/],
			title => "Clan",
			fulltitle => "Clan name and web link",
			data => sub { $c->render_clan($_[0][0], $_[0][1]).($_[0][2] ? " (<a href=\"$_[0][2]\">web</a>)" : "") },
			STRING_SORT('$_[0][1]'),
		},
		clan_tag => {
			params => 'clan',
			tables => 'clans(0)',
			cols => [ qw/id tag/ ],
			title => "Tag",
			fulltitle => "Clan tag",
			data => sub { $c->render_clan($_[0][0], $_[0][1]) },
			STRING_SORT('$_[0][1]'),
		},
		clan_tag_bare => {
			params => 'clan',
			tables => 'clans(0)',
			cols => 'tag',
			title => "Tag",
			fulltitle => "Clan tag (no link)",
			STRING_FIELD(),
		},
		clan_description => {
			params => 'clan',
			tables => 'clans(0)',
			cols => "SUBSTRING_INDEX(\${looking},'\n',1)",
			title => "Description",
			fulltitle => "Clan description (first line)",
			STRING_FIELD(),
		},
		clan_forums => {
			params => 'clan',
			tables => 'clans(0)',
			cols => [qw/forum_id forum_private_id/],
			title => "Forum",
			fulltitle => "Clan forum links",
			init => sub { $persist = $c->is_clan_member },
			data => sub { ($_[0][0] ? "<a href=\"/forum/viewforum.php?f=$_[0]\">Public</a>" : "").($_[0][1] && $persist == $_[0][0] ? " / <a href=\"/forum/viewforum.php?f=$_[0][1]\">Private</a>" : "") },
		},
		join_member_clan_leader => {
			params => [ 'clan', 'member' ],
			tables => [ 'clans(0)', 'members(1)' ],
			where => {
				members => '${id} = ${clans.leader_id}'
			},
			title => "Leader Member",
			fulltitle => "Clan leader",
			description => "Virtual column to select clan leader for a clan.",
			structural => 1,
		},
		table_members => {
			tables => [ 'members' ],
			is_a => 'member',
			title => "Members",
			fulltitle => "Members Table",
			description => "Virtual column to select all members.",
			structural => 1,
		},
		table_members_outer => {
			tables => [ '[outer]members' ],
			is_a => 'member',
			title => "Members",
			fulltitle => "Members Table",
			description => "Virtual column to select all members (outer).",
			structural => 1,
		},
		join_members_by_clan => {
			params => [ 'clan', 'member' ],
			tables => [ 'clans(0)', 'members(1)' ],
			where => {
				members => '${clan_id} = ${clans.id}',
			},
			title => "Clan Members",
			fulltitle => "Clan Members",
			description => "Virtual column to limit to members in a clan.",
			structural => 1,
		},
		group_members_by_clan => {
			params => [ 'clan', 'member' ],
			tables => [ 'members(1)', 'clans(0)' ],
			group => {
				members => 'clan_id',
			},
			title => "Members Group",
			fulltitle => "Clan Members Grouping Clause",
			description => "Virtual column to group a member column by clan.",
			structural => 1,
		},
		filter_member_qualified => {
			params => 'member',
			tables => 'members(0)',
			where => '${played} + ${played_pure} >= 7',
			title => "Member Active",
			fulltitle => "Member is active filter",
			description => "Virtual column to filter to only members marked active.",
			structural => 1,
		},
		filter_member_active => {
			params => 'member',
			tables => 'members(0)',
			where => '${active} = 1',
			title => "Member Active",
			fulltitle => "Member is active filter",
			description => "Virtual column to filter to only members marked active.",
			structural => 1,
		},
		count => {
			params => '*',
			tables => '(0) table',
			cols => 'COUNT(DISTINCT ${id})',
			title => "Count",
			fulltitle => "Count of ids",
			description => "Counts the entries in a grouped table.",
			NUMERIC_TOTAL_FIELD(),
		},
		clan_members_active_qualified => {
			params => 'clan',
			tables => 'clans(0)',
			structure => [
				'table_members_outer members',
					'group_members_by_clan($0, members)',
					'join_members_by_clan($0, members)',
					'filter_member_active(members)',
				'table_members_outer members_qualified',
					'group_members_by_clan($0, members_qualified)',
					'join_members_by_clan($0, members_qualified)',
					'filter_member_active(members_qualified)',
					'filter_member_qualified(members_qualified)',
			],
			structure_tables => [ 'members(members)', 'members(members_qualified) members_qualified' ],
			cols => [ 'COUNT(DISTINCT ${members.id})', 'COUNT(DISTINCT ${members_qualified.id})' ],
			title => "Members (Qualified)",
			fulltitle => "Member Summary (Active/Qualified)",
			description => "Counts the active and qualified members of a clan.",
			pre_first => sub {
				$_ = {
					act => 0,
					qual => 0,
				};
			},
			data => sub {
				$_->{act} += $_[0][0];
				$_->{qual} += $_[0][1];
				"$_[0][0] ($_[0][1])"
			},
			final => sub { "$_->{act} ($_->{qual})" },
			NUMERIC_SORT(),
		},
		clan_members_active => {
			params => 'clan',
			tables => 'clans(0)',
			structure => [ 'table_members_outer members', 'group_members_by_clan($0, members)', 'join_members_by_clan($0, members)', 'filter_member_active(members)', '<title=Active Members>count(members)' ],
			title => "Members",
			fulltitle => "Member Summary (Active)",
			description => "Counts the members in a clan.",
			NUMERIC_TOTAL_FIELD(),
		},
		clan_leader => {
			params => 'clan',
			tables => 'clans(0)',
			structure => [ 'table_members leader', 'join_member_clan_leader($0, leader)', '<title=Leader>member_name(leader)' ],
			title => "Leader",
			fulltitle => "Clan Leader",
			description => "Gets the leader for each clan.",
			structural => 1,
		},
		member_name => {
			params => 'member',
			tables => 'members(0)',
			cols => [qw/id name rank/],
			title => "Member",
			fulltitle => "Member Name",
			data => sub { $c->render_member($_[0][0], $_[0][1], $_[0][2]) },
			STRING_SORT('$_[0][1]'),
		},
		clan_points => {
			params => 'clan',
			tables => 'clans(0)',
			cols => 'points',
			title => "Points",
			fulltitle => 'Points accrued by clan this period.',
			NUMERIC_TOTAL_FIELD(),
		},
		clan_games_summary => {
			params => 'clan',
			tables => 'clans(0)',
			structure => [
				'table_members_outer members',
					'group_members_by_clan($0, members)',
					'join_members_by_clan($0, members)',
			],
			cols => [ 'SUM(${members.played})', 'SUM(${members.played_pure})' ],
			title => "Games (Pure)",
			fulltitle => 'Clan: Summary of games played this period',
			pre_first => sub {
				$_ = {
					norm => 0,
					pure => 0,
				};
			},
			data => sub {
				$_->{norm} += $_[0][0];
				$_->{pure} += $_[0][1] / 2;
				"$_[0][0] ($_[0][1])"
			},
			final => sub { "".($_->{norm}-$_->{pure})." (".$_->{pure}.")" },
			NUMERIC_SORT(),
		},
		clan_games_overall => {
			params => 'clan',
			tables => 'clans(0)',
			structure => [
				'table_members_outer members',
					'group_members_by_clan($0, members)',
					'join_members_by_clan($0, members)',
			],
			cols => [ 'SUM(${members.played})', 'SUM(${members.played_pure})' ],
			title => "Games",
			fulltitle => 'Clan: All games played this period',
			pre_first => sub {
				$_ = {
					norm => 0,
					pure => 0,
				};
			},
			data => sub {
				$_->{norm} += $_[0][0];
				$_->{pure} += $_[0][1] / 2;
				"$_[0][0]"
			},
			final => sub { "".($_->{norm}-$_->{pure}) },
			NUMERIC_SORT(),
		},
		clan_games_pure => {
			params => 'clan',
			tables => 'clans(0)',
			structure => [
				'table_members_outer members',
					'group_members_by_clan($0, members)',
					'join_members_by_clan($0, members)',
			],
			cols => [ 'SUM(${members.played})', 'SUM(${members.played_pure})' ],
			title => "Games",
			fulltitle => 'Clan: All games played this period',
			pre_first => sub {
				$_ = {
					pure => 0,
				};
			},
			data => sub {
				$_->{pure} += $_[0][0] / 2;
				"$_[0][0]"
			},
			final => sub { $_->{pure} },
			NUMERIC_SORT(),
		},
		clan_games_average_summary => {
			params => [ 'clan', 'members' ],
			tables => [ 'clans(0)', 'members(1)' ],
			structure => [
				'table_members_outer members',
					'group_members_by_clan($0, members)',
					'join_members_by_clan($0, members)',
			],
			cols => [ 'SUM(${members.played})', 'SUM(${members.played_pure})', 'COUNT(members.id)' ],
			title => "Games (Pure)",
			fulltitle => 'Clan: Summary of games played this period',
			pre_first => sub {
				$_ = {
					norm => 0,
					pure => 0,
				};
			},
			data => sub {
				$_->{norm} += $_[0][0];
				$_->{pure} += $_[0][1] / 2;
				"$_[0][0] ($_[0][1])"
			},
			final => sub { "".($_->{norm}-$_->{pure})." (".$_->{pure}.")" },
			NUMERIC_SORT(),
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
	);
}
1;
# LOL TODO
__DATA__
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
		ROWINIT => {
			sqlcols => [qw/clans.got100time/],
			joins => [ "  LEFT OUTER JOIN members mall ON mall.clan_id = clans.id",
			           "LEFT OUTER JOIN members ON clans.leader_id = members.id" ], # Ensure this happens
			init => sub { },
			class => sub { $_[0] ? " class=\"qualified\"" : "" },
		}
		ROWINIT => {
			sqlcols => [ qw/members.played members.played_pure/ ],
			joins => [ "  INNER JOIN clans ON clans.id = members.clan_id" ], # Ensure this happens
			init => sub { },
			class => sub { $_[0] + $_[1] >= $reqpoints ? " class=\"qualified\"" : "" },
		},

