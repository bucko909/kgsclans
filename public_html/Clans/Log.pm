package Clans;

sub get_log_lines_period {
	&Clans::Log::get_log_lines($_[0], 'period_id', @_[1..$#_]);
}

sub get_log_line {
	&Clans::Log::get_log_line($_[0], @_[1..$#_]);
}

sub get_log_lines_clan {
	&Clans::Log::get_log_lines($_[0], 'clan_id', @_[1..$#_]);
}

sub get_log_lines_team {
	&Clans::Log::get_log_lines($_[0], 'team_id', @_[1..$#_]);
}

sub get_log_lines_member {
	&Clans::Log::get_log_lines($_[0], 'member_id', @_[1..$#_]);
}

sub format_log_lines_debug {
	&Clans::Log::format_log_lines_debug(@_);
}

sub format_log_lines {
	&Clans::Log::format_log_lines(@_);
}

package Clans::Log;
use Clans;
use strict;
use warnings;
use POSIX qw/strftime/;
our (%forms, %input_tests);

sub get_log_line {
	my ($c, $id) = @_;
	my $result = $c->db_select("SELECT log.id, action, status, message, log.user_id, username, time FROM log INNER JOIN phpbb3_users ON phpbb3_users.user_id = log.user_id WHERE log.id = ?", {}, $id);
	return unless $result && @$result;
	my $line = $result->[0];
	my $params = $c->db_select("SELECT log_id, param_name, param_value FROM log_params WHERE log_id = ?", {}, $id);
	$line->[7] = {};
	for (@$params) {
		$line->[7]{$_->[1]} = $_->[2];
	}
	return $line;
}

sub get_log_lines {
	my ($c, $pname, $pvalue, $start, $count) = @_;
	$start ||= 0;
	$count ||= 200;
	my $result = $c->db_select("SELECT log.id, action, status, message, log.user_id, username, time FROM log INNER JOIN phpbb3_users ON phpbb3_users.user_id = log.user_id INNER JOIN log_params ON log.id = log_params.log_id WHERE log_params.param_name = ? AND log_params.param_value = ? ORDER BY time DESC LIMIT ?, ?", {}, $pname, $pvalue, $start, $count);
	my %indices;
	for (0..$#$result) {
		$indices{$result->[$_][0]} = $_;
	}
	my $ids = join(',', map { $_->[0] } @$result);
	my $params = $c->db_select("SELECT log_id, param_name, IF(LENGTH(param_value)>47,CONCAT(LEFT(param_value,47),'...'),param_value) FROM log_params WHERE log_id IN ($ids)");
	for (@$params) {
		$result->[$indices{$_->[0]}][7] ||= {};
		$result->[$indices{$_->[0]}][7]{$_->[1]} = $_->[2];
	}
	return $result;
}

sub get_format {
	my ($c, $name) = @_;
	$c->{formats} ||= {};
	return $c->{formats}{$name} if $c->{formats}{$name};
	return $c->{formats}{$name} = $c->db_selectone("SELECT format FROM log_formats WHERE action = ?", {}, $name);
}

sub format_log_lines {
	my ($c, $lines, $cols, $private) = @_;
	my $output = '<table>';
	$output .= qq|<tr><th>Debug</th><th>Forum User</th><th>Time</th>|;
	for(@$cols) {
		$output .= qq|<th>|;
		if ($_ eq 'period') {
			$output .= 'Period';
		} elsif ($_ eq 'clan') {
			$output .= 'Clan';
		} elsif ($_ eq 'member') {
			$output .= 'Member';
		} elsif ($_ eq 'team') {
			$output .= 'Team';
		}
		$output .= qq|</th>|;
	}
	$output .= "</tr>";
	foreach my $line (@$lines) {
		my $format = &get_format($c, $line->[1]) || "Unknown action: $line->[1]";
		$output .= qq|<tr>|;
		$output .= qq|<td>|.(!$private && $format =~ /{/ ? $line->[0] : qq|<a href="/log.pl?log_id=$line->[0]">$line->[0]</a>|).qq|</td>|;
		$output .= qq|<td>$line->[5]</td>|;
		$output .= qq|<td>|.strftime("%c", localtime $line->[6]).qq|</td>|;
		for(@$cols) {
			$output .= qq|<td>|;
			if ($_ eq 'period') {
				$output .= $line->[7]{period_id} || '';
			} elsif ($_ eq 'clan') {
				#$output .= $line->[7]{clan_id} && $format !~ /\%clan/ ? $c->render_clan($line->[7]{clan_id}, $line->[7]{clan_name}) : '';
				$output .= $line->[7]{clan_id} && $format !~ /\%clan/ ? $line->[7]{clan_name} : '';
			} elsif ($_ eq 'member') {
				#$output .= $line->[7]{member_id} && $format !~ /\%member/ ? $c->render_member($line->[7]{member_id}, $line->[7]{member_name}) : '';
				$output .= $line->[7]{member_id} && $format !~ /\%member/ ? $line->[7]{member_name} : '';
			} elsif ($_ eq 'team') {
				$output .= $line->[7]{team_id} && $format !~ /\%team/ ? $line->[7]{team_name} : '';
			}
			$output .= qq|</td>|;
		}
		# Remove [ %var% ] if var is not set.
		$format =~ s/\[.*?%(.*?)%.*?\]/$line->[7]{$2}?$&:''/eg;

		# Expand vars.
		$format =~ s/%(.*?)%/$line->[7]{$1}||"NULL"/eg;

		# Remove private chunks.
		if (!$private) {
			$format =~ s/{.*?}//g;
		} else {
			$format =~ s/[{}]//g;
		}
		$output .= qq|<td>$format</td>|;
		$output .= qq|</tr>|;
	}
	$output .= "</table>";
	return $output;
}

sub format_log_lines_debug {
	my ($c, $lines) = @_;
	my $output = '<table>';
	foreach my $line (@$lines) {
		$output .= qq|<tr><td>$line->[1]</td><td>$line->[2]</td><td>$line->[3]</td><td>$line->[5]</td><td>|;
		$output .= qq|<ul>|.join('', map { defined $line->[6]{$_} ? qq|<li>$_ = $line->[6]{$_}</li>| : qq|<li>$_ = NULL</li>| } keys %{$line->[6]}).qq|</ul>|;
		$output .= qq|</td></tr>|;
	}
	$output .= "</table>";
	return $output;
}

1;
