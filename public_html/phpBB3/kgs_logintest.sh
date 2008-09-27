#!/bin/bash
tmp=$(tempfile);
wget http://www.gokgs.com/membership.jsp -O /dev/null -q --save-cookies=$tmp --keep-session-cookies
r=1
if wget --no-check-certificate -q https://www.gokgs.com/login.jsp --post-data="user=$1&password=$2" -O - --load-cookies=$tmp --keep-session-cookies | grep -q 'logged in as'; then
	r=0
fi
rm $tmp
echo $r
exit $r
