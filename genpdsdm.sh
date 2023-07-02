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
# Version 1.0
#
# Version designed on openSUSE Leap 15.5 on Raspberry Pi 4B
# This version should also work in other environments of openSUSE
#
# ---------------------------------------------------------------------
#
# this script should be run as user root
#
id | tr "a-z" "A-Z" | egrep -q '^UID=0'
[ $? -ne 0 ] && echo "This script should be executed by root or sudo $0" && exit 1
#
# /etc/genpdsdm/genpdsdm.history keeps the history of already executed parts of this script
#
# initialize the history file of the script or read the history to skip what has been done
#
mkdir -p /etc/genpdsdm
[ -e /etc/genpdsdm/genpdsdm.history ] && source /etc/genpdsdm/genpdsdm.history
NEW=1 ; OLD=1
if [ "$1" != "" ] ; then
    for par in $@
    do
	case $par in
	    "--new" ) NEW=0 ;;
            "--old" ) OLD=0 ;;
	    *       ) echo "Invoke this script with $0 [--new|--old] , try again" && exit 1 ;;
        esac
	[ $NEW -eq 0 -a $OLD -eq 0 ] && echo "Parameters --new and --old are mutually exclusief" && exit 1
    done
fi
#
# Install the required packages
#
if [ -z "${INSTALLATION_done}" ] ; then
    # Check if this a clean system
    if [ -e /etc/zypp/repos.d/postfix-policyd-spf-perl.repo ] ; then
        echo "This is not a clean installed system with only a few required additions"
        echo "Please start with a fresh installation on the boot device"
        exit 1
    fi
    zypper up
    zypper in --no-recommends postfix telnet dovecot amavisd-new spamassassin arc arj\
     lzop clzip rzip melt cabextract lz4 p7zip-full rzsz tnef zoo clamav bind-utils
    if [ ! -e /etc/zypp/repos.d/postfix-policyd-spf-perl ] ; then
	zypper ar https://download.opensuse.org/repositories/devel:/languages:/perl/15.4/ postfix-policyd-spf-perl
	zypper in postfix-policyd-spf-perl
    fi
    if [ ! -e /etc/zypp/repos.d/mail-server ] ; then
	zypper ar https://download.opensuse.org/repositories/server:/mail/15.5/ server-mail
	zypper in opendmarc
        mkdir -p /etc/opendmarc
	if [ ! -e /etc/opendmarc/ignore.hosts ] ; then
	    touch /etc/opendmarc/ignore.hosts
	    chown opendmarc:opendmarc /etc/opendmarc/ignore.hosts
	    chmod 644 /etc/opendmarc/ignore.hosts
	fi
    fi
    # postfix needs to be initialized to obtain a standard situation for this script
    systemctl start postfix.service
    systemctl enable postfix.service
    #
    # Save all files that will get changed by the script
    #
    cp -a /etc/postfix/main.cf /etc/genpdsdm/main.cf.org
    cp -a /etc/postfix/master.cf /etc/genpdsdm/master.cf.org
    cp -a /etc/aliases /etc/genpdsdm/aliases.org
    cp -a /etc/postfix/canonical /etc/genpdsdm/canonical.org
    cp -a /etc/dovecot/dovecot.conf /etc/genpdsdm/dovecot.conf.org
    cp -a /etc/dovecot/conf.d/10-ssl.conf /etc/genpdsdm/10-ssl.conf.org
    cp -a /etc/dovecot/conf.d/10-master.conf /etc/genpdsdm/10-master.conf.org
    cp -a /etc/dovecot/conf.d/10-mail.conf /etc/genpdsdm/10-mail.conf.org
    cp -a /usr/share/dovecot/dovecot-openssl.cnf /etc/genpdsdm/dovecot-openssl.cnf.org
    cp -a /usr/share/dovecot/mkcert.sh /etc/genpdsdm/dovecot-mkcert.sh
    cp -a /etc/amavisd.conf /etc/genpdsdm/amavisd.conf.org
    cp -a /etc/opendmarc.conf /etc/genpdsdm/opendmarc.conf.org
    cp -a /etc/opendmarc/ignore.hosts /etc/genpdsdm/opendmarc-ignore.hosts.org
    echo "INSTALLATION_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
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
    [ -e /etc/genpdsdm/dovecot-openssl.cnf.org ] && cp -a /etc/genpdsdm/dovecot-openssl.cnf.org /usr/share/dovecot/dovecot-openssl.cnf
    [ -e /etc/genpdsdm/dovecot-mkcert.sh ] && cp -a /etc/genpdsdm/dovecot-mkcert.sh /usr/share/dovecot/mkcert.sh
    [ -e /etc/genpdsdm/amavisd.conf.org ] && cp -a /etc/genpdsdm/amavisd.conf.org /etc/amavisd.conf
    [ -e /etc/postfix/sasl_passwd ] && rm /etc/postfix/sasl_passwd
    [ -e /etc/genpdsdm/dkimtxtrecoed.txt ] && rm /etc/genpdsdm/dkimtxtrecord.txt
    [ -e /etc/genpdsdm/opendmarc.conf.org ] && cp -a /etc/genpdsdm/opendmarc.conf.org /etc/opendmarc.conf
    [ -e /etc/genpdsdm/opendmarc-ignore.hosts.org ] && cp -a /etc/genpdsdm/opendmarc-ignore.hosts.org /etc/opendmarc/ignore.hosts
    [ -d ./demoCA ] && rm -rf ./demoCA
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
    	unset FULLNAME
    	unset LUSERNAME
    	unset NAME
    fi
fi
#
# Find the host name and the domain name of the system
#
echo "Trying to find host name and domain name..."
HOSTNAME=$(cat /etc/hostname)
[ ! -z $HOSTNAME ] && grep $HOSTNAME /etc/hosts > /tmp/hosts
count=0
[ -e /tmp/hosts ] && count=$(cat /tmp/hosts | wc -l) && rm /tmp/hosts
grep -q '\.' /etc/hostname
if [ $? -eq 0 -o -z "$HOSTNAME" -o $count -eq 0 ] ; then
    ipa=$(hostname -I)
    echo ""
    echo Questions about host name and domain name
    echo ""
    echo "The host name can be any name and consist of letters, digits, a \"_\" and/or \"-\""
    echo "This name need not be smtp or mail or imap, which will be used elsewhere in the server"
    echo -n "Enter the name of the system: "
    read HOSTNAME
    echo "An example of the domain name is: example.com; should at least contain one dot"
    echo "The script requires the existance of a DNS for this domain with A MX records for the domain"
    echo "The MX record should point to smtp.<domain_name> or mail.<domain_name>, which both should have"
    echo "an A record. Also an imap.<domain_name> A record should exist, all with the same IP address"
    echo -n "Enter the domain name: "
    read DOMAINNAME
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
    [ $n -ne 0 ] && echo "Please provide the required records in the DNS for domain $DOMAINNAME and start the script again"\
	&& exit 1
    gipaddress=$(grep 'Address:' /tmp/Adomain | tail -1)
    gipaddress=${gipaddress#* }
    sub[0]="smtp" ; sub[1]="mail" ; sub[3]="imap" ; i=0 ; n=0
    for f in /tmp/smtpdomain /tmp/maildomain /tmp/imapdomain ; do
	grep -q "$gipaddress" $f
        [ $? -ne 0 ] && echo "Global IP address not in record for ${sub[$i]}.$DOMAINNAME" && n=$(($n+1))
	rm $f
	i=$(($i+1))
    done
    rm /tmp/Adomain /tmp/MXdomain
    [ $n -ne 0 ] && echo "Apparently there is something wrong with the data in the DNS. Please fix it" && exit 1
    #
    # Check if there is already an entry in /etc/hosts for the server, if so remove it and enter such an entry.
    # The entry should be <host_ip_address> <host_name>.<domain_name> <hostname>
    #
    hostip=$(hostname -I)
    hostip=${hostip% *}
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
    [ $? -eq 0 ] && echo "WARNING: This script supports only a server without an IPv6 address for smtp.$DOMAINNAME"\
      && echo "Contact the author if you have this requirement"
    rm /tmp/AAAAdomain
    echo "The system will reboot now and please run this script again"
    reboot
fi
if [ $count -ne 1 ] ; then    
    echo "There is more than 1 line in /etc/hosts with the text '$HOSTNAME'"
    echo "You should not have changed anything in /etc/hosts before running this script"
    exit 1
fi
line=$(grep $HOSTNAME /etc/hosts)
DOMAINNAME=${line#*$HOSTNAME.}
DOMAINNAME=${DOMAINNAME% *}
if [ -z "${DOMAINNAME_done}" ] ; then
    echo "The domain name \"$DOMAINNAME\" will be used throughout this script"
    echo -n "Is this OK enter y, Y or nothing and press Enter: "
    read answ
    case $answ in
        "y" | "Y" ) ;;
        *) 
	    if [ ! -z "$answ" ] ; then
		echo "The host name in /etc/hostname will be emptied, so when invoke the scrip again"
		echo "You will be asked again for the host name and the domain name"
		echo "The script will exit; you need to invoke the script again"
                echo "" > /etc/hostname
		exit 1
	    fi
	    ;;
    esac
    echo "DOMAINNAME_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Read other needed parameters
#
if [ $NEW -eq 0 -o $OLD -eq 0 -o -z "$PARAMETERS_read" ] ; then
    echo "=============================="
    echo "Establishing needed parameters"
    echo "=============================="
    #
    # Restore possibly earlier changed files
    #
    cp -a /etc/genpdsdm/canonical.org /etc/postfix/canonical
    cp -a /etc/genpdsdm/aliases.org /etc/aliases
    [ -e /etc/postfix/sasl_passwd ] && rm /etc/postfix/sasl_passwd
    #
    echo ""
    echo "Questions about the relay host of your provider"
    echo ""
    echo "We assume the relay host is accessable via port 587 (submission) and"
    echo "requires a user name and password"
    while true ; do
	[ $OLD -eq 0 -a ! -z "$RELAYHOST" ] && echo "A single Enter will take \"$RELAYHOST\" as its value"
	echo -n "Please enter the name of the relayhost: "
	read relayhost
        [ "$relayhost" = "" -a $OLD -eq 0 -a -z "$RELAYHOST" ] && continue
        [ ! -z "$relayhost" ] && RELAYHOST="$relayhost"
        [ -z $RELAYHOST ] && echo "The relay host seems to be empty. Please try again" && continue
	nslookup $RELAYHOST > /tmp/relayhost
	rcrh=$?
	rhipaddress=$(grep "Address: " /tmp/relayhost | tail -1)
	[ $rcrh -eq 0 -a ! -z "$rhipaddress" ] && break
	echo "The name \"$RELAYHOST\" does not seem to exist in a DNS. Please try again"
    done
    while true ; do
	[ $OLD -eq 0 -a ! -z "$USERNAME" ] && echo "A single Enter will take \"$USERNAME\" as its value"
	echo -n "Please enter your user name on the relay host, might be an e-mail address: "
	read username
        [ "$username" = "" -a $OLD -eq 0 -a -z "$USERNAME" ] && continue
        [ ! -z "$username" ] && USERNAME="$username"
	[ ! -z "$USERNAME" ] && break
	echo "The user name seems to be empy. Please try again"
    done
    while true ; do
	[ $OLD -eq 0 -a ! -z "$PASSWORD" ] && echo "A single Enter will take \"$PASSWORD\" as its value"
	echo -n "Please enter the password of your account on the relay host: "
	read password
        [ "$password" = "" -a $OLD -eq 0 -a -z "$PASSWORD" ] && continue
        [ ! -z "$password" ] && PASSWORD="$password"
	[ ! -z "$PASSWORD" ] && break
	echo "The password seems to be empy. Please try again"
    done
    while true ; do
	[ $OLD -eq 0 -a ! -z "$LUSERNAME" ] && echo "A single Enter will take \"$LUSERNAME\" as its value"
	echo -n "Please enter the account name to be created in this server: "
	read lusername
        [ "$lusername" = "" -a $OLD -eq 0 -a -z "$LUSERNAME" ] && continue
        [ ! -z $lusername ] && LUSERNAME="$lusername"
	[ ! -z "$LUSERNAME" ] && break
	echo "The local account name seems to be empy. Please try again"
    done
    echo "The password for this account will be 'genpdsdm', but as root you can easily change it"
    while true ; do
	[ $OLD -eq 0 -a ! -z "$NAME" ] && echo "A single Enter will take \"$NAME\" as its value"
	echo -n "Please enter your name to be used with this account, like 'John P. Doe': "
	read name
        [ "$name" = "" -a $OLD -eq 0 -a -z "$NAME" ] && continue
        [ ! -z "$name" ] && NAME="$name"
	[ ! -z "$NAME" ] && break
	echo "Your name seems to be empy. Please try again"
    done
    grep -q "$LUSERNAME" /etc/passwd
    if [ $? -eq 0 ] ; then
	echo "The user \"$LUSERNAME\" already exists. Your name as comment may have changed and will be replaced."
	echo "The password will remain the same as it is"
        usermod -c "$NAME" "$LUSERNAME"
    else
        useradd -c "$NAME" -m -p genpdsdm "$LUSERNAME"
    fi
    while true ; do
	echo "When sending an email as this user the sender address will be \"$LUSERNAME@$DOMAINNAME\""
        echo "You may want to have a canonical sender name like \"John.P.Doe@$DOMAINNAME\""
	[ $OLD -eq 0 -a ! -z "$FULLNAME" ] && echo "A single Enter will take \"$FULLNAME\" as its value"
        echo -n "Enter the part you want before the @ : "
	read fullname
        [ "$fullname" = "" -a $OLD -eq 0 -a -z "$FULLNAME" ] && continue
        [ ! -z "$fullname" ] && FULLNAME="$fullname"
	[ ! -z "$FULLNAME" ] && break
        echo "The canonical sender name seems to be empty. Please try again"
    done
    #
    # Parameters for self signed certificates
    #
    echo ""
    echo "Questions about self signed certificates"
    echo ""
    echo "In certificates usually parameters like Country, State, Locality/City, Organization"
    echo "and Organizational Unit are present. These are not really necessary, but at least a"
    echo "two character country code is required"
    echo "The script will use it own names for Organizational Unit"
    #
    # Country code
    #
    while true ; do
	[ $OLD -eq 0 -a ! -z "$COUNTRYCODE" ] && echo "A single Enter will take \"$COUNTRYCODE\" as its value"
        echo -n "Enter your two character country code: "
        read countrycode
        [ "$countrycode" = "" -a $OLD -eq 0 -a -z "$COUNTRYCODE" ] && continue
        [ ! -z "$countrycode" ] && COUNTRYCODE="$countrycode"
        [ ! -z "$COUNTRYCODE" -a ${#COUNTRYCODE} -eq 2 ] && break
        echo "Empty or not length 2. Please try again"
    done
    COUNTRYCODE=$(echo $COUNTRYCODE | tr [a-z] [A-Z])
    #
    # State or Province
    #
    echo -n "Enter the name of your STATE or PROVINCE"
    if [ $OLD -eq 0 -a ! -z "$STATEPROVINCE" ] ; then
        echo ", but ..."
	echo -n "Enter means take \"$STATEPROVINCE\", a dot '.' means leave empty : "
        read stateprovince
        if [ ! -z "$stateprovince" ] ; then
	    if [ ! "$stateprovince" = "." ] ; then
		STATEPROVINCE="$stateprovince"
            else
		STATEPROVINCE=""
            fi
	fi
    else
	echo ""
	echo -n "Enter means leave empty, anything else means the name : "
        read STATEPROVINCE
    fi
    #
    # Locality or City
    #
    echo -n "Enter the name of your LOCALITY/CITY"
    if [ $OLD -eq 0 -a ! -z "$LOCALITYCITY" ] ; then
        echo ", but ..."
	echo -n "Enter means take \"$LOCALITYCITY\", a dot '.' means leave empty : "
        read localitycity
        if [ ! -z "$localitycity" ] ; then
	    if [ ! "$localitycity" = "." ] ; then
		LOCALITYCITY="$localitycity"
            else
		LOCALITYCITY=""
	    fi
        fi	    
    else
	echo ""
	echo -n "Enter means leave empty, anything else means the name : "
        read LOCALITYCITY
    fi
    #
    # Organization name
    #
    echo -n "Enter the name of your ORGANIZATION"
    if [ $OLD -eq 0 -a ! -z "$ORGANIZATION" ] ; then
        echo ", but ..."
	echo -n "Enter means take \"$ORGANIZATION\", a dot '.' means leave empty : "
        read organization
        if [ ! -z "$organization" ] ; then
	    if [ ! "$organization" = "." ] ; then
		ORGANIZATION="$organization"
            else
		ORGANIZATION=""
	    fi
        fi	    
    else
        echo ""
	echo -n "Enter means leave empty, anything else means the name : "
        read ORGANIZATION
    fi
    #
    #
    #
    echo ""
    echo "The script will use Certificate Authority as the Organizational Unit for the signing certificate"
    echo "and \"IMAP server\" and \"EMAIL server\" respectively for Dovecot and Postfix certificates"
    echo ""
    if [ -z "$PARAMETERS_read" -o $NEW -eq 0 -o $OLD -eq 0 ] ; then
	echo "[$RELAYHOST]:587 $USERNAME:$PASSWORD" >> /etc/postfix/sasl_passwd
	echo "$LUSERNAME	$FULLNAME" >> /etc/postfix/canonical
        postmap /etc/postfix/sasl_passwd
        postmap /etc/postfix/canonical
    fi
    grep -q RELAYHOST /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "RELAYHOST=\"$RELAYHOST\"" >> /etc/genpdsdm/genpdsdm.history
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
    grep -q FULLNAME /etc/genpdsdm/genpdsdm.history
    if [ $? -ne 0 ] ; then
	echo "FULLNAME=\"$FULLNAME\"" >> /etc/genpdsdm/genpdsdm.history
    else
	sed -i "/^FULLNAME=/c FULLNAME=\"$FULLNAME\"" /etc/genpdsdm/genpdsdm.history
    fi
    echo "$FULLNAME:	$LUSERNAME" >> /etc/aliases
    echo "root:	$LUSERNAME" >> /etc/aliases
    echo "ca:	root" >> /etc/aliases
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
#
# Configuration of the firewall
#
if [ -z "$FIREWALL_config" ] ; then
    echo "=========================="
    echo "Configurating firewalld..."
    echo "=========================="
    [ "$(systemctl is-enabled firewalld.service)" = "disabled" ] && systemctl enable firewalld.service
    [ "$(systemctl is-active firewalld.service)" = "inactive" ] && systemctl start firewalld.service
    [ "$(firewall-cmd --list-interface --zone=public)" != "eth0" ] && firewall-cmd --zone=public --add-interface=eth0
    firewall-cmd --list-services --zone=public | grep -q " smtp "
    [ $? -ne 0 ] && firewall-cmd --zone=public --add-service=smtp
    localdomain=$(ip r | tail -1)
    localdomain=${localdomain%% *}
    [ "$(firewall-cmd --zone=internal --list-sources)" != "$localdomain" ] &&
	firewall-cmd --zone=internal --add-source=$localdomain
    firewall-cmd --list-services --zone=internal | grep " imap "
    [ $? -ne 0 ] && firewall-cmd --zone=internal --add-service=imap
    firewall-cmd --list-services --zone=public | grep -q " imaps "
    [ $? -ne 0 ] && firewall-cmd --zone=public --add-service=imaps
    firewall-cmd --runtime-to-permanent
    echo FIREWALL_config=yes >> /etc/genpdsdm/genpdsdm.history
fi
#
# Configuration of /etc/postfix/main.cf
#
if [ -z "$MAINCF_done" -o $NEW -eq 0 ] ; then
    echo "==================================="
    echo "Configuring /etc/postfix/main.cf..."
    echo "==================================="
    [ -e /etc/genpdsdm/main.cf.org ] && cp -a /etc/genpdsdm/main.cf.org /etc/postfix/main.cf
    postconf "inet_interfaces = all"
    postconf "myhostname = smtp.$DOMAINNAME"
    postconf "mydomain = $DOMAINNAME"
    postconf "alias_maps = lmdb:/etc/aliases"
    postconf "mydestination = \$myhostname, \$mydomain, localhost, localhost.\$mydomain, $HOSTNAME.\$mydomain"
    postconf "myorigin = \$mydomain"
    db_type=$(postconf default_database_type)
    db_type=${db_type##* }
    postconf "sender_canonical_maps = ${db_type}:/etc/postfix/sender_canonical"
    postconf "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_invalid_helo_hostname,\
      reject_non_fqdn_sender, reject_unknown_sender_domain, reject_non_fqdn_recipient, reject_unknown_recipient_domain,\
      reject_unauth_destination, reject_rbl_client zen.spamhaus.org"
    postconf "smtpd_helo_required=yes"
    postconf "home_mailbox = Maildir/"
    postconf "smtpd_sasl_path = private/auth"
    postconf "smtpd_sasl_type = dovecot"
    postconf "smtpd_sasl_auth_enable =yes"
    postconf "smtpd_tls_auth_only = yes"
    postconf "smtpd_tls_CAfile = /etc/postfix/cacert.pem"
    postconf "smtpd_tls_cert_file = /etc/postfix/newcert.pem"
    postconf "smtpd_tls_key_file = /etc/postfix/newkey.pem"
    postconf "smtpd_tls_session_cache_database = ${db_type}:/var/lib/postfix/smtpd_tls_session_cache"
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
    postconf "smtp_sasl_auth_enable = yes"
    postconf "smtp_sasl_tls_security_options = noanonymous"
    postconf "smtp_sasl_security_options = noanonymous"
    postconf "smtp_use_tls = yes"
    postconf "policyd-spf_time_limit = 3600"
    postconf "content_filter = amavis:[127.0.0.1]:10024"
    grep -q MAINCF_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "MAINCF_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Configuration of /etc/postfix/master.cf
#
if [ -z "$MASTERCF_done" -o $NEW -eq 0 ] ; then
    echo "====================================="
    echo "Configuring /etc/postfix/master.cf..."
    echo "====================================="
    [ -e /etc/genpdsdm/master.cf.org ] && cp -a /etc/genpdsdm/master.cf.org /etc/postfix/master.cf
    cat <<EOF > /tmp/sedscript.txt
/^smtp      inet/a\    -o smtpd_relay_restrictions=check_policy_service,unix:private/policyd-spf,permit\n\
    -o smtpd_milters=inet:127.0.0.1:8893
/^#amavis    unix/,/#  -o max_use=20/ s/^#//
/^#submission inet/,/^#   -o smtpd_reject_unlisted_recipient=no/ {
     s/10024/10026/
     s/^#//
     }
/^#   -o smtpd_recipient_restrictions=/,/^#   -o milter_macro_daemon_name=ORIGINATING/ s/^#//
/milter_macro_daemon_name=ORIGINATING/a\   -o disable_vrfy_command=yes
/^#localhost:10025 inet/,/^#  -o relay_recipient_maps=/ s/#//
EOF
    sed -i -f /tmp/sedscript.txt /etc/postfix/master.cf
    postconf -M policyd-spf/type='policyd-spf    unix    -    n    n    -    0 spawn user=policyd-spf argv=/usr/lib/policyd-spf-perl'
    grep -q policyd-spf /etc/passwd
    [ $? -ne 0 ] && useradd -c "SPF Policy Server for Postfix" -d /etc/policyd-spf -s "/sbin/nologin" -r policyd-spf
    grep -q MASTERCF_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "MASTERCF_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Generation of certificates for postfix
#
if [ -z "$POSTFIXCERTIFICATES_done" -o $NEW -eq 0 ] ; then
    echo "======================================"
    echo "Generating Certificates for postfix..."
    echo "======================================"
    #
    # Remove what might be left by a previous run
    #
    [ -d ./demoCA ] && rm -rf ./demoCA
    ls *.pem > /dev/null 2>&1
    [ $? -eq 0 ] && rm *.pem
    # The following commands are a copy of what "/usr/share/ssl/misc/CA.pl -newca" would do, except
    # that we add '-subj "<parameters"' to provide what else would be asked for
    mkdir ./demoCA
    mkdir ./demoCA/certs
    mkdir ./demoCA/crl
    mkdir ./demoCA/newcerts
    mkdir ./demoCA/private
    touch ./demoCA/index.txt
    echo "01" > ./demoCA/crlnumber
    openssl req  -new -keyout ./demoCA/private/cakey.pem -out ./demoCA/careq.pem \
      -subj "/C=$COUNTRYCODE/ST=$STATEPROVINCE/L=$LOCALITYCITY/O=$ORGANIZATION/OU=Certificate Authority/emailAddress=ca@$DOMAINNAME/CN=Certificate Authority"
    openssl ca  -create_serial -out ./demoCA/cacert.pem -days 3653 -batch -keyfile ./demoCA/private/cakey.pem\
      -selfsign -extensions v3_ca\
      -subj "/C=$COUNTRYCODE/ST=$STATEPROVINCE/L=$LOCALITYCITY/O=$ORGANIZATION/OU=Certificate Authority/emailAddress=ca@$DOMAINNAME/CN=Certificate Authority/"\
      -infiles ./demoCA/careq.pem
    # Next commands are not necessary because the previous command already has days on 3653
    #openssl x509 -in demoCA/cacert.pem -days 3653 -out ./cacert.pem -signkey demoCA/private/cakey.pem
    #mv ./cacert.pem demoCA/
    openssl req -new -nodes -subj\
      "/CN=smtp.$DOMAINNAME/O=$ORGANIZATION/C=$COUNTRYCODE/ST=$STATEPROVINCE/L=$LOCALITYCITY/emailAddress=postmaster@$DOMAINNAME"\
      -keyout newkey.pem -out newreq.pem
    openssl ca -days 3653 -out newcert.pem -infiles newreq.pem
    cp demoCA/cacert.pem newkey.pem newcert.pem /etc/postfix/
    chmod 644 /etc/postfix/cacert.pem /etc/postfix/newcert.pem
    grep -q POSTFIXCERTIFICATES_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "POSTFIXCERTIFICATES_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Configuration of Dovecot
#
if [ -z "$DOVECOT_done" -o $NEW -eq 0 ] ; then
    echo "======================"
    echo "Configuring dovecot..."
    echo "======================"
    if [ -e /etc/genpdsdm/dovecot.conf.org ] ; then
	cp -a /etc/genpdsdm/dovecot.conf.org /etc/dovecot/dovecot.conf
	cp -a /etc/genpdsdm/10-mail.conf.org /etc/dovecot/conf.d/10-mail.conf
	cp -a /etc/genpdsdm/10-master.conf.org /etc/dovecot/conf.d/10-master.conf
	cp -a /etc/genpdsdm/10-ssl.conf.org /etc/dovecot/conf.d/10-ssl.conf
	cp -a /etc/genpdsdm/dovecot-mkcert.sh /usr/share/dovecot/mkcert.sh
	cp -a /etc/genpdsdm/dovecot-openssl.cnf.org /usr/share/dovecot/dovecot-openssl.cnf
	[ -e /etc/ssl/private/dovecot.crt ] && rm /etc/ssl/private/dovecot.crt
	[ -e /etc/ssl/private/dovecot.pem ] && rm /etc/ssl/private/dovecot.pem
    fi
    sed -i "/^#protocols = imap/a\protocols = imap" /etc/dovecot/dovecot.conf
    cat <<EOF > /tmp/sedscript.txt
/^#ssl = yes/s/^#//
/^#ssl_cert = </s/^#//
/^#ssl_key = </s/^#//
/^#ssl_dh/s/^#//
EOF
    sed -i -f /tmp/sedscript.txt /etc/dovecot/conf.d/10-ssl.conf
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
    sed -i -f /tmp/sedscript.txt /etc/dovecot/conf.d/10-mail.conf
    [ $(systemctl is-enabled dovecot.service) = "disabled" ] && systemctl enable dovecot.service
    [ $(systemctl is-active dovecot.service) = "inactive" ] && systemctl start dovecot.service
    grep -q DOVECOT_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "DOVECOT_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Generate certificates for dovecot
#
if [ -z "$CERTIFICATEDOVECOT_done" -o $NEW -eq 0 ] ; then
    echo "====================================="
    echo "Generating certificate for dovecot..."
    echo "====================================="
    cat <<EOF > /tmp/sedscript.txt
/^#C=FI/c C=$COUNTRYCODE
/^#ST=/c ST=$STATEPROVINCE
/^#L=Helsinki/c L=$LOCALITYCITY
/^#O=Dovecot/c O=$ORGANIZATION
/^CN=imap.example.com/c CN=imap.$DOMAINNAME
/^emailAddress=/c emailAddress=postmaster@$DOMAINNAME
EOF
    sed -i -f /tmp/sedscript.txt /usr/share/dovecot/dovecot-openssl.cnf
    sed -i '/365/ s/365/3653/' /usr/share/dovecot/mkcert.sh
    chmod 700 /usr/share/dovecot/mkcert.sh
    folder=$(pwd)
    cd /usr/share/dovecot/
    ./mkcert.sh
    cd $folder
    if [ ! -e /etc/dovecot/dh.pem ] ; then
	if [ -e /etc/genpdsdm/dh.pem ] ; then
	    cp /etc/genpdsdm/dh.pem /etc/dovecot/
	else
	    echo "WARNING: It might take quite some time (160 minutes on a Raspberry Pi 4B) to finish the following command"
	    openssl dhparam -out /etc/dovecot/dh.pem 4096
	    cp /etc/dovecot/dh.pem /etc/genpdsdm/
	fi
    fi
    grep -q CERTIFICATEDOVECOT_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "CERTIFICATEDOVECOT_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Activate clamav
#
if [ -z "$CLAMAV_activated" ] ; then
    echo "==============================="
    echo "Starting freshclam and clamd..."
    echo "==============================="
    [ "$(systemctl is-enabled freshclam.service)" != "enabled" ] && systemctl enable freshclam.service
    [ "$(systemctl is-active freshclam.service)" != "active" ] && systemctl start freshclam.service
    [ "$(systemctl is-enabled clamd.service)" != "enabled" ] && systemctl enable clamd.service
    sleep 10 #freshclam needs the first time some time to settle before clamd can be activated
    [ "$(systemctl is-active clamd.service)" != "active" ] && systemctl start clamd.service
    sa-update
    echo "CLAMAV_activated=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Configuration of Amavis-new
#
if [ -z "$AMAVIS_done" -o $NEW -eq 0 ] ; then
    echo "====================="
    echo "Configuring amavis..."
    echo "====================="
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
    mkdir -p /etc/amavisd
    if [ $(ls /etc/amavisd/${DOMAINNAME}.dkim*.pem 2>/dev/null | wc -l) -eq 0 ] ; then
	date=$(date --date=now +%Y%m%d)
	amavisd -c /etc/amavisd.conf genrsa /etc/amavisd/${DOMAINNAME}.dkim${date}.pem 2048
	chmod 640 /etc/amavisd/$DOMAINNAME.dkim${date}.pem
	chown root:vscan /etc/amavisd/$DOMAINNAME.dkim${date}.pem
    else
	date=$(ls /etc/amavisd/${DOMAINNAME}.dkim*.pem | tail -1)
	date=${date%.pem}
	date=${date#*dkim}
    fi
    cat <<EOF >> /etc/amavisd.conf
dkim_key(
   '${DOMAINNAME}',
   'dkim${date}',
   '/etc/amavisd/${DOMAINNAME}.dkim${date}.pem'
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
    [ ! -e /etc/amavisd/${DOMAINNAME}.dkim${date}.txtrecord ] && \
	amavisd -c /etc/amavisd.conf showkeys > /etc/amavisd/${DOMAINNAME}.dkim${date}.txtrecord
    echo ""
    echo "The DKIM public key to be entered in the DNS is present in the file /etc/amavisd/${DOMAINNAME}.dkim${date}.txtrecord"
    echo ""
    [ $(systemctl is-enabled amavis.service) = "disabled" ] && systemctl enable amavis.service
    [ $(systemctl is-active amavis.service) = "inactive" ] && systemctl start amavis.service
    grep -q AMAVIS_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "AMAVIS_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
[ -e /tmp/sedscript.txt ] && rm /tmp/sedscript.txt
#
# Configuration of DMARC
#
if [ -z "$DMARC_done" -o $NEW -eq 0 ] ; then
    echo "====================="
    echo "Configuring DMARC... "
    echo "====================="
    if [ -e /etc/genpdsdm/opendmarc.conf.org ] ; then
	cp -a /etc/genpdsdm/opendmarc.conf.org /etc/opendmarc.conf
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
	grep -q dmarc /etc/aliases
	if [ $? -ne 0 ] ; then
	    echo -e "dmarc-failures:\t\tpostmaster" >> /etc/aliases
	    echo -e "dmarc-reports-send:\tpostmaster" >> /etc/aliases
	    newaliases
	fi
    fi
    [ -e /etc/genpdsdm/opendmarc-ignore.hosts.org ] && \
	cp -a /etc/genpdsdm/opendmarc-ignore.hosts.org /etc/opendmarc/ignore.hosts
    [ "$(systemctl is-enabled opendmarc.service)" = "disabled" ] && systemctl enable opendmarc.service
    [ "$(systemctl is-active opendmarc.service)" != "active" ] && systemctl start opendmarc.service
    grep -q DMARC_done /etc/genpdsdm/genpdsdm.history
    [ $? -ne 0 ] && echo "DMARC_done=yes" >> /etc/genpdsdm/genpdsdm.history
fi
#
# Restart possibly changed services
#
echo "======================================"
echo "Restarting postfix, dovecot and amavis"
echo "======================================"
systemctl restart postfix.service
systemctl restart dovecot.service
systemctl restart amavis.service
systemctl restart opendmarc.service
