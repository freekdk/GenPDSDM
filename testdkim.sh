#!/bin/bash
# insert DKIM test email message in submission port 587
# after that inspect the recieved message for presence of a DKIM item in the header
#
echo "Script to test generation of DKIM item in outgoing email via submission port 587"
echo "It needs the domain name you used to generate the DKIM certificate,"
echo "the user name of a user on this system and its password. You will be prompted"
echo "for these values. The password will not be visible. The destination of the"
echo "message is the user where messages for root are directed to."
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
authbase64=$(echo -en "\0$username\0$password" | base64)
date=$(date --date=now "+%d %b %Y %H:%M:%S")
openssl s_client -connect localhost:587 -starttls smtp -quiet <<EOF
EHLO smtp.$domain
AUTH PLAIN $authbase64
mail from:<root@$domain>
rcpt to:<root@localhost.$domain>
data
Date: $datum
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
echo ""
echo "Now look for the message in the folder ~/Maildir/new/ of the user email for root is directed to."
echo ""
