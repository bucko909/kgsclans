package Clans;

sub get_log_lines_period {
	&Clans::Log::get_log_lines($_[0], 'period_id', @_[1..$#_]);
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

package Clans::Log;
use Clans;
use strict;
use warnings;
our (%forms, %input_tests);

sub get_log_lines {
	my ($c, $pname, $pvalue) = @_;
	my $result = $c->db_select("SELECT log.id, action, status, message, log.user_id, username FROM log INNER JOIN phpbb3_users ON phpbb3_users.user_id = log.user_id INNER JOIN log_params ON log.id = log_params.log_id WHERE log_params.param_name = ? AND log_params.param_value = ? ORDER BY time DESC LIMIT 200", {}, $pname, $pvalue);
	my %indices;
	for (0..$#$result) {
		$indices{$result->[$_][0]} = $_;
	}
	my $ids = join(',', map { $_->[0] } @$result);
	my $params = $c->db_select("SELECT log_id, param_name, param_value FROM log_params WHERE log_id IN ($ids)");
	for (@$params) {
		$result->[$indices{$_->[0]}][6] ||= {};
		$result->[$indices{$_->[0]}][6]{$_->[1]} = $_->[2];
	}
	return $result;
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
