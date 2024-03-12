#!/bin/bash
#
#***************************************************************************
#
# Copyright (c) 2023-2024 Freek de Kruijf
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
# Script to generate an email system that supports a single domain and
# implements all security features available for such a system. It is
# designed to follow the procedure outlined in the openSUSE wiki page
# https://en.opensuse.org/Mail_server_HOWTO after heading SMTP.
#
# In this wiki page the domain name used is domain.com, which will be
# replaced by the required domain name. Furthermore all packages mentioned
# in this page will be installed right from the beginning.
#
# Version history
# Version 1.0 First release
# Version 1.0.1 Restrict disable_vrfy_command=yes to after ORIGINATING in submission
# Version 1.0.2 Milter to port 8893 is for opendkim (currenly not supported) removed
# Version 1.1.0 Improved generation of certificates (no questions asked anymore)
# Version 1.2.0 Added option to use dialog in asking questions and showing progress
# Version 1.3.0 Added support for Raspberry Pi OS with Bookworm
#
# Version designed on openSUSE Leap 15.5 on Raspberry Pi 4B
# This version should also work in other environments of openSUSE
# Tested also on Tumbleweed and x86_64
# Tested in Rasbberry Pi OS Lite 32 bit on Rasberry Pi 4B
#
# ---------------------------------------------------------------------
#
# this script should be run as user root
#
debug=1
[ -e /etc/genpdsdm/genpdsdm.log ] && rm /etc/genpdsdm/genpdsdm.log
comm="$0"
dialog1='dialog --title GenPDSDM --begin 5 10'
exitmsg() {
    if [ $DIAL -eq 0 ] ; then
	local n=$((${#1}/50))
	$dialog1 --colors --msgbox "\Z1\Zb${1}\Zr" $(($n+5)) 75
	clear
    else
	/usr/bin/echo -e "$1"
    fi
    exit 1
}
dlog() {
    [ $debug -eq 1 ] && echo "$1" >> /etc/genpdsdm/genpdsdm.log
}
# initialize NEW, OLD and DIAL as not activated
NEW=1 ; OLD=1 ; DIAL=1
grep -q "Tumbleweed" /etc/os-release && OS="openSUSE_Tumbleweed"
grep -q "Leap 15.5" /etc/os-release && OS="15.5"
egrep -q "raspbian|ID=debian" /etc/os-release && OS="raspbian"
[ ! -x /usr/bin/dialog ] && apt-get -y install dialog
[ "$OS" = "" ] && exitmsg "Only openSUSE Tumbleweed, Leap 15.5 and Raspbian are supported"
#
# /etc/genpdsdm/genpdsdm.log keeps track of what has been done during running the script
# /etc/genpdsdm/genpdsdm.history keeps the history of already executed parts of this script
#
# initialize the history file of the script or read the history to skip what has been done
#
mkdir -p /etc/genpdsdm
[ -e /etc/genpdsdm/genpdsdm.history ] && . /etc/genpdsdm/genpdsdm.history
help="\nUse genpdsdm [OPTIONS]\n\n\
Generates configurations for Postfix, Dovecot, SPL, DKIM and DMARC from\n\
scratch. When invoked for the first time all necessary packets will be\n\
installed and all files, that will be changed, are saved to be able to\n\
start all over again, even much later in the livetime of the system.\n\
When starting the script without --old or -new, and the script has\n\
been succesfully completed before, the configuration will not change,\n\
and only processes will be restarted.\n\n\
OPTIONS\n\
 --dial     use dialog screens to ask questions and show progress\n\
 --old      configure all over again using previously saved parameters\n\
 --new      configure all over again using newly configured parameters\n\
 --help     print this help text and exit\n\n"
if [ "$1" != "" ] ; then
    for par in $@
    do
	case $par in
	    --new   ) NEW=0 ;;
            --old   ) OLD=0 ;;
	    --help  ) [ $DIAL -ne 0 ] && /usr/bin/echo -e "$help" || $dialog1 --msgbox "$help" 20 0 ;;
	    --dial* ) DIAL=0 ;;
	    *       ) echo "Invoke this script with $0 [--dial[og]] [--new|--old] , try again" && exit 1 ;;
        esac
	[ $NEW -eq 0 -a $OLD -eq 0 ] && echo "Parameters --new and --old are mutually exclusief" && exit 1
    done
fi
id | tr "a-z" "A-Z" | egrep -q '^UID=0'
if [ $? -ne 0 ] ; then 
    exitmsg "This script should be executed by root or sudo $0"
fi
#
# Install the required packages
#
dlog "== Starting Installation =="
if [ -z "${INSTALLATION_done}" ] ; then
    if [ $OS != raspbian ] ; then 
	# Check if this a clean system
	if [ -e /etc/zypp/repos.d/postfix-policyd-spf-perl.repo ] ; then
            exitmsg "This is not a clean installed system with only a few required additions\n\
Please start with a fresh installation on the boot device. Removing,\n\
first, the 5 involved packages and the non-standard repositories is\n\
also possible."
	fi
	[ "$OS" = "openSUSE_Tumbleweed" ] && zypper dup -y
	[ "$OS" = "15.5" ] && zypper up -y
	zypper in -y --no-recommends postfix telnet dovecot spamassassin clzip rzip melt cabextract\
	    lz4 p7zip-full rzsz clamav bind-utils
	zypper in  -y --recommends amavisd-new
	if [ ! -e /etc/zypp/repos.d/postfix-policyd-spf-perl ] ; then
	    zypper ar https://download.opensuse.org/repositories/devel:/languages:/perl/$os/ postfix-policyd-spf-perl
	    zypper in -y postfix-policyd-spf-perl
	    # disable repository for not having conflicts during updates
	    zypper mr -d postfix-policyd-spf-perl
	fi
	if [ ! -e /etc/zypp/repos.d/mail-server ] ; then
	    zypper ar https://download.opensuse.org/repositories/server:/mail/$os/ server-mail
	    zypper in -y opendmarc
	    # disable repository for not having conflicts during updates
            zypper mr -d server-mail
	fi
    else
	apt-get -y update
	apt-get -y upgrade
	debconf-set-selections postfixsettings.txt
	apt-get -y install postfix dovecot-imapd postfix-policyd-spf-perl spamassassin opendmarc
	apt-get -y install amavisd-new arj cabextract clamav-daemon lhasa libnet-ldap-perl libsnmp-perl lzop\
	    nomarch rpm libcrypt-des-perl clamav-freshclam clamav-docs firewalld pyzor razor bind9-dnsutils dialog
	usermod -G amavis clamav
	[ -e /usr/share/dovecot/dh.pem ] && cp -a /usr/share/dovecot/dh.pem /etc/genpdsdm/
    fi
    mkdir -p /etc/opendmarc
    if [ ! -e /etc/opendmarc/ignore.hosts ] ; then
	touch /etc/opendmarc/ignore.hosts
	chown opendmarc:opendmarc /etc/opendmarc/ignore.hosts
	chmod 644 /etc/opendmarc/ignore.hosts
    fi
    
    if [ $OS != raspbian ] ; then 
	# postfix needs to be initialized to obtain a standard situation for this script
	systemctl start postfix.service
	systemctl enable postfix.service
	#
    fi
    # Save all files that will get changed by the script
    #
    cp -a /etc/postfix/main.cf /etc/genpdsdm/main.cf.org
    cp -a /etc/postfix/master.cf /etc/genpdsdm/master.cf.org
    cp -a /etc/aliases /etc/genpdsdm/aliases.org
    if [ $OS != raspbian ] ; then 
	cp -a /etc/postfix/canonical /etc/genpdsdm/canonical.org
    else
	touch /etc/genpdsdm/canonical.org
    fi
    cp -a /etc/dovecot/dovecot.conf /etc/genpdsdm/dovecot.conf.org
    cp -a /etc/dovecot/conf.d/10-ssl.conf /etc/genpdsdm/10-ssl.conf.org
    cp -a /etc/dovecot/conf.d/10-master.conf /etc/genpdsdm/10-master.conf.org
    cp -a /etc/dovecot/conf.d/10-mail.conf /etc/genpdsdm/10-mail.conf.org
    #cp -a /usr/share/dovecot/dovecot-openssl.cnf /etc/genpdsdm/dovecot-openssl.cnf.org
    if [ $OS != raspbian ] ; then
	cp -a /etc/amavis.conf /etc/genpdsdm/amavis.conf.org
    else
	cp -a /etc/amavis/conf.d/05-node_id /etc/genpdsdm/05-node_id.org
	cp -a /etc/amavis/conf.d/05-domain_id /etc/genpdsdm/05-domain_id.org
	cp -a /etc/amavis/conf.d/15-content_filter_mode /etc/genpdsdm/15-content_filter_mode.org
	cp -a /etc/amavis/conf.d/20-debian_defaults /etc/genpdsdm/20-debian_defaults.org
	cp -a /etc/amavis/conf.d/50-user /etc/genpdsdm/amavis_conf.d_50-user.org
    fi
    cp -a /etc/opendmarc.conf /etc/genpdsdm/opendmarc.conf.org
    echo "INSTALLATION_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
dlog "== End of installation"
#
# Restore all changed files if OLD or NEW is 0
#
if [ "$OLD" -eq 0 -o "$NEW" -eq 0 ] ; then
    [ -e /etc/genpdsdm/main.cf.org ] && cp -a /etc/genpdsdm/main.cf.org /etc/postfix/main.cf
    [ -e /etc/genpdsdm/master.cf.org ] && cp -a /etc/genpdsdm/master.cf.org /etc/postfix/master.cf
    [ -e /etc/genpdsdm/aliases.org ] && cp -a /etc/genpdsdm/aliases.org /etc/aliases
    [ -e /etc/genpdsdm/canonical.org ] && cp -a /etc/genpdsdm/canonical.org /etc/postfix/canonical
    [ -e /etc/genpdsdm/dovecot.conf.org ] && cp -a /etc/genpdsdm/dovecot.conf.org /etc/dovecot/dovecot.conf
    [ -e /etc/genpdsdm/10-ssl.conf.org ] && cp -a /etc/genpdsdm/10-ssl.conf.org /etc/dovecot/conf.d/10-ssl.conf
    [ -e /etc/genpdsdm/10-master.conf.org ] && cp -a /etc/genpdsdm/10-master.conf.org /etc/dovecot/conf.d/10-master.conf
    [ -e /etc/genpdsdm/10-mail.conf.org ] && cp -a /etc/genpdsdm/10-mail.conf.org /etc/dovecot/conf.d/10-mail.conf
    #[ -e /etc/genpdsdm/dovecot-openssl.cnf.org ] && cp -a /etc/genpdsdm/dovecot-openssl.cnf.org /usr/share/dovecot/dovecot-openssl.cnf
    if [ $OS != raspbian ] ; then
	[ -e /etc/genpdsdm/amavisd.conf.org ] && cp -a /etc/genpdsdm/amavisd.conf.org /etc/amavisd.conf
    else
	[ -e /etc/genpdsdm/05-node_id.org ] && cp -a /etc/genpdsdm/05-node_id.org /etc/amavis/conf.d/05-node_id
	[ -e /etc/genpdsdm/05-domain_id.org ] && cp -a /etc/genpdsdm/05-domain_id.org /etc/amavis/conf.d/05-domain_id
	[ -e /etc/genpdsdm/15-content_filter_mode.org ] && \
	    cp -a /etc/genpdsdm/15-content_filter_mode.org /etc/amavis/conf.d/15-content_filter_mode
	[ -e /etc/genpdsdm/20-debian_defaults.org ] && \
	    cp -a /etc/genpdsdm/20-debian_defaults.org /etc/amavis/conf.d/20-debian_defaults
	[ -e /etc/genpdsdm/amavis_conf.d_50-user.org ] && cp -a /etc/genpdsdm/amavis_conf.d_50-user.org /etc/amavis/conf.d/50-user
    fi
    [ -e /etc/postfix/sasl_passwd ] && rm /etc/postfix/sasl_passwd
    [ -e /etc/genpdsdm/dkimtxtrecord.txt ] && rm /etc/genpdsdm/dkimtxtrecord.txt
    [ -e /etc/genpdsdm/opendmarc.conf.org ] && cp -a /etc/genpdsdm/opendmarc.conf.org /etc/opendmarc.conf
    unset MAINCF_done
    unset MASTERCF_done
    unset POSTFIXCERTIFICATES_done
    unset DOVECOT_done
    unset CERTIFICATEDOVECOT_done
    unset AMAVIS_done
    if [ $NEW -eq 0 ] ; then
	unset PARAMETERS_read
	unset COUNTRYCODE
    	unset STATEPROVINCE
    	unset LOCALITYCITY
    	unset ORGANIZATION
    	unset RELAYHOST
    	unset USERNAME
    	unset PASSWORD
    	unset ENAME
    	unset LUSERNAME
    	unset NAME
    fi
    dlog "== End of restoring changed files =="
fi
#
# Find the host name and the domain name of the system
#
dlog "== Section to find host and domain name  =="
message="\
===============================================\n\
= Trying to find host name and domain name... =\n\
==============================================="
[ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
[ $DIAL -eq 0 ] && sleep 3
HOSTNAME="$(cat /etc/hostname)"
count=0
if [ ! -z "$HOSTNAME" ] ; then
    grep "$HOSTNAME" /etc/hosts > /tmp/hosts
#    if [ $OS = raspbian ] ; then
#	grep -v "127.0.1.1" /tmp/hosts > /tmp/hostsn
#	mv /tmp/hostsn /tmp/hosts
#    fi
    [ -e /tmp/hosts ] && count=$(cat /tmp/hosts | wc -l)
    [ $count -ne 1 ] && rm /tmp/hosts && exitmsg "There is more than 1 line in /etc/hosts with the text \"$HOSTNAME\"\n\
You should not have changed anything in /etc/hosts before running this script."
    DOMAINNAME=$(cat /tmp/hosts | tr "\t" " ")
    DOMAINNAME=${DOMAINNAME% *}
    DOMAINNAME=${DOMAINNAME#* }
    DOMAINNAME=${DOMAINNAME#*.}
else
    DOMAINNAME=""
fi
[ -e /tmp/hosts ] && rm /tmp/hosts
dlog "count=$count, domain name=$DOMAINNAME, host name=$HOSTNAME"
grep -q '\.' /etc/hostname
if [ $? -eq 0 -o -z "$HOSTNAME" -o $count -eq 0 -o -z "$DOMAINNAME" ] ; then
    # HOSTNAME not known or contains a dot and/or no DOMAINNAME
    while true ; do
	if [ $DIAL -ne 0 ] ; then
	    echo ""
	    echo Questions about host name and domain name
	    echo ""
	    echo "The host name can be any name and consist of letters, digits, a \"_\" and/or \"-\""
	    echo "This name need not be smtp or mail or imap, which will be used elsewhere in the server"
	    echo -n "Enter the name of the system: "
	    read HOSTNAME
	    echo ""
	    echo "An example of the domain name is: example.com; should at least contain one dot"
	    echo "The script requires the existance of a DNS for this domain with A MX records for the domain"
	    echo "The MX record should point to smtp.<domain_name> or mail.<domain_name>, which both should have"
	    echo "an A record. Also an imap.<domain_name> A record should exist, all with the same IP address"
	    echo -n "Enter the domain name: "
	    read DOMAINNAME
	else
            $dialog1 --form "\
Questions about host name and domain name\n\
The host name can be any name and consist of letters, digits, a \"_\"\n\
and/or \"-\". This name need not be smtp or mail or imap, which will be\n\
used elsewhere in the server. An example of the domain name is:\n\
example.com; should at least contain one dot. The script requires the\n\
existance of a DNS for this domain with a MX records for the domain.\n\
The MX record should point to smtp.<domain_name> or mail.<domain_name>,\n\
which both should have an A record. Also an imap.<domain_name> A record\n\
should exist, all with the same IP address." 15 0 2 \
"Hostname :    " 1 1 "" 1 18 15 15 \
"Domain name : " 2 1 "" 2 18 25 25 2> /tmp/u.tmp
            [ $? -ne 0 ] && exitmsg "Script canceled by user or other error"
            HOSTNAME="$(head -1 /tmp/u.tmp)"
            DOMAINNAME=$(tail -1 /tmp/u.tmp)
            rm /tmp/u.tmp
	fi
	if [ -z "$HOSTNAME" -o -z "$DOMAINNAME" ] ; then
	    message="Hostname and Domainname must not be empty!"
            [ $DIAL -ne 0 ] && echo "$message" || $dialog1 --msgbox "$message" 6 50 
	else
	    break
	fi
    done
    # further checkes on names
    message="\n\
============================================\n\
= Checking for existing records in the DNS =\n\
============================================"
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 7 0
    [ $DIAL -eq 0 ] && sleep 5
    message="Errors found by checking:"
    n=0
    nslookup -query=A $DOMAINNAME > /tmp/Adomain
    [ $? -ne 0 ] && message="$message\n\n$DOMAINNAME does not have an A record." && n=$(($n+1))
    nslookup -query=MX $DOMAINNAME > /tmp/MXdomain
    [ $? -ne 0 ] && message="$message\n\n$DOMAINNAME does not have an MX record." && n=$(($n+1))
    nslookup -query=A smtp.$DOMAINNAME > /tmp/smtpdomain
    [ $? -ne 0 ] && message="$message\n\nsmtp.$DOMAINNAME does not have an A or CNAME record." && n=$(($n+1))
    nslookup -query=A mail.$DOMAINNAME > /tmp/maildomain
    [ $? -ne 0 ] && message="$message\n\nmail.$DOMAINNAME does not have an A or CNAME record." && n=$(($n+1))
    nslookup -query=A imap.$DOMAINNAME > /tmp/imapdomain
    [ $? -ne 0 ] && message="$message\n\nimap.$DOMAINNAME does not have an A or CNAME record." && n=$(($n+1))
    if [ $n -ne 0 ] ; then
	message="$message\n\n\
Please provide the required records in the DNS for domain\n\
\"$DOMAINNAME\"\n and start the script again."
	[ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" $(($n*2+8)) 60
	exit 1
    fi
    gipaddress=$(grep 'Address:' /tmp/Adomain | tail -1)
    gipaddress=${gipaddress#* }
    sub[0]="smtp" ; sub[1]="mail" ; sub[3]="imap" ; i=0 ; n=0
    for f in /tmp/smtpdomain /tmp/maildomain /tmp/imapdomain ; do
	grep -q "$gipaddress" $f
        [ $? -ne 0 ] && message="Global IP address not in record for ${sub[$i]}.$DOMAINNAME" && n=$(($n+1))
	rm $f
	i=$(($i+1))
    done
    rm /tmp/Adomain /tmp/MXdomain
    if [ $n -ne 0 ] ; then
	message="$message\n\nApparently there is something wrong with the data in the DNS.\n\n\
Please fix it!"
	[ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 7 0
	exit 1
    fi
    #
    # Check if there is already an entry in /etc/hosts for the server, if so remove it and enter such an entry.
    # The entry should be <host_ip_address> <host_name>.<domain_name> <hostname>
    #
    hostip=$(hostname -I)
    hostip=$(echo "$hostip" | tr "\t" " ")
    # keep only the IP4 address
    hostip=${hostip%% *}
    grep -q "$hostip" /etc/hosts
    [ $? -eq 0 ] && sed -i "/$hostip/d" /etc/hosts
    if [ $OS != raspbian ] ; then
	#
	# Insert the entry in /etc/hosts after line with 127.0.0.1[[:blank:]]+localhost\.localdomain
	#
	sed -i -E "/^127.0.0.1[[:blank:]]+localhost\.localdomain/ a $hostip\t$HOSTNAME.$DOMAINNAME $HOSTNAME" /etc/hosts
    else
	sed -i -E "/^127.0.0.1[[:blank:]]+localhost/ a $hostip\t$HOSTNAME.$DOMAINNAME $HOSTNAME" /etc/hosts
    fi
    dlog "IP address and hostname entered in /etc/hosts"
    echo $HOSTNAME > /etc/hostname
    nslookup -query=AAAA smtp.$DOMAINNAME > /tmp/AAAAdomain
    tail -1 /tmp/AAAAdomain | grep -q Address
    if [ $? -eq 0 ] ; then
	message="WARNING: This script supports only a server without an IPv6 address for smtp.$DOMAINNAME\n\n\
Contact the author if you have this requirement."
	[ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --msgbox "$message" 5 0
    fi
    rm /tmp/AAAAdomain
    # count must be 1 when HOSTNAME and DOMAINNAME are set
    count=1
else
    message="Found host name is : ${HOSTNAME}\nDomain name is     : ${DOMAINNAME}"
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 4 60
    [ $DIAL -eq 0 ] && sleep 5
fi
dlog "== End of finding domain name \"$DOMAINNAME\" and host name \"$HOSTNAME\""
dlog "== Check if domain name is OK =="
if [ -z "$DOMAINNAME_done" ] ; then
    message="\nThe domain name \"$DOMAINNAME\" will be used throughout this script\n\
Is this OK?"
    if [ $DIAL -ne 0 ] ; then
	/usr/bin/echo -e -n "${message}\n\nEnter y or Y for OK, anything else is NO and the script will terminate : "
	read answ
    else
	$dialog1 --yesno "${message}\nSelecting NO will terminate the script" 10 60
	[ $? -eq 0 ] && answ="y"
    fi
    case $answ in
	"y" | "Y" ) ;;
	*         ) 
		echo "" > /etc/hostname
		grep DOMAINNAME_done /etc/genpdsdm/genpdsdm.history
	       	[ $? -eq 0 ] && sed -i "/^DOMAINNAME_done/ d" /etc/genpdsdm/genpdsdm.history
		exitmsg "The host name in /etc/hostname will be cleared,\n\
so when you invoke the script again, you will be asked again\n\
for the host name and the domain name."
		  ;;
    esac
    echo "DOMAINNAME_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
if [ "$HOSTNAME.$DOMAINNAME" != "$(hostname --fqdn)" ] ; then
    message="The command (hostname --fqdn) does provide $HOSTNAME.$DOMAINNAME.\n\
This means the system needs to reboot to establish that.
We will reboot in 5 seconds!!!"
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    sleep 5
    reboot
fi
#
# Read other needed parameters
#
if [ $NEW -eq 0 -o $OLD -eq 0 -o -z "$PARAMETERS_read" ] ; then
    message="\
==================================\n\
= Establishing needed parameters =\n\
=================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    [ $DIAL -eq 0 ] && sleep 5
    #
    # Restore possibly earlier changed files
    #
    cp -a /etc/genpdsdm/canonical.org /etc/postfix/canonical
    cp -a /etc/genpdsdm/aliases.org /etc/aliases
    [ -e /etc/postfix/sasl_passwd ] && rm /etc/postfix/sasl_passwd
    #
    message="Questions about the relay host of your provider\n\
We assume the relay host is accessible via port 587\n\
(submission) and requires a user name and password.\n\
An MX record for this name will not be used.\n\n"
    n=0
    while true ; do
	if [ $DIAL -ne 0 ] ; then
	    /usr/bin/echo -e "$message"
	    [ $OLD -eq 0 -o $n -ne 0 -a ! -z "$RELAYHOST" ] && /usr/bin/echo -e "\nA single Enter will take \"$RELAYHOST\" as its value"
	    echo -n -e "\nPlease enter the name of the relayhost: "
	    read relayhost
	    [ -z $relayhost ] && relayhost="$RELAYHOST"
	    [ $OLD -eq 0 -o $n -ne 0 -a ! -z "$USERNAME" ] && /usr/bin/echo -e "\nA single Enter will take \"$USERNAME\" as its value"
	    /usr/bin/echo -e -n "\nPlease enter your user name on the relay host, might be an e-mail address: "
	    read username
	    [ -z $username ] && username="$USERNAME"
	    [ $OLD -eq 0 -o $n -ne 0 -a ! -z "$PASSWORD" ] && /usr/bin/echo -e "\nA single Enter will take \"$PASSWORD\" as its value"
	    echo -n -e "\nPlease enter the password of your account on the relay host: "
	    read password
	    [ -z $password ] && password="$PASSWORD"
	else
	    [ $n -eq 0 ] && n=6
	    $dialog1 --form "${message}\
The username may be an email address." $(($n+9)) 65 3 \
"Relayhost : " 1 5 "$RELAYHOST" 1 20 20 20 \
"Username  : " 2 5 "$USERNAME" 2 20 20 20 \
"Password  : " 3 5 "$PASSWORD" 3 20 20 20 2>/tmp/rup.tmp
            [ $? -ne 0 ] && exitmsg "Script aborted by user or other error"
	    relayhost="$(head -1 /tmp/rup.tmp)"
            username="$(head -2 /tmp/rup.tmp | tail -1 )"
            password="$(tail -1 /tmp/rup.tmp)"
	    rm  /tmp/rup.tmp
	fi
	n=0
	message=""
        RELAYHOST="$relayhost"
	dlog "relayhost=$RELAYHOST"
	if [ -z "$RELAYHOST" ] ; then
	    message="The relay host is empty.\n" && n=$(($n+1))
	else
	    nslookup $RELAYHOST > /tmp/relayhost
	    rcrh=$?
	    rhipaddress=$(grep "Address: " /tmp/relayhost | tail -1)
	    [ $rcrh -ne 0 -o -z "$rhipaddress" ] && \
		message="${message}The name \"$RELAYHOST\" does not seem to exist in a DNS.\n" && n=$(($n+2))
	fi
        USERNAME="$username"
	dlog "username=$USERNAME"
	[ -z "$USERNAME" ] && message="${message}The user name is empty.\n" && n=$(($n+1))
        PASSWORD="$password"
	dlog "password=$PASSWORD"
	[ -z "$PASSWORD" ] && message="${message}The password is empty.\n" && n=$(($n+1))
	if [ $n -eq 0 ] ; then
	    break
	else
	     message="${message}\n"
	     n=$(($n+2))
	fi
    done
    dlog "End asking relayhost etc."
    message="Questions about username and name administrator.\n\n\
The account name of the administrator to be created or\n\
already present in this server. In case it is created, the\n\
password for this account will be 'genpdsdm', but as root you\n\
can easily change it.\n"
    n=0
    while true ; do
	dlog "Asking for administrator etc."
	[ $OLD -ne 0 -a $n -eq 0 ] || [ $NEW -eq 0 -a $n -eq 0 ] && LUSERNAME="" && NAME=""
	if [ $DIAL -ne 0 ] ; then
	    /usr/bin/echo -e "\n=====================\n"
	    [ ! -z "$LUSERNAME" ] && message="${message}\nA single Enter will take \"$LUSERNAME\" as its value"
	    /usr/bin/echo -e -n "${message}\n\nPlease enter the account name : "
	    read lusername
	    [ -z $lusername ] && lusername="$LUSERNAME"
	    message=""
	    [ ! -z "$NAME" ] && message="\nA single Enter will take \"$NAME\" as its value"
	    message="${message}\nPlease enter the name of the administrator\n\
for this account"
	    [ $n -eq 0 -a -z "$NAME" ] && message="${message}, like 'John P. Doe' : " || message="${message} : "
	    /usr/bin/echo -e -n "$message"
	    read name
	    [ -z $name ] && name="$NAME"
	else
	    [ $n -eq 0 -a -z "$NAME" ] && message="${message}The full name is something like 'John P. Doe'."
	    [ $n -eq 0 ] && m=14 || m=$(($n+10))
	    $dialog1 --form "$message" $m 65 2 \
"Account name administrator : " 1 5 "$LUSERNAME" 1 35 20 20 \
"Full name                  : " 2 5 "$NAME" 2 35 20 20  2>/tmp/lu.tmp
	    [ $? -ne 0 ] && exitmsg "Script aborted by user or other error in asking name administrator."
	    lusername=$(head -1 /tmp/lu.tmp)
	    name=$(tail -1 /tmp/lu.tmp)
	    rm /tmp/lu.tmp
	    dlog "lusername=$lusername, name=$name"
	fi
	n=0
	dlog "lusername=$lusername, name=$name"
        LUSERNAME="$lusername"
	[ -z "$LUSERNAME" ] && message="The account name of the administator is empty.\n" && n=$(($n+1))
        NAME="$name"
	[ -z "$NAME" ] && message="${message}The full name, comment in /etc/passwd, is empty.\n" && n=$(($n+1))
	if [ $n -eq 0 ] ; then
	    break
	else
	    message="\n${message}Please try again.\n"
	    n=$(($n+2))
	fi
    done
    grep -q "$LUSERNAME" /etc/passwd
    if [ $? -eq 0 ] ; then
	message="\nThe user \"$LUSERNAME\" already exists.\n\
The name as comment may have changed and will be replaced.\n\
The password will remain the same as it is."
	[ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 7 65
       	[ $DIAL -eq 0 ] && sleep 5
        usermod -c "$NAME" "$LUSERNAME" > /dev/null
    else
        useradd -c "$NAME" -m -p genpdsdm "$LUSERNAME" > /dev/null
    fi
    dlog "lusername=$LUSERNAME,name=$NAME"
    n=0
    message="\nWhen sending an email as this user the sender address\n\
will currently be \"${LUSERNAME}@${DOMAINNAME}\"\n\
This will be changed in a canonical name like \"john.p.doe@${DOMAINNAME}\"."
    [ $OLD -ne 0 ] && ENAME=""
    while true ; do
	if [ $DIAL -ne 0 ] ; then
	    [ $OLD -eq 0 -a ! -z "$ENAME" ] && message="${message}\nA single Enter will take \"$ENAME\" as its value"
            echo -n -e "${message}\nEnter the part you want before the @ : "
	    read ename
	    [ -z $ename ] && ename="$ENAME"
	else
	    $dialog1 --form "${message}" 11 0 1 "Part before @ : " 1 5 "$ENAME" 1 30 20 20 2> /tmp/fn.tmp
	    [ $? -ne 0 ] && exitmsg "Script aborted on user request or other error."
	    ename=$(head -1 /tmp/fn.tmp)
	    rm /tmp/fn.tmp
	fi
	n=0
        ENAME="$ename"
	[ -z "$ENAME" ] && message="The part before the @ is empty.\n\nPlease try again\n" && n=1
	[ $n -eq 0 ] && break
    done
    dlog "ename=$ENAME"
    #
    # Parameters for self signed certificates
    #
    message="\n\
Questions about self signed certificates\n\n\
In certificates usually parameters like Country, State, Locality/City, Organization\n\
and Organizational Unit are present.\n\
The script will use \"Certificate Authority\" as the Organizational Unit\n\
for the signing certificate and \"IMAP server\" and \"Email server\"\n\
respectively for Dovecot and Postfix certificates.\n\
Common Names (CN) will be imap.$DOMAINNAME and smtp.$DOMAINNAME.\n"
    n=0
    while true ; do
	if [ $OLD -ne 0 -a $n -eq 0 ] || [ $NEW -eq 0 -a $n -eq 0 ] ; then
            COUNTRYCODE=""
            STATEPROVINCE=""
            LOCALITYCITY=""
            ORGANIZATION=""
	fi
	n=0
	if [ $DIAL -ne 0 ] ; then
	    #
	    # Country code
	    #
	    [ ! -z "$COUNTRYCODE" ] && \
		message="${message}\nA single Enter will take \"$COUNTRYCODE\" as its value"
            echo -n -e "${message}\nEnter the two character country code: "
	    read countrycode
	    [ -z $countrycode ] && countrycode="$COUNTRYCODE"
	    #
	    # State or Province
	    #
	    [ ! -z "$STATEPROVINCE" ] && \
		echo "A single Enter will take \"$STATEPROVINCE\" as its value"
	    echo -n "Enter the name of the STATE or PROVINCE: "
	    read stateprovince
	    [ -z $stateprovonce ] && stateprovince="$STATEPROVINCE"
	    #
	    # Locality or City
	    #
	    [ ! -z "$LOCALITYCITY" ] && \
		echo "A single Enter will take \"$LOCALITYCITY\" as its value"
	    echo -n "Enter the name of the LOCALITY/CITY: "
	    read localitycity
	    [ -z $localitycity ] && localitycity="$LOCALITYCITY"
	    #
	    # Organization
	    #
	    [ ! -z "$ORGANIZATION" ] && \
		echo "A single Enter will take \"$ORGANIZATION\" as its value"
	    echo -n "Enter the name of the ORGANIZATION: "
	    read organization
	    [ -z $organization ] && organization="$ORGANIZATION"
	else
	    [ $n -eq 0 ] && n=7
	    $dialog1 --form "${message}" $(($n+9)) 0 4 \
"Country code        : " 1 5 "$COUNTRYCODE" 1 27 20 20 \
"State/Province      : " 2 5 "$STATEPROVINCE" 2 27 20 20 \
"Locality/City       : " 3 5 "$LOCALITYCITY" 3 27 20 20 \
"Organisation name   : " 4 5 "$ORGANIZATION" 4 27 30 30 2>/tmp/cslo.tmp
	    [ $? -ne 0 ] && exitmsg "Script aborted by user or other error"
	    countrycode=$(head -1 /tmp/cslo.tmp)
	    stateprovince=$(head -2 /tmp/cslo.tmp | tail -1)
	    localitycity=$(head -3 /tmp/cslo.tmp | tail -1)
	    organization=$(tail -1 /tmp/cslo.tmp)
	    rm /tmp/cslo.tmp
	fi
	n=0
	dlog "countrycode=$countrycode, stateprovince=$stateprovince, localitycity=$localitycity, organization=$organization"
	message=""
        COUNTRYCODE="$countrycode"
        if [ -z "$COUNTRYCODE" ] ; then
	    message="${message}\nCountry code is empty."
	    n=$(($n+1))
	elif [ ${#COUNTRYCODE} -ne 2 ] ; then
	    message="${message}\nCountry code is not length 2."
	    n=$(($n+1))
	fi
	COUNTRYCODE=$(echo "$COUNTRYCODE" | tr [a-z] [A-Z])
	STATEPROVINCE="$stateprovince"
	[ -z "$STATEPROVINCE" ] && message="${message}\nState/Province is empty." && n=$(($n+1))
        LOCALITYCITY="$localitycity"
	[ -z "$LOCALITYCITY" ] && message="${message}\nLocality/City is empty." && n=$(($n+1))
        ORGANIZATION="$organization"
	[ -z "$ORGANIZATION" ] && message="${message}\nName organization is empty." && n=$(($n+1))
	if [ $n -eq 0 ] ; then
	    break
	else
	    message="The following errors are found:\n${message}"
	    n=$(($n+1))
	fi
    done
    dlog "== Parameters read; save parameters in history =="
    if [ -z "$PARAMETERS_read" -o $NEW -eq 0 -o $OLD -eq 0 ] ; then
	echo "[$RELAYHOST]:587 $USERNAME:$PASSWORD" >> /etc/postfix/sasl_passwd
	echo "$LUSERNAME	$ENAME" >> /etc/postfix/canonical
        postmap /etc/postfix/sasl_passwd
        postmap /etc/postfix/canonical
    fi
    grep -q RELAYHOST /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "RELAYHOST=\"${RELAYHOST}\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^RELAYHOST=/c RELAYHOST=\"$RELAYHOST\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q USERNAME /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "USERNAME=\"$USERNAME\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^USERNAME=/c USERNAME=\"$USERNAME\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q PASSWORD /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "PASSWORD=\"$PASSWORD\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^PASSWORD=/c PASSWORD=\"$PASSWORD\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q LUSERNAME /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "LUSERNAME=\"$LUSERNAME\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^LUSERNAME=/c LUSERNAME=\"$LUSERNAME\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q -e "^NAME" /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "NAME=\"$NAME\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^NAME=/c NAME=\"$NAME\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q ENAME /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "ENAME=\"$ENAME\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^ENAME=/c ENAME=\"$ENAME\"" /etc/genpdsdm/genpdsdm.history
    fi
    echo "$ENAME:	$LUSERNAME" >> /etc/aliases
    /usr/bin/echo -e "ca:\t\troot" >> /etc/aliases
    grep -q -E "^root:[[:blank:]]" /etc/aliases
    if [ $? -ne 0 ] ; then
        /usr/bin/echo -e "root:\t$LUSERNAME" >> /etc/aliases
    else
        sed -i "/^root:[[:blank:]]/c root:\t$LUSERNAME" /etc/aliases
    fi
    newaliases
    grep -q COUNTRYCODE /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "COUNTRYCODE=\"$COUNTRYCODE\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^COUNTRYCODE=/c COUNTRYCODE=\"$COUNTRYCODE\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q STATEPROVINCE /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "STATEPROVINCE=\"$STATEPROVINCE\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^STATEPROVINCE=/c STATEPROVINCE=\"$STATEPROVINCE\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q LOCALITYCITY /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "LOCALITYCITY=\"$LOCALITYCITY\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^LOCALITYCITY=/c LOCALITYCITY=\"$LOCALITYCITY\"" /etc/genpdsdm/genpdsdm.history
    fi
    grep -q ORGANIZATION /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "ORGANIZATION=\"$ORGANIZATION\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^ORGANIZATION=/c ORGANIZATION=\"$ORGANIZATION\"" /etc/genpdsdm/genpdsdm.history
    fi
    [ -z "$PARAMETERS_read" ] && echo PARAMETERS_read=yes >> /etc/genpdsdm/genpdsdm.history
fi
dlog "== End needed parameters =="
#
# Configuration of the firewall
#
if [ -z "$FIREWALL_config" ] ; then
    message="\
==============================\n\
= Configurating firewalld... =\n\
=============================="
    interf=$(ip r | grep default)
    interf=${interf#*dev }
    interf=${interf% proto*}
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
    [ "$(systemctl is-enabled firewalld.service)" = "disabled" ] && systemctl enable firewalld.service
    [ "$(systemctl is-active firewalld.service)" = "inactive" ] && systemctl start firewalld.service
    [ "$(firewall-cmd --list-interface --zone=public)" != "$interf" ] && firewall-cmd --zone=public --add-interface=$interf
    firewall-cmd --list-services --zone=public | grep -q " smtp "
    [ $? -ne 0 ] && firewall-cmd --zone=public --add-service=smtp
    localdomain=$(ip r | tail -1)
    localdomain=${localdomain%% *}
    [ "$(firewall-cmd --zone=internal --list-sources)" != "$localdomain" ] &&
	firewall-cmd --zone=internal --add-source=$localdomain
    firewall-cmd --list-services --zone=internal | grep " imap "
    [ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=imap
    firewall-cmd --list-services --zone=internal | grep " imaps "
    [ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=imaps
    firewall-cmd --list-services --zone=public | grep -q " imaps "
    [ $? -ne 0 ] && firewall-cmd --zone=public --add-service=imaps
    firewall-cmd --runtime-to-permanent
    echo FIREWALL_config=yes >> /etc/genpdsdm/genpdsdm.history
    [ $DIAL -eq 0 ] && sleep 5
fi
#
# Configuration of /etc/postfix/main.cf
#
if [ -z "$MAINCF_done" -o $NEW -eq 0 ] ; then
    message="\
=======================================\n\
= Configuring /etc/postfix/main.cf... =\n\
======================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    [ -e /etc/genpdsdm/main.cf.org ] && cp -a /etc/genpdsdm/main.cf.org /etc/postfix/main.cf
    postconf "inet_interfaces = all"
    postconf "myhostname = smtp.$DOMAINNAME"
    postconf "mydomain = $DOMAINNAME"
    db_type=$(postconf default_database_type)
    db_type=${db_type##* }
    postconf "alias_maps = ${db_type}:/etc/aliases"
    postconf "mydestination = \$myhostname, \$mydomain, localhost, localhost.\$mydomain, $HOSTNAME.\$mydomain"
    postconf "myorigin = \$mydomain"
    postconf "mynetworks_style = subnet"
    postconf "canonical_maps = ${db_type}:/etc/postfix/canonical"
    postmap /etc/postfix/canonical
    postconf "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_invalid_helo_hostname,\
      reject_non_fqdn_sender, reject_unknown_sender_domain, reject_non_fqdn_recipient, reject_unknown_recipient_domain,\
      reject_unauth_destination, reject_rbl_client zen.spamhaus.org"
    postconf "smtpd_helo_required = yes"
    postconf "home_mailbox = Maildir/"
    postconf "smtpd_sasl_path = private/auth"
    postconf "smtpd_sasl_type = dovecot"
    postconf "smtpd_sasl_auth_enable =yes"
    postconf "smtpd_tls_auth_only = yes"
    postconf "smtpd_tls_ask_ccert = no"
    postconf "smtpd_tls_CApath = /etc/ssl/certs"
    postconf "smtpd_tls_CAfile = /etc/postfix/ssl/cacert.pem"
    postconf "smtpd_tls_cert_file = /etc/postfix/ssl/certs/postfixcert.pem"
    postconf "smtpd_tls_key_file = /etc/postfix/ssl/certs/postfixkey.pem"
    postconf "smtpd_tls_session_cache_database = ${db_type}:/var/lib/postfix/smtpd_tls_session_cache"
    postconf "smtpd_tls_exclude_ciphers = RC4"
    postconf "smtpd_helo_required = yes"
    postconf "smtpd_tls_loglevel = 1"
    postconf "smtpd_tls_security_level = may"
    postconf "smtpd_sasl_local_domain = \$myhostname"
    postconf "smtpd_tls_received_header = yes"
    postconf "smtpd_noop_commands = etrn"
    postconf "smtp_tls_security_level = may"
    postconf "smtp_tls_ciphers = medium"
    postconf "smtp_tls_protocols = >=TLSv1, <=TLSv1.3"
    postconf "smtp_tls_note_starttls_offer = yes"
    postconf "smtp_tls_loglevel = 1"
    postconf "smtp_tls_session_cache_database = ${db_type}:/var/lib/postfix/smtp_tls_session_cache"
    postconf "relayhost = [$RELAYHOST]:587"
    postconf "smtp_sasl_password_maps = ${db_type}:/etc/postfix/sasl_passwd"
    postmap /etc/postfix/sasl_passwd
    postconf "smtp_sasl_auth_enable = yes"
    postconf "smtp_sasl_tls_security_options = noanonymous"
    postconf "smtp_sasl_security_options = noanonymous"
    postconf "smtp_use_tls = yes"
    postconf "policyd-spf_time_limit = 3600"
    postconf "content_filter = amavis:[127.0.0.1]:10024"
    postconf "strict_rfc821_envelopes = yes"
    postconf "disable_vrfy_command = yes"
    grep -q MAINCF_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "MAINCF_done=yes" >> /etc/genpdsdm/genpdsdm.history
    [ $DIAL -eq 0 ] && sleep 5
fi
#
# Configuration of /etc/postfix/master.cf
#
if [ -z "$MASTERCF_done" -o $NEW -eq 0 ] ; then
    message="\
=========================================\n\
= Configuring /etc/postfix/master.cf... =\n\
========================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    [ -e /etc/genpdsdm/master.cf.org ] && cp -a /etc/genpdsdm/master.cf.org /etc/postfix/master.cf
    if [ $OS != raspbian ] ; then
	cat <<EOF > /tmp/sedscript.txt
#/^smtp      inet/a\    -o smtpd_relay_restrictions=check_policy_service,unix:private/policyd-spf,permit\n\
#    -o smtpd_milters=inet:127.0.0.1:8893
/^smtp      inet/a\    -o smtpd_relay_restrictions=check_policy_service,unix:private/policyd-spf,permit
/^#amavis    unix/,/#  -o max_use=20/ s/^#//
/^#submission inet/,/^#   -o smtpd_reject_unlisted_recipient=no/ {
     s/^#//
     s/10024/10026/
     }
/^#   -o smtpd_recipient_restrictions=/,/^#   -o milter_macro_daemon_name=ORIGINATING/ {
     s/^#//
     /milter_macro_daemon_name=ORIGINATING/a\   -o disable_vrfy_command=yes
     }
/^#localhost:10025 inet/,/^#  -o relay_recipient_maps=/ s/#//
EOF
    else
	cat <<EOF > /tmp/sedscript.txt
/^smtp      inet/ a \
\ \ \ \ -o smtpd_relay_restrictions=check_policy_service,unix:private/policyd-spf,permit\n\
    -o smtpd_milters=inet:127.0.0.1:8893\n\
amavis    unix  -       -       y       -       4       smtp\n\
  -o smtp_data_done_timeout=1200\n\
  -o smtp_send_xforward_command=yes\n\
  -o disable_dns_lookups=yes\n\
  -o max_use=20
/^#submission inet/,/^#  -o milter_macro_daemon_name=ORIGINATING/ {
s/#sub/sub/
s/#  -o/  -o/
}
/^  -o smtpd_tls_security_level=encrypt/ a\
\ \ -o content_filter=smtp:[127.0.0.1]:10026
EOF
    fi
    sed -i -f /tmp/sedscript.txt /etc/postfix/master.cf
    if [ $OS = raspbian ] ; then
	cat <<EOF > /tmp/sedscript.txt
/^postlog   unix-dgram/ a \
localhost:10025 inet   n       -       y       -       -       smtpd\n\
  -o content_filter=\n\
  -o smtpd_delay_reject=no\n\
  -o smtpd_client_restrictions=permit_mynetworks,reject\n\
  -o smtpd_helo_restrictions=\n\
  -o smtpd_sender_restrictions=\n\
  -o smtpd_recipient_restrictions=permit_mynetworks,reject\n\
  -o smtpd_data_restrictions=reject_unauth_pipelining\n\
  -o smtpd_end_of_data_restrictions=\n\
  -o smtpd_restriction_classes=\n\
  -o mynetworks=127.0.0.0/8\n\
  -o smtpd_error_sleep_time=0\n\
  -o smtpd_soft_error_limit=1001\n\
  -o smtpd_hard_error_limit=1000\n\
  -o smtpd_client_connection_count_limit=0\n\
  -o smtpd_client_connection_rate_limit=0\n\
  -o receive_override_options=no_unknown_recipient_checks,no_header_body_checks,no_address_mappings\n\
  -o local_header_rewrite_clients=\n\
  -o local_recipient_maps=\n\
  -o relay_recipient_maps=
/^maildrop /,/^  -flags=DRXhu/ s/^/#/
/^uucp /,/^  flags=Fqhu/ s/^/#/
/^ifmail /,/^  flags=F / s/^/#/
EOF
	sed -i -f /tmp/sedscript.txt /etc/postfix/master.cf
    fi
    if [ $OS != raspbian ] ; then
	postconf -M policyd-spf/type='policyd-spf    unix    -    n    n    -    0 spawn user=policyd-spf argv=/usr/lib/policyd-spf-perl'
    else
	postconf -M \
	policyd-spf/type='policyd-spf    unix    -    n    y    -    0 spawn user=policyd-spf argv=/usr/sbin/postfix-policyd-spf-perl'
    fi
    grep -q policyd-spf /etc/passwd
    [ $? -ne 0 ] && useradd -c "SPF Policy Server for Postfix" -d /etc/policyd-spf -s "/sbin/nologin" -r policyd-spf
    grep -q MASTERCF_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "MASTERCF_done=yes" >> /etc/genpdsdm/genpdsdm.history
    [ $DIAL -eq 0 ] && sleep 5
fi
#
# Generation of certificates for postfix
#
if [ -z "$POSTFIXCERTIFICATES_done" -o $NEW -eq 0 -o $OLD -eq 0 ] ; then
    message="\
=====================================\n\
= Generating Certificates for CA... =\n\
====================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    openssl=/usr/bin/openssl
    sslpath=/etc/postfix/ssl
    dovecotpath=/etc/ssl/private
    sslconfig=$sslpath/openssl_postfix.conf
    date="$(date)"
    oldmask=$(umask)
    #
    # Remove what might be left by a previous run
    #
    [ -d $sslpath ] && rm -rf $sslpath/*
    [ -d $dovecotpath ] && rm -rf $dovecotpath/*
    [ ! -f /etc/postfix/openssl_postfix.conf.in ] && cp -a ${0%/*}/openssl_postfix.conf.in /etc/postfix/
    umask 077
    mkdir -p $sslpath/private
    mkdir -p $sslpath/certs
    mkdir -p $sslpath/newcerts
    [ -f $sslpath/serial ] || echo "01" > $sslpath/serial
    touch $sslpath/index.txt
    sed -e "s/@POSTFIX_SSL_COUNTRY@/$COUNTRYCODE/" \
        -e "s/@POSTFIX_SSL_STATE@/$STATEPROVINCE/" \
        -e "s/@POSTFIX_SSL_LOCALITY@/$LOCALITYCITY/" \
        -e "s/@POSTFIX_SSL_ORGANIZATION@/$ORGANIZATION/" \
        -e "s/@POSTFIX_SSL_ORGANIZATIONAL_UNIT@/Certificate Authority/" \
        -e "s/@POSTFIX_SSL_COMMON_NAME@/Certificate Authority/" \
        -e "s/@POSTFIX_SSL_EMAIL_ADDRESS@/ca@$DOMAINNAME/" \
        -e "s/@RANDOM@/${RANDOM}${RANDOM}/" \
        -e "s/@COMMENT@/generated by genpdsdm at $date/" \
        /etc/postfix/openssl_postfix.conf.in > $sslconfig
    $openssl req -days 3653 -config $sslconfig -new -x509 -nodes \
        -keyout $sslpath/private/cakey.pem -out $sslpath/cacert.pem 2>/dev/null
    if [ $? -ne 0 ] ; then
        rm -rf $sslpath
        umask $oldmask
        exitmsg "Error creating CA request/certificate\nAsk author for help"
    fi
    [ $DIAL -eq 0 ] && sleep 5
    message="\
=========================================\n\
= Generating Certificates for postfix.. =\n\
========================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    sed -i -e "/^commonName / s/Certificate Authority/smtp.$DOMAINNAME/" \
	-e "/^organizationalUnitName / s/Certificate Authority/Email server/" \
        -e "s/ca@$DOMAINNAME/postmaster@$DOMAINNAME/" $sslconfig
    $openssl req -config $sslconfig -new -nodes -keyout \
        $sslpath/certs/postfixkey.pem -out $sslpath/certs/postfixreq.pem 2>/dev/null
    if [ $? -ne 0 ] ; then
        rm -rf $sslpath
        umask $oldmask
        exitmsg  "Error creating certificate request for postfix"
    fi
    # signing server certificate for postfix
    $openssl ca -config $sslconfig -notext -batch \
        -out $sslpath/certs/postfixcert.pem \
        -infiles $sslpath/certs/postfixreq.pem 2>/dev/null
    if [ $? -ne 0 ] ; then
        rm -rf $sslpath
        umask $oldmask
        exitmsg "Error signing server certificate for postfix"
    fi
    [ $DIAL -eq 0 ] && sleep 5
    message="\
==========================================\n\
= Generating Certificates for dovecot... =\n\
=========================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    # creating certificate request for dovecot
    [ ! -d $dovecotpath ] && mkdir -p $dovecotpath
    # change Common Name and Organizational Unit
    sed -i -e "s/smtp.$DOMAINNAME/imap.$DOMAINNAME/" \
           -e "s/Email server/IMAP server/" $sslconfig
    $openssl req -config $sslconfig -new -nodes -keyout \
        $dovecotpath/dovecot.pem -out $dovecotpath/dovecotreq.pem 2>/dev/null
    if [ $? -ne 0 ] ; then
        rm -rf $dovecotpath
        rm -rf $sslpath
        umask $oldmask
        exitmsg "Error creating certificate request for dovecot"
    fi
    # signing server certificate for dovecot..."
    $openssl ca -config $sslconfig -notext -batch \
        -out $dovecotpath/dovecot.crt \
        -infiles $dovecotpath/dovecotreq.pem 2>/dev/null
    if [ $? -ne 0 ] ; then
        rm -rf $dovecotpath
        rm -rf $sslpath
        umask $oldmask
        exitmsg "Error signing server certificate for dovecot"
    fi
    chmod 755 $sslpath
    chmod 755 $sslpath/certs
    chmod 644 $sslpath/cacert.pem
    umask $oldmask
    [ ! -f /etc/genpdsdm/dh.pem -a -f ${0%/*}/dh.pem ] && cp -a ${0%/*}/dh.pem /etc/genpdsdm/
    if [ ! -e /etc/dovecot/dh.pem ] ; then
	if [ -e /etc/genpdsdm/dh.pem ] ; then
	    cp /etc/genpdsdm/dh.pem /etc/dovecot/
	else
	    message="WARNING: It might take quite some time (160 minutes on a Raspberry Pi 4B) to finish the following command\n\
===>> openssl dhparam -out /etc/dovecot/dh.pem 4096"
	    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
	    openssl dhparam -out /etc/dovecot/dh.pem 4096
	    cp /etc/dovecot/dh.pem /etc/genpdsdm/
	    dlog "dh.pem generated"
	fi
    fi
    grep -q POSTFIXCERTIFICATES_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "POSTFIXCERTIFICATES_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Configuration of Dovecot
#
if [ -z "$DOVECOT_done" -o $NEW -eq 0 -o $OLD -eq 0 ] ; then
    message="\
==========================\n\
= Configuring dovecot... =\n\
=========================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
    if [ -e /etc/genpdsdm/dovecot.conf.org ] ; then
	cp -a /etc/genpdsdm/dovecot.conf.org /etc/dovecot/dovecot.conf
	cp -a /etc/genpdsdm/10-mail.conf.org /etc/dovecot/conf.d/10-mail.conf
	cp -a /etc/genpdsdm/10-master.conf.org /etc/dovecot/conf.d/10-master.conf
	cp -a /etc/genpdsdm/10-ssl.conf.org /etc/dovecot/conf.d/10-ssl.conf
	#cp -a /etc/genpdsdm/dovecot-openssl.cnf.org /usr/share/dovecot/dovecot-openssl.cnf
	#[ -e /etc/ssl/private/dovecot.crt ] && rm /etc/ssl/private/dovecot.crt
	#[ -e /etc/ssl/private/dovecot.pem ] && rm /etc/ssl/private/dovecot.pem
    fi
    #
    # Configuring dovecot.conf; enable only imap, which is default on raspbian
    #
    [ $OS != rasbian ] && sed -i "/^#protocols = imap/a\protocols = imap" /etc/dovecot/dovecot.conf
    #
    # Configuring imaps, wich is enabled on raspbian, but location of pem files differs from above generated files
    #
    if [ $OS != raspbian ] ; then
	cat <<EOF > /tmp/sedscript.txt
/^#ssl = yes/s/^#//
/^#ssl_cert = </s/^#//
/^#ssl_key = </s/^#//
/^#ssl_dh/s/^#//
EOF
   else
	cat <<EOF > /tmp/sedscript.txt
/^ssl_cert =/ {
s/dovecot/ssl/
s/\.pem/.crt/
}
/^ssl_key =/ {
s/dovecot/ssl/
s/\.key/.pem/
}
/^ssh_dh =/ s@usr/share/@etc@
/^#ssl_prefer_server_ciphers = no/ {
s/#//
s/no/yes/
}
/^#ssl_cipher_list = ALL:\!DH/ a\
ssl_cipher_list = ALL:!aNULL:!eNULL:!EXPORT:!DES:!3DES:!MD5:!PSK:!RC4:!ADH:!LOW@STRENGTH
EOF
    fi
    sed -i -f /tmp/sedscript.txt /etc/dovecot/conf.d/10-ssl.conf
    #
    # Configuring authentication by dovecot
    #
    cat <<EOF > /tmp/sedscript.txt
/^  # Postfix smtp-auth/,/^  #}$/ {
   /^  #unix_listener/s/#//
   /^  #  mode = 0666$/s/#//
   /^    mode = 0666$/a\    user = postfix\n   group = postfix
   /^  #}$/s/#//
   }
EOF
    sed -i -f /tmp/sedscript.txt /etc/dovecot/conf.d/10-master.conf
    # the second line in the next file means: between line which begins with "namespace inbox {"
    # and the line which begins with "}" after the line which contains "  #prefix = " the line
    # with "  prefix = INBOX." should be inserted
    cat <<EOF > /tmp/sedscript.txt
/^#mail_location/a\mail_location = maildir:~/Maildir
/^namespace inbox {/,/^}/ {
/^  #prefix = $/a\  prefix = INBOX.
}
EOF
    [ $OS = raspbian ] && cat <<EOF >> /tmp/sedscript.txt
/^mail_location =/ c \mail_location = maildir:~/Maildir
EOF
    sed -i -f /tmp/sedscript.txt /etc/dovecot/conf.d/10-mail.conf
    #
    [ $(systemctl is-enabled dovecot.service) = "disabled" ] && systemctl enable dovecot.service
    [ $(systemctl is-active dovecot.service) = "inactive" ] && systemctl start dovecot.service
    grep -q -e "^DOVECOT_done" /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "DOVECOT_done=yes" >> /etc/genpdsdm/genpdsdm.history
    [ $DIAL -eq 0 ] && sleep 5
fi
#
# Activate clamav
#
if [ -z "$CLAMAV_activated" ] ; then
    message="\
===================================\n\
= Starting freshclam and clamd... =\n\
==================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
    if [ $OS != raspbian ] ; then
	[ "$(systemctl is-enabled freshclam.service)" != "enabled" ] && systemctl enable freshclam.service
	[ "$(systemctl is-active freshclam.service)" != "active" ] && systemctl start freshclam.service
	[ "$(systemctl is-enabled clamd.service)" != "enabled" ] && systemctl enable clamd.service
	sleep 10 #freshclam needs the first time some time to settle before clamd can be activated
	[ "$(systemctl is-active clamd.service)" != "active" ] && systemctl start clamd.service
    else
	[ "$(systemctl is-enabled clamav-freshclam.service)" != "enabled" ] && systemctl enable clamav-freshclam.service
	[ "$(systemctl is-active clamav-freshclam.service)" != "active" ] && systemctl start clamav-freshclam.service
	[ "$(systemctl is-enabled clamav-daemon.service)" != "enabled" ] && systemctl enable clamav-daemon.service
	sleep 10 #freshclam needs the first time some time to settle before clamd can be activated
	[ "$(systemctl is-active clamav-daemon.service)" != "active" ] && systemctl start clamav-daemon.service
    fi
    sa-update
    echo "CLAMAV_activated=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Configuration of Amavisd-new
#
if [ -z "$AMAVIS_done" -o $NEW -eq 0 -o $OLD -eq 0 ] ; then
    message="\
=========================\n\
= Configuring amavis... =\n\
========================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
    if [ $OS != raspbian ] ; then
	[ -e /etc/genpdsdm/amavisd.conf.org ] && cp -a /etc/genpdsdm/amavisd.conf.org /etc/amavisd.conf
	cat <<EOF > /tmp/sedscript.txt
/^\\\$max_servers = 2/ s/2/1/
/^\\\$mydomain = / c\\\$mydomain = '$DOMAINNAME';
/^\\\$inet_socket_port = 10024;/ s/^/# /
/^# \\\$inet_socket_port = \[10024,10026\]/ s/# //
/^\\\$policy_bank{'ORIGINATING'}/,/^  forward_method => / s/10027/10025/g
/^# \\\$myhostname =/ c\\\$myhostname = '$HOSTNAME.$DOMAINNAME';
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavisd.conf
    else
	[ -e /etc/genpdsdm/05-node_id.org ] && cp -a /etc/genpdsdm/05-node_id.org /etc/amavis/conf.d/05-node_id
	cat <<EOF > /tmp/sedscript.txt
/^chomp/ s/^/#/
/^#\$myhostname/ c\
\$myhostname = \"smtp.$DOMAINNAME\" ;
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/05-node_id
	[ -e /etc/genpdsdm/05-domain_id.org ] && cp -a /etc/genpdsdm/05-domain_id.org /etc/amavis/conf.d/05-domain_id
	cat <<EOF > /tmp/sedscript.txt
/^chomp/ c\
\$mydomain = \"$DOMAINNAME\" ;
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/05-domain_id
	[ -e /etc/genpdsdm/15-content_filter_mode.org ] && \
	    cp -a /etc/genpdsdm/15-content_filter_mode.org /etc/amavis/conf.d/15-content_filter_mode
	cat <<EOF > /tmp/sedscript.txt
/^#@bypass_v/,/^#   \\\%bypass_v/ s/^#//
/^#@bypass_s/,/^#   \\\%bypass_s/ s/^#//
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/15-content_filter_mode
	[ -e /etc/genpdsdm/20-debian_defaults.org ] && \
	    cp -a /etc/genpdsdm/20-debian_defaults.org /etc/amavis/conf.d/20-debian_defaults
	cat <<EOF > /tmp/sedscript.txt
/^\$enable_dkim_verification/ {
s/0/1/
s/disabled to prevent warning/enabled to verify dkim/
}
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/20-debian_defaults
	[ -f /etc/genpdsdm/50-user.org ] && cp /etc/genpdsdm/50-user.org /etc/amavis/conf.d/50-user
	cat <<EOF > /tmp/sedscript.txt
/^#--/i\
\$inet_socket_port = [10024,10026];\n\
\$interface_policy{'10026'} = 'ORIGINATING';\n\
\$policy_bank{'ORIGINATING'} = {  # mail supposedly originating from our users\n\
  originating => 1,  # declare that mail was submitted by our smtp client\n\
  allow_disclaimers => 1,  # enables disclaimer insertion if available\n\
  # notify administrator of locally originating malware\n\
  virus_admin_maps => ["virusalert\\\@\$mydomain"],\n\
  spam_admin_maps  => ["virusalert\\\@\$mydomain"],\n\
  warnbadhsender   => 1,\n\
  # forward to MTA for further processing\n\
  forward_method => 'smtp:[127.0.0.1]:10025',\n\
  # force MTA conversion to 7-bit (e.g. before DKIM signing)\n\
  smtpd_discard_ehlo_keywords => ['8BITMIME'],\n\
  bypass_banned_checks_maps => [1],  # allow sending any file names and types\n\
  terminate_dsn_on_notify_success => 0,  # don't remove NOTIFY=SUCCESS option\n\
};\n\
\$enable_dkim_signing = 1 ;
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/50-user
    fi
    # Make sure virusalert is accepted
    grep -q virusalert /etc/aliases
    [ $? -ne 0 ] && /usr/bin/echo -e "virusalert:\tpostmaster" >> /etc/aliases && newaliases
    #
    # Copy or generate the DKIM pair in /var/db/dkim/
    #
    mkdir -p /var/db/dkim
    if [ $(ls ${0%/*}/${DOMAINNAME}.dkim*.pem 2>/dev/null | wc -l) -ne 0 ] ; then
	cp -a ${0%/*}/${DOMAINNAME}.dkim*.pem /var/db/dkim/
    fi
    if [ $(ls /var/db/dkim/${DOMAINNAME}.dkim*.pem 2>/dev/null | wc -l) -eq 0 ] ; then
	date=$(date --date=now +%Y%m%d)
	amavisd genrsa /var/db/dkim/${DOMAINNAME}.dkim${date}.pem 2048
	chmod 640 /var/db/dkim/$DOMAINNAME.dkim${date}.pem
    else
	date=$(ls /var/db/dkim/${DOMAINNAME}.dkim*.pem | head -1)
	date=${date%.pem}
	date=${date##*dkim}
    fi
    [ $OS = raspbian ] && aconf="/etc/amavis/conf.d/50-user" || aconf="/etc/amavisd.conf"
    nlc=$(cat $aconf | wc -l)
    if [ $OS = raspbian ] ; then
	hc=$(($nlc-2))
	tc=2
    else
	hc=$(($nlc-1))
	tc=1
    fi
    cat <<EOF >> /tmp/dkim.conf
dkim_key(
   '${DOMAINNAME}',
   'dkim${date}',
   '/var/db/dkim/${DOMAINNAME}.dkim${date}.pem'
   );
 @dkim_signature_options_bysender_maps = ( {
   "${DOMAINNAME}" => {
     d   => '${DOMAINNAME}',
     a   => 'rsa-sha256',
     c   => 'relaxed/simple',
     ttl => 10*24*3600
     }
   } );
EOF
    # concatenate begin of amavis configuration, dkim configuration and rest of amavis configuration
    # to ensure a defined return
    #cat <(head -$hc $aconf) /tmp/dkim.conf <(tail -$tc $aconf) > /tmp/amavisd.conf
    head -$hc $aconf > /tmp/amavisd.conf
    cat /tmp/dkim.conf >> /tmp/amavisd.conf
    tail -$tc $aconf >> /tmp/amavisd.conf
    mv /tmp/amavisd.conf $aconf
    rm /tmp/dkim.conf
    if [ $OS != raspbian ] ; then
	chown vscan:root -R /var/db/dkim
    else
	chown amavis:root -R /var/db/dkim
    fi
    if [ ! -e /var/db/dkim/${DOMAINNAME}.dkim${date}.txtrecord ] ; then
	amavisd showkeys > /var/db/dkim/${DOMAINNAME}.dkim${date}.txtrecord
	echo ""
	echo "The DKIM public key to be entered in the DNS is present in the file /var/db/dkim/${DOMAINNAME}.dkim${date}.txtrecord"
	echo ""
    fi
    [ $(systemctl is-enabled amavis.service) = "disabled" ] && systemctl enable amavis.service
    [ $(systemctl is-active amavis.service) = "inactive" ] && systemctl start amavis.service
    grep -q AMAVIS_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "AMAVIS_done=yes" >> /etc/genpdsdm/genpdsdm.history
    [ $DIAL -eq 0 ] && sleep 5
fi
[ -e /tmp/sedscript.txt ] && rm /tmp/sedscript.txt
#
# Configuration of DMARC
#
if [ -z "$DMARC_done" -o $NEW -eq 0 -o $OLD -eq 0 ] ; then
    message="\
=========================\n\
= Configuring DMARC...  =\n\
========================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
    if [ -e /etc/genpdsdm/opendmarc.conf.org ] ; then
	cp -a /etc/genpdsdm/opendmarc.conf.org /etc/opendmarc.conf
    fi
    cat <<EOF > /tmp/sedscript.txt
/^# AuthservID name/ c\AuthservID OpenDMARC
/^# FailureReports false/ c\FailureReports true
/^# IgnoreAuthenticatedClients false$/ c\IgnoreAuthenticatedClients true
/^# RejectFailures false/ s/# //
/^# TrustedAuthservIDs HOSTNAME$/ c\TrustedAuthservIDs $DOMAINNAME
/^Socket / c\Socket inet:8893@localhost
EOF
    if [ $OS != raspbian ] ; then
	cat <<EOF >> /tmp/sedscript.txt
/^# CopyFailuresTo postmaster@localhost/ c\CopyFailuresTo dmarc-failures@$DOMAINNAME
/^# FailureReportsBcc postmaster@example.coom/ c\FailureReportsBcc dmarc-reports-sent@$DOMAINNAME
/^# FailureReportsOnNone false/ c\FailureReportsOnNone true
/^# FailureReportsSentBy USER@HOSTNAME/ c\FailureReportsSentBy postmaster@$DOMAINNAME
/^# HistoryFile / s/^# //
/^# IgnoreHosts / s/^# //
/^# ReportCommand / s/^# //
/^# RequiredHeaders false$/ c\RequiredHeaders true
EOF
    else
	cat <<EOF >> /tmp/sedscript.txt
/^UserID opendmarc$/ a\
CopyFailuresTo dmarc-failures@$DOMAINNAME\n\
FailureReportsBcc dmarc-reports-sent@$DOMAINNAME\n\
FailureReportsOnNone true\n\
FailureReportsSentBy postmaster@$DOMAINNAME\n\
HistoryFile /var/spool/opendmarc/opendmarc.dat\n\
IgnoreHosts /etc/opendmarc/ignore.hosts\n\
ReportCommand /usr/sbin/sendmail -t\n\
RequiredHeaders true
EOF
    fi
    sed -i -f /tmp/sedscript.txt /etc/opendmarc.conf
    grep -q dmarc /etc/aliases
    if [ $? -ne 0 ] ; then
	/usr/bin/echo -e "dmarc-failures:\tpostmaster" >> /etc/aliases
	/usr/bin/echo -e "dmarc-reports-send:\tpostmaster" >> /etc/aliases
	newaliases
    fi
    [ -e /etc/genpdsdm/opendmarc-ignore.hosts.org ] && \
	cp -a /etc/genpdsdm/opendmarc-ignore.hosts.org /etc/opendmarc/ignore.hosts
    [ "$(systemctl is-enabled opendmarc.service)" = "disabled" ] && systemctl enable opendmarc.service
    [ "$(systemctl is-active opendmarc.service)" != "active" ] && systemctl start opendmarc.service
    grep -q DMARC_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "DMARC_done=yes" >> /etc/genpdsdm/genpdsdm.history
    [ $DIAL -eq 0 ] && sleep 5
fi
#
# Restart possibly changed services
#
message="\
=====================================================\n\
= Restarting postfix, dovecot, amavis and opendmarc =\n\
====================================================="
[ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
systemctl restart postfix.service
systemctl restart dovecot.service
systemctl restart amavis.service
systemctl restart opendmarc.service
[ $DIAL -eq 0 ] && sleep 5 && clear
