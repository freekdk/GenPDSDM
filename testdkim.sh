#!/bin/bash
# insert DKIM test email message in submission port 587
#
echo "Script to test an outgoing email via submission port 587 to specified server"
echo "The following items will be asked for:"
echo "The email from address, the email destination address, the server,"
echo "the user name of a user on this server and its password."
echo
echo -n "From address: "
read from
echo
echo -n "Destination address: "
read dest
echo
echo -n "Name of server: "
read server
dest_port="$server:587"
echo
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
echo
echo "mailx -v -S smtp-use-starttls -S smtp=$dest_port -S smtp-auth=plain -S smtp-auth-password=$password -S smtp-auth-user=$username -S ssl-ca-file=/etc/postfix/ssl/cacert.pem -s testmessage -r $from $dest <<EOF"
mailx -v -S smtp-use-starttls -S smtp=$dest_port -S smtp-auth=plain -S smtp-auth-password=$password -S smtp-auth-user=$username -S ssl-ca-file=/etc/postfix/ssl/cacert.pem -S ssl-verify=ignore -s testmessage -r $from $dest <<EOF
Test message
EOF
if [ $? -eq 0 ] ; then
    echo ""
    echo "Sending test message to $dest via ${dest_port%:*} succeeded."
    echo ""
    exit 1
else
    echo ""
    echo "Sending test message failed. Try \"telnet ${dest_port%:*} ${dest_port#*:}\" to see the problem"
    echo ""
fi
exit 0
