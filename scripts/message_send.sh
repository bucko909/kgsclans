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
	sleep 1
	xte 'key Return' # Username
	sleep 1
	xte 'key Return' # Password->Rooms list
	wait_for_window "KGS: Rooms"
	sleep 1
}
function cgoban_open_message() {
	menu=$(xwininfo -name 'KGS: Rooms'|perl -ne 'BEGIN{$y=10;$x=10}if(/Absolute upper-left Y:\s+(\d+)/){$y+=$1}if(/Absolute upper-left X:.*?(\d+)/){$x+=$1}END{print"$x $y\n"}')
	xte "mousemove $menu" # Select menu
	xte 'mouseclick 1'
	sleep 1
	xte 'key Right'
	xte 'key Right' # User menu
	xte 'key Up' # Leave message
	xte 'key Return' # -> Leave message
	wait_for_window "KGS: Leave Message"
	sleep 1
}
function xte_str() {
	str=$1
	echo "$str"|perl -ne '@a=map { s/ /space/g; s/\./period/g; s/,/comma/g; s/;/semicolon/g; s/:/colon/g; s/-/minus/g; s/\(/parenleft/g; s/\)/parenright/g; s|/|slash|g; s/!/exclam/g; s/"/quotedbl/g; s/'\''/apostrophe/g; s/[\n\r]/Return/; /[A-Z]|exc|paren|quote/?("keydown Shift_L","key $_","keyup Shift_L"):("key $_") } split //;system("/usr/bin/xte", @a);'
	echo "$str"|perl -ne '@a=map { s/ /space/g; s/\./period/g; s/,/comma/g; s/;/semicolon/g; s/:/colon/g; s/-/minus/g; s/\(/parenleft/g; s/\)/parenright/g; s|/|slash|g; s/!/exclam/g; s/"/quotedbl/g; s/'\''/apostrophe/g; s/[\n\r]/Return/; /[A-Z]|exc|paren|quote/?("keydown Shift_L","key $_","keyup Shift_L"):("key $_") } split //;print "@a\n";'
}
function cgoban_enter_message() {
	to="$1"
	message="$2"
	xte 'key Tab' # Select username box
	sleep 1
	xte_str "$to" # username
	sleep 1
	xte_str "$message" # message
	sleep 1
	button=$(xwininfo -name 'KGS: Leave Message'|perl -ne 'BEGIN{$y=-10;$x=10}if(/Absolute upper-left Y:\s+(\d+)/||/Height:\s+(\d+)/){$y+=$1}if(/Absolute upper-left X:.*?(\d+)/){$x+=$1}END{print"$x $y\n"}')
	xte "mousemove $button"
	xte 'mouseclick 1'
	sleep 1
}
function xte() {
	echo "xte: $1"
	/usr/bin/xte "$1"
}
cgoban_start
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
