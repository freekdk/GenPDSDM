#!/bin/bash
# insert DKIM test email message in submission port 587
# after that inspect the recieved message for presence of a DKIM item in the header
#
echo "Script to test generation of DKIM item in outgoing email via submission port 587"
echo "It needs the domain name you used to generate the DKIM certificate,"
echo "the user name of a user on this system and its password. You will be prompted"
echo "for these values. The password will not be visible. The destination of the"
echo "message is the user where messages for root are directed to."
echo "The first paramter $1 replaces locahost:587 by the value the connection goes to."
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
date=$(date --date=now "+%a, %d %b %Y %H:%M:%S %z")
openssl s_client -crlf -connect $dest_port -starttls smtp -quiet <<EOF 2> /dev/null 3>/dev/null
EHLO smtp.$domain
AUTH PLAIN $authbase64
mail from:<root@$domain>
rcpt to:<$dest>
data
Date: $date
From: root@$domain
To: root@localhost.$domain
Subject: test DKIM
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit

Test DKIM
.
QUIT
EOF
if [ $? -eq 0 ] ; then
    echo ""
    echo "Sending test message to root@localhost.$domain on ${dest_port%:*} succeeded."
    echo "Now look for the message in the folder ~/Maildir/new/ of the user, email for root is directed to."
    echo ""
    exit 1
else
    echo ""
    echo "Sending test message failed. Try \"telnet ${dest_port%:*} ${dest_port#*:}\" to see the problem"
    echo ""
fi
exit 0
