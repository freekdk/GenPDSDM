#!/bin/bash
# insert DKIM test email message in submission port 587
# after that inspect the recieved message for presence of a DKIM item in the header
#
if [ ! -x /usr/bin/expect ] ; then
    grep opensuse /etc/os-
    if [ $? -eq 0 ] ; then
	sudo zypper in expect
    else
	apt install expect
    fi
fi
echo "Script to test generation of DKIM item in outgoing email via submission port 587"
echo "It needs the domain name you used to generate the DKIM certificate,"
echo "the user name of a user on this system and its password. You will be prompted"
echo "for these values. The password will not be visible. The destination of the"
echo "message is the user where messages for root are directed to."
echo "The first paramter \"$1\" replaces localhost:587 by the value the connection goes to."
echo "The second parameter \"$2\" replaces the To email address root@localhost.<domain>"
dest_port="localhost:587"
[ "$1" != "" ] && dest_port="$1"
echo ""
echo "==================="
echo ""
echo -n "Enter the domain name: "
read domain
echo ""
echo -n "Enter the user name: "
read username
echo
unset password
prompt="Enter Password: "
while IFS= read -p "$prompt" -r -s -n 1 char
do
    if [[ $char == $'\0' ]]
    then
        break
    fi
    prompt='*'
    password+="$char"
done
echo ""
dest="root@localhost.$domain"
[ "$2" != "" ] && dest="$2"
authbase64=$(echo -en "\0$username\0$password" | base64)
date=$(LC_ALL=C date --date=now "+%a, %d %b %Y %H:%M:%S %z")
echo ${0%/*} $(ls ${0%/*}/testdkim.*)
${0%/*}/testdkim.exp "$dest_port" "root@$domain" "$dest" "$authbase64" "$date"
if [ $? -eq 0 ] ; then
    echo ""
    echo "Sending test message to $dest via ${dest_port%:*} succeeded."
    echo "Now look for the message in the folder ~/Maildir/new/ of the user, email for root is directed to."
    echo ""
    exit 1
else
    echo ""
    echo "Sending test message failed. Try \"telnet ${dest_port%:*} ${dest_port#*:}\" to see the problem"
    echo ""
fi
exit 0
