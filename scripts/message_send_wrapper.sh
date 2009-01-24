#!/bin/sh
if ! [ -e /home/kgs/messages_running.lock ]; then
	touch /home/kgs/messages_running.lock
	cd /home/kgs/scripts
	./xvfb ./message_send.sh > /dev/null 2> /dev/null
	rm /home/kgs/messages_running.lock
fi
