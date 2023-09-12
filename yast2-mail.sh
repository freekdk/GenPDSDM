#!/bin/bash
#
#***************************************************************************
#
# Copyright (c) 2023 Freek de Kruijf
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 or later of the GNU General Public
# License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
#**************************************************************************
#
# Script to do what a new version of yast2 mail should do to generate a
# system with postfix, dovecot, amavis to support SPF, DKIM and DMARC.
# It is should enhance the old version version of yast2 mail, but keep
# the the previous capabilities untouched.
#
# As with the old version, this module only generates the file /etc/sysconfig/mail
# which will be used by /etc/sbin/config.postfix to generate new versions of
# /etc/postfix.{main,master}.cf. However it will also generate new versions of
# several files in /etc/postfix/, which are used in the new versions of
# {main,master}.cf.
# After running this script, /usr/sbin/config.postfix should be run
#
# Version history
# Version 1.0 Version for openSUSE Leap 15.5 on Raspberry Pi 4B
#
# this script should be run as user root
#
id | tr "a-z" "A-Z" | egrep -q '^UID=0'
[ $? -ne 0 ] && echo "This script should be executed by root or sudo $0" && exit 1
#
bold=$(tput bold)
offbold=$(tput sgr0)
#
# function set parameter in /etc/sysconfig/postfix
#
setpar()
{
    grep -q -E "^${1}=" /etc/sysconfig/postfix
    if [ $? -ne 0 ] ; then
	echo "Unknown parameter ${1}= in /etc/sysconfig/postfix"
	exit 1
    fi
    sed -i /^${1}=/c\
"${1}=\"${2}\"" /etc/sysconfig/postfix
}
#
# function set parameter in /etc/sysconfig/mail
#
setparm()
{
    grep -q -E "^${1}=" /etc/sysconfig/mail
    if [ $? -ne 0 ] ; then
	echo "Unknown parameter ${1}= in /etc/sysconfig/mail"
	exit 1
    fi
    sed -i /^${1}=/c\
${1}=\"${2}\" /etc/sysconfig/mail
}
#
# function set parameter in /etc/sysconfig/amavis
#
setpara()
{
    grep -q -E "^${1}=" /etc/sysconfig/amavis
    if [ $? -ne 0 ] ; then
	echo "Unknown parameter ${1}= in /etc/sysconfig/amavis"
	exit 1
    fi
    sed -i /^${1}=/c\
${1}=\"${2}\" /etc/sysconfig/amavis
}
#
# function ask yes or no return 0 is yes (default) otherwise no
#
yesorno()
{
    while true
    do
	echo -n "Enter ${bold}Y${offbold}[es] or n[o] : "
	read answw
	[ ${#answw} -eq 0 ] && answw=Y
	answw=${answw:0:1}
	case $answw in
	    "y"|"Y" )
		    return 0
		    ;;
	    "n"|"N" )
		    return 1
		    ;;
	    *       )
		    ;;
	esac
    done
}
#
# Start of the main program
#
# Source /etc/sysconfig/postfix
#
[ -f /etc/sysconfig/postfix ] && source /etc/sysconfig/postfix
[ -f /etc/sysconfig/mail ] && source /etc/sysconfig/mail
[ -f /etc/sysconfig/amavis ] && source /etc/sysconfig/amavis
#
# Which MTA?
#
[ -f /etc/sendmail.cf ] && isendmail="i"
[ -f /etc/postfix/main.cf ] && ipostfix="i"
if [ "$isendmail" != "i" -a "$ipostfix" != "i" ] ; then
    echo "postfix or sendmail has not been installed."
    while true ; do
        echo -n "Please enter P or S to install one of these : "
	read answ
	answ=${answ:0:1}
	case $answ in
	    "P"|"p" )
		    zypper in -y postfix
		    ipostfix="i"
		    break
		    ;;
	    "S"|"s" )
		    break
		    ;;
	    *       ) echo "Please enter the proper character" ;;
	 esac
    done
else
    [ "${ipostfix}" = "i" ] && cat <<EOF
=================================
= We will continue with Postfix =
=================================
EOF
    [ "${isendmail}" = "i" ] && cat <<EOF
==================================
= We will continue with Sendmail =
==================================
EOF
fi
echo ""
echo "===================="
echo "= General settings ="
echo "===================="
echo "Connection type for email server"
echo "There are four options for this type"
echo "${bold}P${offbold}ermanent, ${bold}D${offbold}ial-up, No ${bold}c${offbold}onnection or D${bold}o${offbold} not start as Daemon"
while true
do
    echo -n "Enter P, D, c or o : "
    read answ
    answ=${answ:0:1}
    case $answ in
	"p"|"P" ) CONTYPE=Permanent
	          break	;;
	"d"|"D" ) CONTYPE=Dial-up
	          break	;;
	"c"|"C" ) CONTYPE=NoConnection
	          break	;;
	"o"|"O" ) CONTYPE=NoStartDaemon
	          break	;;
	*	) echo "Please enter the proper character" ;;
    esac
done
if [ "$CONTYPE" != "Permanent" -a "$CONTYPE" != "Dial-up" ] ; then
    setpar POSTFIX_NODNS yes
    POSTFIX_NODNS="yes"
else
    setpar POSTFIX_NODNS no
    POSTFIX_NODNS="no"
fi
#
# This script now continues only in case CONTYPE is Permanent and with Postfix
#
if [ "$CONTYPE" != "Permanent" -a "${ipostfix}" != "i" ] ; then
    echo "This script covers only the Permanent connection type and only Postfix"
    echo "Exiting..."
    exit
fi
echo "A null client is a machine that can only send mail. It receives no"
echo "mail from the network, and it does not deliver any mail locally."
echo "It will send locally submitted messages onto the relayhost."
if [ "$POSTFIX_NULLCLIENT" = "no" ] ; then
    echo "Currently you did NOT configure a nullclient type postfix."
    echo "Is this OK?"
    yesorno
    if [ $? -eq 1 ] ; then
	setpar POSTFIX_NULLCLIENT yes
	POSTFIX_NULLCLIENT="yes"
    else
	setpar POSTFIX_NULLCLIENT no
	POSTFIX_NULLCLIENT="no"
    fi
else
    echo "Currently you did configure a nullclient type postfix"
    echo "Is this OK?"
    yesorno
    if [ $? -eq 1 ] ; then
	setpar POSTFIX_NULLCLIENT no
	POSTFIX_NULLCLIENT="no"
    else
	setpar POSTFIX_NULLCLIENT yes
	POSTFIX_NULLCLIENT="yes"
    fi
fi
#
# Configuration of relayhost
#
change=0
changeup=0
# value 1 means no change
rhost="$POSTFIX_RELAYHOST"
if [ ${#rhost} -ne 0 ] ; then
    # remove possible port and square brackets
    port=${rhost##*:}
    [ "$port" = "$rhost" ] && port=""
    [ "$port" != "" ] && rhost=${rhost%:*}
    rhost=${rhost#*[}
    rhost=${rhost%]*}
    userpass=$(grep "$rhost" /etc/postfix/sasl_passwd | tr "\t" " ")
    if [ ${#userpass} -ne 0 ] ; then
	relayhost=${userpass%% *}
	userpass=${userpass##* }
	user=${userpass%:*}
	passw=${userpass#*:}
	if [ "$POSTFIX_RELAYHOST" = "$relayhost" -a ${#user} -ne 0 -a ${#passw} -ne 0 ] ; then
	    changeup=1
	fi
    fi
    if [ $change -eq 0 ] ; then
	if [ ${#port} -eq 0 ] ; then
	    echo "Currently you want outgoing email to relayhost: ${bold}${rhost}${offbold}"
	else
	    echo "Currently you want outgoing email to relayhost: ${bold}${rhost}:$port${offbold}"
	fi
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1
    fi
    if [ $changeup -ne 0 ] ; then
	echo "Username and password may be in /etc/postfix/sasl_passwd and possibly are: ${bold}$user : $passw${offbold}"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && changeup=1
    fi
fi
if [ $change -eq 0 ] ; then
    if [ ${#rhost} -eq 0 ] ; then 
	echo 'Do you want outgoing email to a relayhost (the server of your provider)?'
	yesorno
	answ=$?
    else
	if [ ${#port} -eq 0 ] ; then
	    echo "Currently your relayhost is ${bold}$rhost${offbold}"
	else
	    echo "Currently your relayhost is ${bold}$rhost:$port${offbold}"
	fi
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && answ=1 || answ=0
    fi
    if [ $answ -eq 0 ] ; then
	while true
	do
	    echo "Enter the name of the relayhost and the entry port like :"
	    echo -n '(maybe :port is not necessary) smtp.provider.tlp:port : '
	    read answ
	    rhost=${answ%:*}
	    port=${answ#*:}
	    [ "$port" = "$rhost" ] && port=""
	    [ ! -f /usr/bin/nslookup ] && zypper in -y bind-utils
	    if [ $(nslookup ${rhost} | grep 'Address:' | wc -l) -eq 1 ] ; then
		echo "The IP address of ${rhost} does not seem to exist"
		echo "It may currenly not be available, but check your input"
		echo -n "Current value ${rhost}"
		[ ${#port} -ne 0 ] && echo ":$port OK?" || echo " OK?"
		yesorno
		[ $? -eq 0 ] && break
	    else
		break
	    fi
	done
    fi
    if [ "${POSTFIX_RELAYHOST:0:1}" = "[" ] ; then
	echo "Currently postfix will NOT lookup the MX record of ${bold}${rhost}${offbold}"
	echo "Is this OK?"
	yesorno
	if [ $? -ne 0 ] ; then
	    par="[${rhost}]"
	    [ ${#port} -ne 0 ] && par="${par}:$port"
	else
	    par="${rhost}:$port"
	    [ ${#port} -ne 0 ] && par="${par}:$port"
	fi
    else
	echo "Should postfix lookup the MX record of ${bold}$rhost${offbold}."
	yesorno
	if [ $? -ne 0 ] ; then
	    par="[${rhost}]"
	    [ ${#port} -ne 0 ] && par="${par}:$port"
	else
	    par="${rhost}"
	    [ ${#port} -ne 0 ] && par="${par}:$port"
	fi
    fi
    setpar POSTFIX_RELAYHOST "$par"
    POSTFIX_RELAYHOST="$par"
    if [ $changeup -eq 0 ] ; then
	while true
	do
	    echo -n "Enter the username for access to $rhost, often an email address : "
	    read answ
	    [ ${#answ} -eq 0 ] && echo "Username can not be an empty string" && continue
	    echo -n "Enter the password for access to $rhost : "
	    read passw
	    [ ${#passw} -eq 0 ] && echo "Password can not be an emptystring" && continue
	    grep "$rhost" /etc/postfix/sasl_passwd | grep -q "$port"
	    [ $? -eq 0 ] && sed -i "/$rhost/d" /etc/postfix/sasl_passwd
	    echo "$par	${answ}:$passw" >> /etc/postfix/sasl_passwd
	    break
	done
	setpar POSTFIX_SMTP_AUTH yes
	POSTFIX_SMTP_AUTH="yes"
    fi
fi
if [ ${#POSTFIX_RELAYHOST} -ne 0 ] ; then
    if [ "$POSTFIX_SMTP_TLS_CLIENT" = "no" ] ; then
	echo "Currently outgoing email will ${bold}not${offbold} be encrypted"
    elif [ "$POSTFIX_SMTP_TLS_CLIENT" = "may" ] ; then
	echo "Currently outgoing email ${bold}will be tried${offbold} to be encrypted"
    else
	echo "Currently outgoing email ${bold}must${offbold} be encrypted"
    fi
    echo "Is this OK?"
    yesorno
    if [ $? -ne 0 ] ; then
	echo "Three posibilities: No, If possible, or Always. If possible is recommended."
	echo "Your choice is: No?"
	yesorno
	if [ $? -eq 0 ] ; then
	    setpar POSTFIX_SMTP_AUTH no
	    POSTFIX_SMTP_AUTH="no"
	    setpar POSTFIX_SMTP_TLS_CLIENT no
	    POSTFIX_SMTP_TLS_CLIENT="no"
	else
	    echo "Your choice is: If possible?"
	    yesorno
	    if [ $? -eq 0 ] ; then
		setpar POSTFIX_SMTP_AUTH yes
		POSTFIX_SMTP_AUTH="yes"
		setpar POSTFIX_SMTP_TLS_CLIENT may
		POSTFIX_SMTP_TLS_CLIENT="may"
	    else
		echo "So your choice is: Always."
		setpar POSTFIX_SMTP_AUTH yes
		POSTFIX_SMTP_AUTH="yes"
		 setpar POSTFIX_SMTP_TLS_CLIENT yes
		 POSTFIX_SMTP_TLS_CLIENT="yes"
	    fi
	fi
    fi
fi
if [ "$SMTPD_LISTEN_REMOTE" = "no" ] ; then
    echo "Currently remote access to your incoming port 25 is not enabled."
    [ "$POSTFIX_NULLCLIENT" = "yes" ] && echo "Postfix is configured as a nullclient, which is consistent with the current state."
    [ "$USE_AMAVIS" = "yes" ] && echo "AMaVis is enabled, which is not consistent with the current state."
    echo "Do you want access enabled? This means that other parameters will be made consistent."
    yesorno
    if [ $? -eq 0 ] ; then
	setparm SMTPD_LISTEN_REMOTE yes
	SMTPD_LISTEN_REMOTE="yes"
	setpar POSTFIX_NULLCLIENT no
	POSTFIX_NULLCLIENT="no"
    fi
else
    echo "Currently remote access to your incoming port 25 is enabled."
    [ "$USE_AMAVIS" = "no" ] && echo "Also AMaVis should be enabled!!!"
    [ "$POSTFIX_NULLCLIENT" = "yes" ] && echo "Postfix is configured as a nullclient, which is inconsistent with current state."
    echo "Is this OK?"
    yesorno
    if [ $? -ne 0 ] ; then
	setparm SMTPD_LISTEN_REMOTE no
	SMTPD_LISTEN_REMOTE="no"
	[ "$USE_AMAVIS" = "yes" ] && echo "Keeping AMaVis enabled makes no sense!!!"
    else
	setparm SMTPD_LISTEN_REMOTE yes
	SMTPD_LISTEN_REMOTE="yes"
    fi
fi
if [ -n "$USE_AMAVIS" -a "$USE_AMAVIS" = "yes" ] ; then
    echo "Currently virus scanning with AMaVis is enabled."
    [ "$SMTPD_LISTEN_REMOTE" = "no" ] && echo "However you are not listening to remote servers."
else
    echo "Currently virus scanning with AMaVis is not enabled"
    [ "$SMTPD_LISTEN_REMOTE" = "yes" ] && echo "However it is recommended to use this when listening to remote servers."
fi
echo "Is this OK?"
yesorno
if [ $? -ne 0 ] ; then
    if [ -z "$USE_AMAVIS" -o "$USE_AMAVIS" = "no" ] ; then
	if [ ! -f /etc/amavisd.conf ] ; then
	    echo "AMaVis and corresponding packages will be installed"
	    zypper in -y amavisd-new spamassassin clamav clzip rzip melt lz4 p7zip-full rzsz
	fi
	setpara USE_AMAVIS yes
	USE_AMAVIS="yes"
    else
	echo "AMaVis is installed; will be removed with corresponding packages"
	zypper rm -u -y amavisd-new spamassassin clamav clzip rzip melt lz4 p7zip-full rzsz
	USE_AMAVIS="no"
    fi
else
    if [ "$USE_AMAVIS" = "yes" ] ; then
	 [ ! -f /etc/amavisd.conf ] && zypper in -y amavisd-new spamassassin clamav clzip rzip melt lz4 p7zip-full rzsz
    fi
fi
if [ "$POSTFIX_NULLCLIENT" = "yes" -a "$SMTPD_LISTEN_REMOTE" = "yes" ] ; then
    echo "Remote access to port 25 and postfix type is nullclient are mutually exclusive"
    echo "The script will be aborted"
    exit 1
fi
if [ "$USE_AMAVIS" = "yes" -a "$SMTPD_LISTEN_REMOTE" = "no" ] ; then
    echo "No remote access to port 25 and use of AMaVis makes no sense"
    echo "The script will be aborted"
    exit 1
fi
if [ "$SMTPD_LISTEN_REMOTE" = "yes" ] ; then
    if [ "$POSTFIX_SMTP_TLS_SERVER" = "no" ] ; then
	echo "Currently you allow incoming email on port 25, but it is not encrypted?"
	echo "Do you want encrypted access?"
	yesorno
	if [ $? -eq 0 ] ; then
	    setpar POSTFIX_SMTP_TLS_SERVER yes
	    POSTFIX_SMTP_TLS_SERVER="yes"
	fi
    else 
	echo "Currently you allow incoming email on port 25 with encryption."
	echo "Is this OK? Otherwise encryption on this port wil be removed."
	yesorno
	if [ $? -ne 0 ] ; then
	    setpar POSTFIX_SMTP_TLS_SERVER no
	    POSTFIX_SMTP_TLS_SERVER="no"
	    setpar POSTFIX_SMTP_AUTH_SERVER no
	    POSTFIX_SMTP_AUTH_SERVER="no"
	fi
    fi
fi
if [ "$SMTPD_LISTEN_REMOTE" = "yes" -a "$POSTFIX_SMTP_TLS_SERVER" = "yes" ] ; then
    if [ "$POSTFIX_SMTP_AUTH_SERVER" = "no" ] ; then
	echo "Currently you only allow encrypted incoming email on port 25."
	echo "Do you also want authenticated access on port 587?"
	yesorno
	if [ $? -eq 0 ] ; then
	    setpar POSTFIX_SMTP_AUTH_SERVER yes
	    POSTFIX_SMTP_AUTH_SERVER="yes"
	fi
    else
	echo "Currently you allow encrypted incoming email on port 25 and authenticated access on port 587."
	echo "Is this OK? Otherwise authenticated access on port 587 will be removed."
	yesorno
	if [ $? -ne 0 ] ; then
	    setpar POSTFIX_SMTP_AUTH_SERVER no
	    POSTFIX_SMTP_AUTH_SERVER="no"
	fi
    fi
fi
if [ "$SMTPD_LISTEN_REMOTE" = "yes" ] ; then
    change=1
    if [ -n "$POSTFIX_BASIC_SPAM_PREVENTION" ] ; then
	echo "Currently you have enabled basic spam prevention with type ${bold}$POSTFIX_BASIC_SPAM_PREVENTION${offbold}"
	echo "Possibilities are: none, medium, hard, and custom."
	echo "Is the current one OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    else
	echo "You did not specify the basic spam prevention, which can be:"
	echo "none, medium, hard, and custom."
	echo "Do you want none changed in something else?"
	yesorno
	change=$?
    fi
    if [ $change -eq 0 ] ; then
	while true
    	do
	    echo -n "Enter none, medium, hard, or custom : "
	    read POSTFIX_BASIC_SPAM_PREVENTION
	    case "$POSTFIX_BASIC_SPAM_PREVENTION" in
		"none"   ) POSTFIX_BASIC_SPAM_PREVENTION=""
			   ;;
		"medium" ) ;;
		"hard"   ) ;;
		"custom" ) ;;
		*        ) echo "Please provide the proper answer!"
		           continue
			;;
	    esac
	    setpar POSTFIX_BASIC_SPAM_PREVENTION "$POSTFIX_BASIC_SPAM_PREVENTION"
	    break
	done
    fi
    if [ "$POSTFIX_BASIC_SPAM_PREVENTION" = "medium" -o "$POSTFIX_BASIC_SPAM_PREVENTION" = "hard" ] ; then
	change=1
	if [ -n "$POSTFIX_RBL_HOSTS" ] ; then
	    echo "You have specified to blacklist hosts from the server(s): $POSTFIX_RBL_HOSTS"
	    echo "Is this OK?"
	    yesorno
	    [ $? -eq 0 ] && change=1 || change=0
	else
	    echo "You did not specify any server with hosts to be blacklisted."
	    echo "Do you want anything in your list? Options will be given."
	    yesorno
	    change=$?
	fi
	if [ $change -eq 0 ] ; then
	    while true
	    do
		echo "Enter digit 1 or a combination of 2,3, and 4, which belong to the following options:"
		echo "1: nothing in the list of servers with blacklisted hosts"
		echo "2: server bl.spamcop.net"
		echo "3: server cbl.abuseat.org"
		echo "4: server zen.spamhaus.org"
		read answ
		list=""
		error=1
		while [ ${#answ} -ne 0 ]
		do
		    case ${answ:0:1} in
		        "1" ) [ ${#answ} -ne 1 ] && echo "Only digit 1 is allowed" && error=0 && break
			    ;;
		        "2" ) list="${list}bl.spamcop.net "
			    ;;
		        "3" ) list="${list}cbl.abuseat.org "
			    ;;
		        "4" ) list="${list}zen.spamhaus.org "
			    ;;
		        *   ) echo "Please enter the proper digits!!" && error=0 && break
		            ;;
		    esac
		    answ="${answ:1}"
		done
		[ $error -eq 0 ] && continue
		[ -n ${list} ] && list="${list% }"
		POSTFIX_RBL_HOSTS="$list"
		setpar POSTFIX_RBL_HOSTS "$list"
		break
	    done
	fi
    fi
    if [ "$POSTFIX_SMTP_TLS_SERVER" = "yes" ] ; then
	    # We need to generate/have a self signed certificate with a number of parameters in /etc/sysconfig/postfix
	    # also the server needs to have a name in the DNS like smtp.domain.com or mail.domain.com
	    # the local hostname may be <somename>.domain.com
	    #
	    # Find the host name and the domain name of the system
	    #
	    echo "Trying to find host name and domain name..."
	    HOSTNAME="$(hostname -f 2>/dev/null)"
	    # may contain IPv6 address (: in name), if so localhost, or no value
	    [ -z "$HOSTNAME" -o "$HOSTNAME" != "${HOSTNAME%%:*}" ] && HOSTNAME="localhost"
	    Domainname=${HOSTNAME#*.}
	    HOSTNAME=${HOSTNAME%%.*}
	    change=1
	    if [ "$HOSTNAME" != "localhost" ] ; then
		echo "Currently your hostname is: ${bold}$HOSTNAME${offbold}"
		echo "Is this OK?"
		yesorno
		[ $? -ne 0 ] && change=0
	    else
		change=0
	    fi
	    if [ $change -eq 0 ] ; then
		while true
		do
		    echo -n "Enter the name of the system (should not contain a dot) : "
		    read HOSTNAME
		    [ ${#HOSTNAME} -eq 0 ] && echo "Hostname can not be empty" && continue
		    [ "$HOSTNAME" != "${HOSTNAME%#.*}" ] && echo "Hostname contains a dot" && continue
		    break
		done
		echo "$HOSTNAME" > /etc/hostname
	    fi
	    count=$(grep $HOSTNAME /etc/hosts | wc -l)
	    if [ $count -eq 0 ] ; then
		ipa=$(hostname -I)
		# ipa may contain IPv6 addresses, isolate IPv4 address
		ipa=${ipa%% *}
		while true
		do
		    echo -n "Enter the domain name (should contain a dot): "
		    read DOMAINNAME
		    [ ${#DOMAINNAME} -eq 0 ] && "Domain name can not be empty" && continue
		    [ "$DOMAINTNAME" = "${DOMAINNAME%#.*}" ] && echo "Hostname does not contains a dot" && continue
		    break
		done
		if [ "$Domainname" != "$DOMAINNAME" ] ; then
		    echo "The domain name found with 'hostname -f', $Domainname,  does not correspond"
		    echo "with the one entered or in /etc/hosts. Assumed is: '$DOMAINNAME' is the right one"
		fi
		echo "Checking for existing records in the DNS"
		n=0
		nslookup -query=A $DOMAINNAME > /tmp/Adomain
		[ $? -ne 0 ] && echo "$DOMAINNAME does not have an A record" && n=$(($n+1))
		nslookup -query=MX $DOMAINNAME > /tmp/MXdomain
		[ $? -ne 0 ] && echo "$DOMAINNAME does not have an MX record" && n=$(($n+1))
		nslookup -query=A smtp.$DOMAINNAME > /tmp/smtpdomain
		[ $? -ne 0 ] && echo "smtp.DOMAINNAME does not have an A or CNAME record" && n=$(($n+1))
		nslookup -query=A mail.$DOMAINNAME > /tmp/maildomain
		[ $? -ne 0 ] && echo "mail.$DOMAINNAME does not have an A or CNAME record" && n=$(($n+1))
		nslookup -query=A imap.$DOMAINNAME > /tmp/imapdomain
		[ $? -ne 0 ] && echo "imap.$DOMAINNAME does not have an A or CNAME record" && n=$(($n+1))
		[ $n -ne 0 ] &&\
		    echo "Please provide the required records in the DNS for domain $DOMAINNAME and start the script again"\
			&& exit 1
		gipaddress=$(grep 'Address:' /tmp/Adomain | tail -1)
		gipaddress=${gipaddress#* }
		sub[0]="smtp" ; sub[1]="mail" ; sub[3]="imap" ; i=0 ; n=0
		for f in /tmp/smtpdomain /tmp/maildomain /tmp/imapdomain
		do
		    grep -q "$gipaddress" $f
		    [ $? -ne 0 ] && echo "Global IP address not in record for ${sub[$i]}.$DOMAINNAME" && n=$(($n+1))
		    rm $f
		    i=$(($i+1))
		done
		[ $n -ne 0 ] && echo "Apparently there is something wrong with the data in the DNS. Please fix it" && exit 1
		#
		# Check if there is already an entry in /etc/hosts for the server, if so remove it and enter such an entry.
		# The entry should be <host_ip_address> <host_name>.<domain_name> <hostname>
		#
		hostip=$(hostname -I)
		# hostip may contain IPv6 addresses, if so remove these
		hostip=${hostip%% *}
		grep -q $hostip /etc/hosts
		[ $? -eq 0 ] && sed -i "/$hostip/d" /etc/hosts
		#
		# Insert the entry in /etc/hosts after line with 127.0.0.1
		#
		sed -i "/127.0.0.1/a $hostip	$HOSTNAME.$DOMAINNAME $HOSTNAME" /etc/hosts
		count=1
		echo $HOSTNAME > /etc/hostname
		nslookup -query=AAAA smtp.$DOMAINNAME > /tmp/AAAAdomain
		tail -1 /tmp/AAAAdomain | grep -q Address
		[ $? -eq 0 ] &&\
		    echo "WARNING: This script supports only a server without an IPv6 address for smtp.$DOMAINNAME"\
			&& echo "Contact the author if you have this requirement"
		rm /tmp/AAAAdomain
		echo "The system will reboot now to show the system name $HOSTNAME.$DOMAINNAME and please run this script again"
		reboot
		# a proper hostname an domain name should here be available
		# a proper hostname an domain name should here be available
	    else # hostname looks OK check for domain name, should be OK
		DOMAINNAME=$(hostname -f)
		hostname=${DOMAINNAME%%.*}
		DOMAINNAME=${DOMAINNAME#*.}
		if [ "$hostname" != "$HOSTNAME" ] ; then
		    echo "There is an inconsistency between content in /etc/hostname and /etc/hosts"
		    echo "Please solve this inconsistency"
		    exit 1
	        else
		    echo "The domain name to be used is ${bold}$DOMAINNAME${offbold}"
		fi
		setpar POSTFIX_MYHOSTNAME ${HOSTNAME}.${DOMAINNAME}
		POSTFIX_MYHOSTNAME="${HOSTNAME}.${DOMAINNAME}"
	    fi
    else
	POSTFIX_MYHOSTNAME=$(hostname -f)
	setpar POSTFIX_MYHOSTNAME "${POSTFIX_MYHOSTNAME}"
	hostname=${POSTFIX_MYHOSTNAME%%.*}
	DOMAINNAME=${POSTFIX_MYHOSTNAME#*.}
    fi
fi
if [ "$POSTFIX_SMTP_TLS_SERVER" = "yes" ] ; then
    change=1
    if [ "${POSTFIX_SMTP_AUTH_SERVICE,,}" = "dovecot" ] ; then
	echo "Currently you want to use dovecot for authentication"
	echo "Is this OK?"
	yesorno
	if [  $? -ne 0 ] ; then
	    setpar POSTFIX_SMTP_AUTH_SERVICE cyrus
	    POSTFIX_SMTP_AUTH_SERVICE="cyrus"
	    [ -e /etc/dovecot/dovecot.conf ] && zypper rm -u -y dovecot
	    if [ ! -e /usr/lib/systemd/system/saslauthd.service ] ; then
		zypper in -y cyrus-sasl-saslauthd cyrus-sasl-plain
		systemctl start saslauthd.service
		systemctl enable saslauthd.service
	    fi
	else
	    [ ! -e /etc/dovecot/dovecot.conf ] && zypper in -y --no-recommends dovecot
            [  -e /usr/lib/systemd/system/saslauthd.service ] && zypper rm -y -u cyrus-sasl-saslauthd cyrus-sasl-plain
	fi
    else
	echo "Currently you want to use cyrus for authentication"
	echo "Is this OK?"
	yesorno
	if [ $? -ne 0 ] ; then
	    setpar POSTFIX_SMTP_AUTH_SERVICE dovecot
	    POSTFIX_SMTP_AUTH_SERVICE="dovecot"
	    [ ! -e /etc/dovecot/dovecot.conf ] && zypper in -y --no-recommends dovecot
	    [  -e /usr/lib/systemd/system/saslauthd.service ] && zypper rm -y -u cyrus-sasl-saslauthd cyrus-sasl-plain
	else
	    [ ! -e /usr/lib/systemd/system/saslauthd.service ] && zypper in -y cyrus-sasl-saslauthd cyrus-sasl-plain
	    systemctl start saslauthd.service
	    systemctl enable saslauthd.service
	    [ -e /etc/dovecot/dovecot.conf ] && zypper rm -y -u dovecot
	fi
    fi
    # we need to prepare the generation of a self-signed certificate
    echo "Information for generating a self-signed certificate for postfix"
    if [ "$POSTFIX_SMTP_AUTH_SERVICE" = "dovecot" ] ; then
	echo "Dovecot authentication also means a secured imap server by dovecot,"
	echo "which also needs a self-signed certificate"
	if [ ! -x /usr/sbin/dovecot ] ; then
	    zypper in -y --no-recommends dovecot
	fi
    fi
    # Default POSTFIX_SSL_PATH="/etc/postfix/ssl"
    # Next should be default not set
    setpar POSTFIX_TLS_CAFILE "cacert.pem"
    POSTFIX_TLS_CAFILE="cacert.pem"
    # Default POSTFIX_TLS_CERTFILE="certs/postfixcert.pem"
    POSTFIX_TLS_KEYFILE="certs/postfixkey.pem"
    echo "Information to generate a self-signed certificate"
    if [ ${#POSTFIX_SSL_COUNTRY} -eq 0 ] ; then
	change=0 
    else
	echo "Your country code is : $POSTFIX_SSL_COUNTRY"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo -n "Enter the two letter code of your country : "
	read answ
	[ ${#answ} -ne 2 ] && echo "Not a two letter code" && continue
	answ=${answ^^}
	setpar POSTFIX_SSL_COUNTRY "$answ"
	POSTFIX_SSL_COUNTRY="$answ"
	break
    done
    if [ ${#POSTFIX_SSL_STATE} -eq 0 ] ; then
	change=0 
    else
	echo "Your state/province is : $POSTFIX_SSL_STATE"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo -n "Enter the name of your state/province : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar POSTFIX_SSL_STATE "$answ"
	POSTFIX_SSL_STATE="$answ"
	break
    done
    if [ ${#POSTFIX_SSL_LOCALITY} -eq 0 ] ; then
	change=0 
    else
	echo "Your city/locality is : $POSTFIX_SSL_LOCALITY"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo -n "Enter the name of your city/locality : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar POSTFIX_SSL_LOCALITY "$answ"
	POSTFIX_SSL_LOCALITY="$answ"
	break
    done
    if [ ${#POSTFIX_SSL_ORGANIZATION} -eq 0 ] ; then
	change=0 
    else
	echo "Your organization is : $POSTFIX_SSL_ORGANIZATION"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=1
    fi
    while [ $change -eq 0 ]
    do
	echo -n "Enter the name of your organization : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar POSTFIX_SSL_ORGANIZATION "$answ"
	POSTFIX_SSL_ORGANIZATION="$answ"
	break
    done
    if [ ${#POSTFIX_SSL_ORGANIZATIONAL_UNIT} -eq 0 ] ; then
	change=0 
    else
	echo "Your organizational unit is : $POSTFIX_SSL_ORGANIZATIONAL_UNIT"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo -n "Enter the name of your organizational unit : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar POSTFIX_SSL_ORGANIZATIONAL_UNIT "$answ"
	POSTFIX_SSL_ORGANIZATIONAL_UNIT="$answ"
	break
    done
    if [ ${#POSTFIX_SSL_CERTIFICATE_AUTHORITY} -eq 0 ] ; then
	change=0 
    else
	echo "Your common name for the Certificate Authority is : $POSTFIX_SSL_CERTIFICATE_AUTHORITY"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo -n "Enter the common name for the Certificate Authority (recommended: Certificate Authority) : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar POSTFIX_SSL_CERTIFICATE_AUTHORITY "$answ"
	POSTFIX_SSL_CERTIFICATE_AUTHORITY="$answ"
	break
    done
    if [ ${#POSTFIX_SSL_COMMON_NAME} -eq 0 ] ; then
	change=0 
    else
	echo "Your common name for the certificate for postfix is : $POSTFIX_SSL_COMMON_NAME"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo "Enter the common name for this certificate, should be the"
       	echo -n "name in the MX record for the domain like {mail,smtp}.$DOMAINNAME : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar POSTFIX_SSL_COMMON_NAME "$answ"
	POSTFIX_SSL_COMMON_NAME="$answ"
	break
    done
    if [ "${POSTFIX_SMTP_AUTH_SERVICE}" = "dovecot" ] ; then
	if [ ${#DOVECOT_SSL_ORGANIZATIONAL_UNIT} -eq 0 ] ; then
	    change=0 
	else
	    echo "Your common name for the certificate for dovecot is : $DOVECOT_SSL_ORGANIZATIONAL_UNIT"
	    echo "Is this OK?"
	    yesorno
	    [ $? -eq 0 ] && change=1 || change=0
	fi
	while [ $change -eq 0 ]
	do
	    echo "Enter the organizational name for this certificate,"
	    echo -n "something like IMAP-server or Email Department : "
	    read answ
	    [ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	    setpar DOVECOT_SSL_ORGANIZATIONAL_UNIT "$answ"
	    DOVECOT_SSL_ORGANIZATIONAL_UNIT="$answ"
	    break
	done
	if [ ${#DOVECOT_SSL_COMMON_NAME} -eq 0 ] ; then
	    change=0 
	else
	    echo "Your common name for the certificate for dovecot is : $DOVECOT_SSL_COMMON_NAME"
	    echo "Is this OK?"
	    yesorno
	    [ $? -eq 0 ] && change=1 || change=0
	fi
	while [ $change -eq 0 ]
	do
	    echo "Enter the common name for this certificate, should be the name in"
	    echo -n "the DNS for access to the imap server (recommended: imap.$DOMAINNAME) : "
	    read answ
	    [ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	    setpar DOVECOT_SSL_COMMON_NAME "$answ"
	    DOVECOT_SSL_COMMON_NAME="$answ"
	    break
	done
    fi
    if [ ${#CERTIFICATE_AUTHORITY_EMAIL_ADDRESS} -eq 0 ] ; then
	change=0 
    else
	echo "The email address of the Certificate Authority is : $CERTIFICATE_AUTHORITY_EMAIL_ADDRESS"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo -n "Enter the email address of the Certificate Authority (recommended ca@$DOMAINNAME) : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar CERTIFICATE_AUTHORITY_EMAIL_ADDRESS "$answ"
	CERTIFICATE_AUTHORITY_EMAIL_ADDRESS="$answ"
	break
    done
    if [ ${#POSTFIX_SSL_EMAIL_ADDRESS} -eq 0 ] ; then
	change=0 
    else
	echo "The email address in your certificate is : $POSTFIX_SSL_EMAIL_ADDRESS"
	echo "Is this OK?"
	yesorno
	[ $? -eq 0 ] && change=1 || change=0
    fi
    while [ $change -eq 0 ]
    do
	echo "Enter the email address for the certificate of the"
       	echo -n "email server (recommended postmaster@$DOMAINNAME) : "
	read answ
	[ ${#answ} -eq 0 ] && echo "Should not be empty" && continue
	setpar POSTFIX_SSL_EMAIL_ADDRESS "$answ"
	POSTFIX_SSL_EMAIL_ADDRESS="$answ"
	break
    done
fi
# Set POSTFIX_LOCALDOMAINS needs some previous parameters
change=1
addedvalues=""
mydomain="${POSTFIX_MYHOSTNAME#*.}"
if [ -n "$POSTFIX_LOCALDOMAINS" ] ; then
    echo "Currently the domains this server considers local are:"
    echo "${bold}$POSTFIX_LOCALDOMAINS${unbold}"
    for local in "$POSTFIX_MYHOSTNAME" "$mydomain" "localhost.$mydomain"
    do
	[ $(echo "$POSTFIX_LOCALDOMAINS" | egrep -q "^${local},") -o \
		$(echo "$POSTFIX_LOCALDOMAINS" | grep -q " ${local},") ] && continue
	echo "Apparently the parameter POSTFIX_LOCALDOMAINS does not contain $local"
	echo "This parameter will be reset trying to use previous values"
	change=0
    done
    if [ "$POSTFIX_SSL_COMMON_NAME" != "$POSTFIX_MYHOSTNAME" ] ; then
	echo "$POSTFIX_LOCALDOMAINS" | grep -q " $POSTFIX_SSL_COMMON_NAME,"
	[ $? -ne 0 ] && change=0
    fi
    if [ $(echo "$POSTFIX_LOCALDOMAINS" | egrep -q " localhost$") -o \
	    $(echo "$POSTFIX_LOCALDOMAINS" | grep -q " localhost,") ] ; then
	[ $? -ne 0 ] && change=0
    fi
    if [ $change -eq 1 ] ;then
	echo "Is this all OK?"
	yesorno
	[ $? -ne 0 ] change=0
    fi
    addedvalues=${POSTFIX_LOCALDOMAINS#* localhost,}
fi
if [ $change -eq 0 -o -z "$POSTFIX_LOCALDOMAINS" ] ; then
    echo "Currently the domains this server considers or should consider local domains are:"
    echo -n "${bold}$POSTFIX_MYHOSTNAME, $mydomain, localhost.$mydomain"
    [ -n "$POSTFIX_SSL_COMMON_NAME" -a "$POSTFIX_SSL_COMMON_NAME" != "$POSTFIX_MYHOSTNAME" ] && echo -n ", $POSTFIX_SSL_COMMON_NAME"
    echo "${offbold} and ${bold}localhost${offbold}"
    POSTFIX_LOCALDOMAINS="$POSTFIX_MYHOSTNAME, $mydomain, localhost.$mydomain"
    [ -n "$POSTFIX_SSL_COMMON_NAME" -a  "$POSTFIX_SSL_COMMON_NAME" != "$POSTFIX_MYHOSTNAME" ] && \
	POSTFIX_LOCALDOMAINS="$POSTFIX_LOCALDOMAINS, $POSTFIX_SSL_COMMON_NAME"
    POSTFIX_LOCALDOMAINS="$POSTFIX_LOCALDOMAINS, localhost"
    addv=0
    if [ -n "$addedvalues" ] ; then
	while [ -n "$addedvalues" ]
	do
	    addedvalues=${addedvalues#,}
	    addedvalues=${addedvalues# }
	    local=${addedvalues%% *}
	    addedvalues=${addedvalues#* }
	    [ "$addedvalues" = "$local" ] && addedvalues=""
	    local=${local%,}
	    echo "You did have ${bold}${local}${offbold} as additional local domain"
	    echo "Do you want to keep it?"
	    yesorno
	    [ $? -eq 0 ] && POSTFIX_LOCALDOMAINS="$POSTFIX_LOCALDOMAINS, $local" && addv=$(($addv+1))
	done
    fi
    echo 'Do you want (more) additional domains?'
    yesorno
    if [ $? -eq 0 ] ; then
	while true
	do
	    echo -n "Enter one additional domain : "
	    read adds
	    POSTFIX_LOCALDOMAINS="$POSTFIX_LOCALDOMAINS, $adds"
	    addv=$(($addv+1))
	    echo "More additional domains?"
	    yesorno
	    [ $? -eq 0 ] && continue
	    break
	done
    fi
    [ $addv -eq 0 ] && POSTFIX_LOCALDOMAINS=""
fi
setpar POSTFIX_LOCALDOMAINS "$POSTFIX_LOCALDOMAINS"
#
# Support for checking on SPF information
#
if [ "$SMTPD_LISTEN_REMOTE" = "yes" ] ; then
    if [ "$POSTFIX_SPF_CHECKS" = "no" ] ; then
	echo "Currently you do NOT want to check incoming connections on port 25 on SPF information"
	echo "Is this OK?"
	yesorno
	if [ $? -ne 0 ] ; then
	    setpar POSTFIX_SPF_CHECKS yes
	    POSTFIX_SPF_CHECKS="yes"
	    grep -q policyd-spf /etc/passwd
	    [ $? -ne 0 ] && useradd -r -d /etc/policyd-spf -s "/sbin/nologin" -c "SPF Policy Server for Postfix" policyd-spf
	    mkdir -p /etc/policyd-spf
	    chown policyd-spf:root /etc/policyd-spf
	fi
    else
	echo "Currently you want to check incoming connections on port 25 on SPF information"
	echo "Is this OK?"
	yesorno
	if [ $? -ne 0 ] ; then
	    setpar POSTFIX_SPF_CHECKS no
	    POSTFIX_SPF_CHECKS="no"
	    grep -q policyd-spf /etc/passwd
	    [ $? -eq 0 ] && userdel policyd-spf
	    [ -d /etc/policyd-spf ] && rmdir /etc/policyd-spf
	fi
    fi
    if [ "$POSTFIX_SPF_CHECKS" = "yes" ] ; then
	if [ ! -e /etc/zypp/repos.d/postfix-policyd-spf-perl.repo ] ; then
	    zypper ar https://download.opensuse.org/repositories/devel:/languages:/perl/15.4/ postfix-policyd-spf-perl
	    zypper ref postfix-policyd-spf-perl
	fi
	if [ ! -e /usr/lib/policyd-spf-perl ] ; then
	    zypper mr -e postfix-policyd-spf-perl
	    zypper in -y postfix-policyd-spf-perl
	    # disable the repository, because a future zypper (d)up may have problems
	    zypper mr -d postfix-policyd-spf-perl
	fi
    fi
else
    setpar POSTFIX_SPF_CHECKS no
    POSTFIX_SPF_CHECKS="no"
fi
#
# Support for checking on DKIM information and generating DKIM signing
#
if [ "$USE_AMAVIS" = "yes" ] ; then
    if [ "$POSTFIX_WITH_DKIM" = "no" ] ; then
	echo "Currently DKIM support has not been enabled"
	echo "Do you want to enable DKIM support"
	yesorno
	if [ $? -eq 0 ] ; then
	    setpar POSTFIX_WITH_DKIM yes
	    POSTFIX_WITH_DKIM="yes"
	fi
    else
	echo "Currently DKIM support has been enabled"
        echo "Is this OK? Otherwise it will be disabled."
        yesorno
        if [ $? -ne 0 ] ; then
            setpar POSTFIX_WITH_DKIM no
            POSTFIX_WITH_DKIM="no"
        fi
    fi
else
    setpar POSTFIX_WITH_DKIM no
    POSTFIX_WITH_DKIM="no"
fi
if [ "$POSTFIX_WITH_DKIM" = "yes" ] ; then
    if [ "${POSTFIX_DKIM_TYPE,,}"  = "opendkim" ] ; then
	echo "Currently DKIM support is done using openDKIM?"
	echo "Do you want to change that into DKIM support by AMaVis?"
	yesorno
	if [ $? -eq 0 ] ; then
	    setpar POSTFIX_DKIM_TYPE AMAVIS_DKIM
	    POSTFIX_DKIM_TYPE="AMAVIS_DKIM"
	    if [ -f /etc/opendkim/opendkim.conf ] ; then
		zypper rm -u -y opendkim
	    fi
	else
	    setpar POSTFIX_DKIM_TYPE openDKIM
	    POSTFIX_DKIM_TYPE="openDKIM"
	    if [ ! -f /etc/opendkim/opendkim.conf ] ; then
		zypper in -y opendkim
	    fi
	fi
    else
	echo "Currently DKIM support is done using DKIM in AMaVis?"
        echo "Do you want to change that into DKIM support by openDKIM?"
	yesorno
	if [ $? -eq 0 ] ; then
            setpar POSTFIX_DKIM_TYPE openDKIM
	    POSTFIX_DKIM_TYPE="openDKIM"
            if [ ! -f /etc/opendkim.conf ] ; then
                zypper in -y opendkim
            fi
        else
	    setpar POSTFIX_DKIM_TYPE AMAVIS_DKIM
	    POSTFIX_DKIM_TYPE="AMAVIS_DKIM"
            if [ -f /etc/opendkim.conf ] ; then
                zypper rm -u -y opendkim
            fi
	fi
    fi
fi
if [ "${POSTFIX_DKIM_TYPE,,}" = "opendkim" ] ; then
   setpar POSTFIX_DKIM_CONN socket
   POSTFIX_DKIM_CONN="socket"
else
    setpar POSTFIX_DKIM_CONN tcp
    POSTFIX_DKIM_CONN="tcp"
fi
#
# Support for checking with DMARC
#
if [ "$SMTPD_LISTEN_REMOTE" = "yes" ] ; then
    if [ "$POSTFIX_DMARC_CHECKS" = "no" ] ; then
	echo "Currently you do NOT want to check incoming email on port 25 on DMARC information"
	echo "Is this OK?"
	yesorno
	if [ $? -ne 0 ] ; then
            setpar POSTFIX_DMARC_CHECKS yes
            POSTFIX_DMARC_CHECKS="yes"
	fi
    else
	echo "Currently you want to check incoming email on port 25 on DMARC information"
	echo "Is this OK?"
	yesorno
	if [ $? -ne 0 ] ; then
            setpar POSTFIX_DMARC_CHECKS no
            POSTFIX_DMARC_CHECKS="no"
	fi
    fi
    if [ "$POSTFIX_DMARC_CHECKS" = "yes" ] ; then
	if [ ! -e /etc/opendmarc.conf ] ; then
	    if [ ! -e /etc/zypp/repos.d/server-mail.repo ] ; then
		zypper ar https://download.opensuse.org/repositories/server:/mail/15.5/ server-mail
		zypper ar https://download.opensuse.org/repositories/devel:languages:perl/15.5/ devel-languages-perl
		zypper ref server-mail
		zypper ref devel-languages-perl
	    else
		zypper mr -e server-mail
		zypper mr -e devel-languages-perl
	    fi
	    zypper in --allow-unsigned-rpm -y opendmarc
	    # disable repository because a later zypper (d)up may cause problems
	    zypper mr -d server-mail
	    zypper mr -d devel-languages-perl
	fi
	mkdir -p /etc/opendmarc
	egrep -q '^# AuthservID name' /etc/opendmarc.conf
	if [ $? -eq 0 ] ; then
	    cat <<EOF > /tmp/sedscript.txt
/^# AuthservID name/ c\AuthservID OpenDMARC
/^# CopyFailuresTo postmaster@localhost/ c\CopyFailuresTo dmarc-failures@$DOMAINNAME
/^# FailureReports false/ c\FailureReports true
/^# FailureReportsBcc postmaster@example.coom/ c\FailureReportsBcc dmarc-reports-sent@$DOMAINNAME
/^# FailureReportsOnNone false/ c\FailureReportsOnNone true
/^# FailureReportsSentBy USER@HOSTNAME/ c\FailureReportsSentBy postmaster@$DOMAINNAME
/^# HistoryFile / s/^# //
/^# IgnoreAuthenticatedClients false$/ c\IgnoreAuthenticatedClients true
/^# IgnoreHosts / s/^# //
/^# RejectFailures false/ s/# //
/^# ReportCommand / s/^# //
/^# RequiredHeaders false$/ c\RequiredHeaders true
/^# TrustedAuthservIDs HOSTNAME$/ c\TrustedAuthservIDs $DOMAINNAME
EOF
	    sed -i -f /tmp/sedscript.txt /etc/opendmarc.conf
	    rm /tmp/sedscript.txt
            touch /etc/opendmarc/ignore.hosts
            chown opendmarc:opendmarc /etc/opendmarc/ignore.hosts
            chmod 644 /etc/opendmarc/ignore.hosts
	    grep -q dmarc /etc/aliases
	    if [ $? -ne 0 ] ; then
		echo -e "dmarc-failures:\t\tpostmaster" >> /etc/aliases
		echo -e "dmarc-reports-send:\tpostmaster" >> /etc/aliases
		newaliases
	    fi
	fi
    else
	if [ -e /etc/opendmarc.conf ] ; then
	    if [ -e /etc/zypp/repos.d/server-mail.repo ] ; then
		zypper mr -e server-mail
		zypper rm -y opendmarc
		zypper mr -d server-mail
	    fi
	fi
    fi
fi
echo "=========================="
echo "Configurating firewalld..."
echo "=========================="
if [ ! -e /usr/lib/systemd/system/firewalld.service ] ; then
    zypper in -y firewalld
fi
if [ "$SMTPD_LISTEN_REMOTE" = "yes" ] ; then
    if [ "$(systemctl is-active firewalld.service)" = "inactive" ] ; then
	systemctl start firewalld.service
    fi
    interface="$(ip a | grep ' UP ')"
    interface=${interface#* }
    interface=${interface%%:*}
    localipdomain=$(ip r | tail -1)
    localipdomain=${localipdomain%% *}
    if [ "$POSTFIX_SMTP_TLS_SERVER" = "yes" ] ; then
	firewall-cmd --list-all --zone=public | grep -q $interface
	[ $? -ne 0 ] && firewall-cmd --zone=public --add-interface=$interface
	firewall-cmd --list-all --zone=public | grep -q smtp
	[ $? -ne 0 ] && firewall-cmd --zone=public --add-service=smtp
	firewall-cmd --list-all --zone=public | grep -q ' imaps '
	[ $? -ne 0 ] && firewall-cmd --zone=public --add-service=imaps
	firewall-cmd --list-all --zone=internal | grep -q "$localipdomain"
	[ $? -ne 0 ] && firewall-cmd --zone=internal --add-source=$localipdomain
	firewall-cmd --list-all --zone=internal | grep -q ' smtp-submission '
	[ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=smtp-submission
	if [ "$POSTFIX_SMTP_AUTH_SERVICE" = "dovecot" ] ; then
	    firewall-cmd --list-all --zone=internal | grep -q ' imap '
	    [ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=imap
	    firewall-cmd --list-all --zone=internal | grep -q ' imaps '
	    [ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=imaps
	    firewall-cmd --list-all --zone=internal | grep -q ' smtp '
	    [ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=smtp
	    firewall-cmd --list-all --zone=internal | grep -q ' smtp-submission '
	    [ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=smtp-submission
	fi
	firewall-cmd --runtime-to-permanent
    fi
fi
