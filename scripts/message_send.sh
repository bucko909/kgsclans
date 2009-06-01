#!/bin/bash
function wait_for_window() {
	name="$1"
	while sleep 1; do
		echo "$name"
		if xwininfo -wm -name "$name" > /dev/null 2> /dev/null; then
			break
		fi
	done
}
function cgoban_start() {
#	/home/kgs/scripts/xvfb java -jar /home/kgs/cgoban.jar 2> /dev/null > /dev/null &
	java -jar /home/kgs/cgoban.jar & #2> /dev/null > /dev/null &
	wait_for_window "CGoban: Main Window"
	sleep 1
}
function cgoban_exit() {
	main_id=$(xwininfo -children -name 'CGoban: Main Window'|grep xwininfo|sed 's/.*\(0x[0-9a-f]*\).*/\1/')
	xkill -id $main_id > /dev/null 2> /dev/null
}
function cgoban_login {
	xte 'key space' # Login->Login box
	wait_for_window "KGS: Log In"
	sleep 3
	xte 'key Return' # Username
	sleep 3
	xte 'key Return' # Password->Rooms list
	wait_for_window "KGS: Rooms"
	sleep 3
}
function cgoban_open_message() {
	menu=$(xwininfo -name 'KGS: Rooms'|perl -ne 'BEGIN{$y=10;$x=10}if(/Absolute upper-left Y:\s+(\d+)/){$y+=$1}if(/Absolute upper-left X:.*?(\d+)/){$x+=$1}END{print"$x $y\n"}')
	xte "mousemove $menu" # Select menu
	xte 'mouseclick 1'
	sleep 3
	xte 'key Right'
	xte 'key Right' # User menu
	xte 'key Up' # Leave message
	xte 'key Return' # -> Leave message
	wait_for_window "KGS: Leave Message"
	sleep 3
}
function xte_str() {
	str=$1
	echo "$str"|perl -ne '
		my $shift=0;
		my @out;
		my %conv = (
			"`" => "grave",
			"¬" => "shift|grave",
			"!" => "shift|1",
			"\"" => "shift|2",
			"£" => "shift|3",
			"\$" => "shift|4",
			"%" => "shift|5",
			"^" => "shift|6",
			"&" => "shift|7",
			"*" => "shift|8",
			"(" => "shift|9",
			")" => "shift|0",
			"-" => "minus",
			"_" => "shift|minus",
			"=" => "equal",
			"+" => "shift|equal",
			"[" => "bracketleft",
			"(" => "shift|bracketleft",
			"]" => "bracketright",
			")" => "shift|bracketright",
			";" => "semicolon",
			"'\''" => "apostrophe",
			"#" => "numbersign",
			"," => "comma",
			"." => "period",
			"/" => "slash",
			":" => "shift|semicolon",
			"@" => "shift|apostrophe",
			"~" => "shift|numbersign",
			"<" => "shift|comma",
			">" => "shift|period",
			"/" => "shift|slash",
			" " => "space",
			"\n" => "Return",
			"\r" => "Return",
		);
		for (split //) {
			my $needshift;
			my $key;
			if ($key = $conv{$_}) {
				$needshift = 1 if $key =~ s/shift\|//;
			} elsif (/[a-zA-Z0-9]/) {
				$key = $_;
				$needshift = 1 if ord $key >= ord("A") && ord $key <= ord("Z");
				$key = lc $key;
			}
			if ($needshift && !$shift) {
				$shift = 1;
				push @out, "keydown Shift_L";
			} elsif ($shift && !$needshift) {
				push @out, "keyup Shift_L";
				undef $shift;
			}
			push @out, "key $key";
		}
		if ($shift) {
			push @out, "keyup Shift_L";
		}
		print join("\n",@out)."\n";
		system("/usr/bin/xte", @out);
	'
}
function cgoban_enter_message() {
	to="$1"
	message="$2"
	xte 'key Tab' # Select username box
	sleep 3
	xte_str "$to" # username
	sleep 3
	xte_str "$message" # message
	sleep 10
	button=$(xwininfo -name 'KGS: Leave Message'|perl -ne 'BEGIN{$y=-10;$x=10}if(/Absolute upper-left Y:\s+(\d+)/||/Height:\s+(\d+)/){$y+=$1}if(/Absolute upper-left X:.*?(\d+)/){$x+=$1}END{print"$x $y\n"}')
	xte "mousemove $button"
	xte 'mouseclick 1'
	sleep 3
}
function xte() {
	echo "xte: $1"
	/usr/bin/xte "$1"
}
cgoban_start
xmodmap /home/kgs/.xmodmap
cgoban_login
count=0
while [ $count -le 5 ]; do
	if mysql -Nsre 'SELECT username FROM message_queue LIMIT 1; SELECT message FROM message_queue LIMIT 1;' | (
		read to
		if [ -z "$to" ]; then
			exit 1
		fi
		message="$(cat)"
		echo "To: $to"
		echo "$message"
		cgoban_open_message
		cgoban_enter_message "$to" "$message"
		mysql -Nsre 'DELETE FROM message_queue LIMIT 1;'
	) then
		count=0
	else
		sleep 10
		count=$(expr $count + 1)
	fi
done
cgoban_exit
