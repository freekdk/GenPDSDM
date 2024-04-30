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
# Version 1.4.0 Added support for additional destination domains
#
# Version designed on openSUSE Leap 15.5 on Raspberry Pi 4B
# This version should also work in other environments of openSUSE
# Tested also on Tumbleweed and x86_64
# Tested in Rasbberry Pi OS (bookworm) Lite 32 bit and 64 bit on Rasberry Pi 4B
#
# ---------------------------------------------------------------------
#
# this script should be run as user root
#
INSTDATE="$(date +'%Y-%m-%d_%H%M%S')"
LOGFILE=/var/log/genpdsdm-$INSTDATE.log
debug=0 # enables logfile
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
    [ $debug -eq 0 ] && echo "$1" >> $LOGFILE
}
#
# wrren: write or renew parameter - might be an indexed parameter - in file parameters
#
wrren() {
    p=$(echo $1 | tr '[]' '..')
    grep -q "^$p" /etc/genpdsdm/parameters
    [ $? -eq 0 ] && sed -i "/^$p/ d" /etc/genpdsdm/parameters
    if [ ${1:0:1} != "#" ] ;then
        [ "$p" = "$1" ] && eval p='$'$1 || eval p='$'{$1}
        echo ${1}=\"$p\" >> /etc/genpdsdm/parameters
    else
	# test on $1 ending on ] (indexed parameter)
        if [ ${1: -1} = "]" ] ; then
	    # (#PAR[0] -> PAR[0])
	    p=${1:1}
            p={$p}
            eval p='$'$p
            echo ${1}=$p >> /etc/genpdsdm/parameters
        else
            eval p='$'${1:1}
            echo ${1}=$p >> /etc/genpdsdm/parameters
        fi
    fi
}

# echo and log
outlog() {
  echo "${*}"
  do_log "${*}"
}

# write log
do_log() {
  if [ ! -f ${LOGFILE} ]; then
    touch ${LOGFILE}
    chmod 600 ${LOGFILE}
    outlog "Log ${LOGFILE} started."
    outlog "ATTENTION: the log file contains sensitive information (e.g. passwords, "
  fi
  echo "$(date +'%Y-%m-%d_%H%M%S') ### ${*}" >>${LOGFILE}
}

# execute and log
# make sure, to be run command is passed within '' or ""
#    if redirects etc. are used
run() {
  do_log "Running: ${*}"
  eval ${*} >>${LOGFILE} 2>&1
  RET=${?}
  if [ ${RET} -ne 0 ]; then
    dlog "EXIT CODE NOT ZERO (${RET})!"
  fi
  return ${RET}
}

# initialize NEW, OLD and DIAL as not activated
NEW=1 ; OLD=1 ; DIAL=1
grep -q "Tumbleweed" /etc/os-release && OS="openSUSE_Tumbleweed"
grep -q "Leap 15.5" /etc/os-release && OS="15.5"
grep -q "Leap 15.6" /etc/os-release && OS="15.6"
egrep -q "raspbian|ID=debian" /etc/os-release && OS="raspbian"
if [ ! -x /usr/bin/dialog ] ; then
    [ "$OS" = "raspbian" ] && run 'apt-get -y install dialog' || run 'zypper in -y dialog'
fi
[ "$OS" = "" ] && exitmsg "Only openSUSE Tumbleweed, Leap 15.5/15.6 and Raspbian are supported"
#
# /var/log/genpdsdm-<date-time> .log keeps track of what has been done during running the script
# /etc/genpdsdm/parameters keeps track of what has been done already and holds parameter values
#
# initialize the parameters file of the script or read the parameters to skip what has been done
#
if [ ! -f ${0%/*}/openssl_postfix.conf.in ] ; then
    echo -e "\
===============================================================\n\
The file ${0%/*}/openssl_postfix.conf.in is missing.\n\
Please provide this file!! The script will exit!!\n\
==============================================================="
    exit 1
fi
[ ! -d /var/adm/backup/genpdsdm ] && mkdir -p /var/adm/backup/genpdsdm
#
# read the parameters file if present and set the available parameters
#
[ ! -d /etc/genpdsdm ] && mkdir -p /etc/genpdsdm
if [ -f /etc/genpdsdm/parameters ] ; then
    . /etc/genpdsdm/parameters
    # parameters with passwwords are present as comment in the file parameters; set these as parameters also
    PASSWORD="$(grep '^#PASSWORD=' /etc/genpdsdm/parameters)"
    [ -n "$PASSWORD" ] && PASSWORD=${PASSWORD#*=} || unset PASSWORD
    j=0
    rc=0
    # To be able to have even the characters ', ", and $ in a password the following trick is used
    # they are stored with a # in the first position, the parameter name followed by the index and =
    # the trick is that what follows the = is stored verbose in the indexed parameter PAR[n]
    # what is entered with read and in dialog is taken verbose and written verbose in parameters
    # and assigned to the indexed parameter
    while [ $rc -eq 0 ]
    do
	PASSW[$j]="$(grep "^#PASSW.$j.=" /etc/genpdsdm/parameters)"
	rc=$?
	[ $rc -eq 0 ] && PASSW[$j]=${PASSW[$j]#*=} || unset PASSW[$j]
	j=$(($j+1))
    done
fi
help="\nUse genpdsdm [OPTIONS]\n\n\
Generates configurations for Postfix, Dovecot, SPL, DKIM and DMARC from\n\
scratch. When invoked for the first time all necessary packets will be\n\
installed and all files, that will be changed, are saved to be able to\n\
start all over again, even much later in the livetime of the system.\n\
When starting the script without --old or --new, and the script has\n\
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
	    --help  ) [ $DIAL -ne 0 ] && /usr/bin/echo -e "$help" || $dialog1 --msgbox "$help" 20 0
		      exit
		      ;;
	    --dial* ) DIAL=0 ;;
	    *       ) echo "Invoke this script with $0 [--dial[og]] [--new|--old] , try again" && exit 1 ;;
        esac
	[ $NEW -eq 0 -a $OLD -eq 0 ] && echo "Parameters --new and --old are mutually exclusief" && exit 1
    done
fi
id | tr "a-z" "A-Z" | egrep -q '^UID=0'
[ $? -ne 0 ] && exitmsg "This script should be executed by root or sudo $0"
#
# Install the required packages
#
dlog "== Starting Installation =="
if [ -z "$INSTALLATION_done" ] ; then
    if [ $OS != raspbian ] ; then 
	# Check if this a clean system
	if [ -f /etc/zypp/repos.d/postfix-policyd-spf-perl.repo ] ; then
            exitmsg "This is not a clean installed system with only a few required additions\n\
Please start with a fresh installation on the boot device. Removing,\n\
first, the 5 involved packages and the non-standard repositories is\n\
also possible."
	fi
	[ "$OS" = "openSUSE_Tumbleweed" ] && run 'zypper dup -y'
	[ "${OS:0:3}" = "15." ] && run 'zypper up -y'
	run 'zypper in -y --no-recommends postfix telnet dovecot spamassassin clzip rzip melt cabextract\
	    lz4 p7zip-full clamav bind-utils openssl cyrus-sasl-plain perl-Socket6'
	run 'zypper in  -y --recommends amavisd-new'
	if [ ! -f /etc/zypp/repos.d/postfix-policyd-spf-perl ] ; then
	    run "zypper ar https://download.opensuse.org/repositories/devel:/languages:/perl/$OS/ postfix-policyd-spf-perl"
	    zypper ref
	    run 'zypper in -y postfix-policyd-spf-perl'
	    # disable repository for not having conflicts during updates
	    run 'zypper mr -d postfix-policyd-spf-perl'
	fi
	[ $OS = 15.6 ] && OSl=15.5 || OSl=$OS
	if [ "${OS:0:3}" = "15." -a ! -f /etc/zypp/repos.d/lang-perl.repo ] ; then
	    run "zypper ar https://download.opensuse.org/repositories/home:fdekruijf:branches:devel:languages:perl:CPAN-D/$OSl/ lang-perl"
	    zypper ref
#	    run 'zypper in -y perl-Domain-PublicSuffix'
	fi
	if [ ! -f /etc/zypp/repos.d/mail-server ] ; then
	    run "zypper ar https://download.opensuse.org/repositories/server:/mail/$OSl/ server_mail"
	    zypper ref server_mail
	    run 'zypper in -y --no-recommends opendmarc'
	    # disable repository for not having conflicts during updates
            run 'zypper mr -d server_mail'
	fi
    else
	run 'apt-get -y update'
	run 'apt-get -y upgrade'
	run 'debconf-set-selections postfixsettings.txt'
	run 'apt-get -y install postfix dovecot-imapd postfix-policyd-spf-perl spamassassin opendmarc'
	run 'apt-get -y install amavisd-new arj cabextract clamav-daemon lhasa libnet-ldap-perl libsnmp-perl lzop\
	    nomarch rpm libcrypt-des-perl clamav-freshclam clamav-docs firewalld pyzor razor bind9-dnsutils dialog'
	run 'usermod -G amavis clamav'
	[ -f /usr/share/dovecot/dh.pem ] && cp -a /usr/share/dovecot/dh.pem /etc/genpdsdm/
    fi
    mkdir -p /etc/opendmarc
    if [ ! -f /etc/opendmarc/ignore.hosts ] ; then
	touch /etc/opendmarc/ignore.hosts
	chown opendmarc:opendmarc /etc/opendmarc/ignore.hosts
	chmod 644 /etc/opendmarc/ignore.hosts
    fi
    
    if [ $OS != raspbian ] ; then 
	# postfix needs to be initialized to obtain a standard situation for this script
	[ "$(systemctl is-active postfix.service)" != "active" ] && run 'systemctl start postfix.service'
	[ "$(systemctl is-enabled postfix,service)" != "enabled" ] && run 'systemctl enable postfix.service'
	#
    fi
    # Save all files that will get changed by the script
    #
    cp -a /etc/postfix/main.cf /var/adm/backup/genpdsdm/main.cf.org
    cp -a /etc/postfix/master.cf /var/adm/backup/genpdsdm/master.cf.org
    [ -f /etc/postfix/sasl_passwd ] && cp -a /etc/postfix/sasl_passwd /var/adm/backup/genpdsdm/sasl_passwd.org
    [ -f /etc/postfix/sender_dependent_relayhost ] && \
	cp -a /etc/postfix/sender_dependent_relayhost /var/adm/backup/genpdsdm/sender_dependent_relayhost.org
    [ -f /etc/postfix/sender_dependent_default_transport ] && \
	cp -a /etc/postfix/sender_dependent_default_transport /var/adm/backup/genpdsdm/sender_dependent_default_transport.org
    [ -f /etc/postfix/tls_per_site ] && cp -a /etc/postfix/tls_per_site /var/adm/backup/genpdsdm/tls_per_site.org
    if [ $OS != raspbian ] ; then 
	cp -a /etc/postfix/canonical /var/adm/backup/genpdsdm/canonical.org
    else
	touch /var/adm/backup/genpdsdm/canonical.org
    fi
    cp -a /etc/dovecot/dovecot.conf /var/adm/backup/genpdsdm/dovecot.conf.org
    cp -a /etc/dovecot/conf.d/10-ssl.conf /var/adm/backup/genpdsdm/10-ssl.conf.org
    cp -a /etc/dovecot/conf.d/10-master.conf /var/adm/backup/genpdsdm/10-master.conf.org
    cp -a /etc/dovecot/conf.d/10-mail.conf /var/adm/backup/genpdsdm/10-mail.conf.org
    #cp -a /usr/share/dovecot/dovecot-openssl.cnf /var/adm/backup/genpdsdm/dovecot-openssl.cnf.org
    if [ $OS != raspbian ] ; then
	cp -a /etc/amavisd.conf /var/adm/backup/genpdsdm/amavisd.conf.org
    else
	cp -a /etc/amavis/conf.d/05-node_id /var/adm/backup/genpdsdm/05-node_id.org
	cp -a /etc/amavis/conf.d/05-domain_id /var/adm/backup/genpdsdm/05-domain_id.org
	cp -a /etc/amavis/conf.d/15-content_filter_mode /var/adm/backup/genpdsdm/15-content_filter_mode.org
	cp -a /etc/amavis/conf.d/20-debian_defaults /var/adm/backup/genpdsdm/20-debian_defaults.org
	cp -a /etc/amavis/conf.d/50-user /var/adm/backup/genpdsdm/amavis_conf.d_50-user.org
    fi
    cp -a /etc/opendmarc.conf /var/adm/backup/genpdsdm/opendmarc.conf.org
    echo "INSTALLATION_done=yes" >> /etc/genpdsdm/parameters
fi
dlog "== End of installation"
#
# Restore all changed files if OLD or NEW is 0
#
if [ "$OLD" -eq 0 -o "$NEW" -eq 0 ] ; then
    [ -f /var/adm/backup/genpdsdm/main.cf.org ] && cp -a /var/adm/backup/genpdsdm/main.cf.org /etc/postfix/main.cf
    [ -f /var/adm/backup/genpdsdm/master.cf.org ] && cp -a /var/adm/backup/genpdsdm/master.cf.org /etc/postfix/master.cf
    [ -f /var/adm/backup/genpdsdm/sasl_passwd.org ] && cp -a /var/adm/backup/genpdsdm/sasl_passwd.org /etc/postfix/sasl_passwd
    [ -f /var/adm/backup/genpdsdm/sender_dependent_relayhost.org ] && \
	cp -a /var/adm/backup/genpdsdm/sender_dependent_relayhost.org /etc/postfix/sender_dependent_relayhost
    [ -f /var/adm/backup/genpdsdm/sender_dependent_default_transport.org ] && \
	cp -a /var/adm/backup/genpdsdm/sender_dependent_default_transport.org /etc/postfix/sender_dependent_default_transport
    [ -f /var/adm/backup/genpdsdm/tls_per_site.org ] && cp -a /var/adm/backup/genpdsdm/tls_per_site.org /etc/postfix/tls_per_site
    [ -f /var/adm/backup/genpdsdm/canonical.org ] && cp -a /var/adm/backup/genpdsdm/canonical.org /etc/postfix/canonical
    [ -f /var/adm/backup/genpdsdm/dovecot.conf.org ] && cp -a /var/adm/backup/genpdsdm/dovecot.conf.org /etc/dovecot/dovecot.conf
    [ -f /var/adm/backup/genpdsdm/10-ssl.conf.org ] && cp -a /var/adm/backup/genpdsdm/10-ssl.conf.org /etc/dovecot/conf.d/10-ssl.conf
    [ -f /var/adm/backup/genpdsdm/10-master.conf.org ] && cp -a /var/adm/backup/genpdsdm/10-master.conf.org /etc/dovecot/conf.d/10-master.conf
    [ -f /var/adm/backup/genpdsdm/10-mail.conf.org ] && cp -a /var/adm/backup/genpdsdm/10-mail.conf.org /etc/dovecot/conf.d/10-mail.conf
    #[ -f /var/adm/backup/genpdsdm/dovecot-openssl.cnf.org ] && cp -a /var/adm/backup/genpdsdm/dovecot-openssl.cnf.org /usr/share/dovecot/dovecot-openssl.cnf
    if [ $OS != raspbian ] ; then
	[ -f /var/adm/backup/genpdsdm/amavisd.conf.org ] && cp -a /var/adm/backup/genpdsdm/amavisd.conf.org /etc/amavisd.conf
    else
	[ -f /var/adm/backup/genpdsdm/05-node_id.org ] && cp -a /var/adm/backup/genpdsdm/05-node_id.org /etc/amavis/conf.d/05-node_id
	[ -f /var/adm/backup/genpdsdm/05-domain_id.org ] && cp -a /var/adm/backup/genpdsdm/05-domain_id.org /etc/amavis/conf.d/05-domain_id
	[ -f /var/adm/backup/genpdsdm/15-content_filter_mode.org ] && \
	    cp -a /var/adm/backup/genpdsdm/15-content_filter_mode.org /etc/amavis/conf.d/15-content_filter_mode
	[ -f /var/adm/backup/genpdsdm/20-debian_defaults.org ] && \
	    cp -a /var/adm/backup/genpdsdm/20-debian_defaults.org /etc/amavis/conf.d/20-debian_defaults
	[ -f /var/adm/backup/genpdsdm/amavis_conf.d_50-user.org ] && cp -a /var/adm/backup/genpdsdm/amavis_conf.d_50-user.org /etc/amavis/conf.d/50-user
    fi
    [ -f /etc/postfix/sasl_passwd ] && rm /etc/postfix/sasl_passwd
    [ -f /etc/genpdsdm/dkimtxtrecord.txt ] && rm /etc/genpdsdm/dkimtxtrecord.txt
    [ -f /var/adm/backup/genpdsdm/opendmarc.conf.org ] && cp -a /var/adm/backup/genpdsdm/opendmarc.conf.org /etc/opendmarc.conf
    #
    # With OLD or NEW true all generation needs to be done again
    #
    for par in MAINCF_done MASTERCF_done POSTFIXCERTIFICATES_done DOVECOT_done CERTIFICATEDOVECOT_done AMAVIS_done DMARC_done ; do
	sed -i "/^$par/ d" /etc/genpdsdm/parameters
	unset $par
    done
    if [ $NEW -eq 0 ] ; then
	#
	# clear all parameters and get these again
	#
	for par in PARAMETERS_done COUNTRYCODE STATEPROVINCE LOCALITYCITY ORGANIZATION RELAYHOST USERNAME \#PASSWORD ENAME \
	    LUSERNAME NAME BLACKLISTHOSTS
	do
	    sed -i -e "/^$par/ d" /etc/genpdsdm/parameters
	    [ ${par:0:1} = "#" ] && unset ${par:1} || unset $par
	done
	j=0
	while [ "${LDOMAIN[$j]}" != "" ] ; do
	    sed -i -e "/^LDOMAIN.$j./ d" /etc/genpdsdm/parameters
	    unset LDOMAIN[$j]
	    j=$(($j+1))
	done
	j=0
        while [ "${EMAILA[$j]}" != "" ]
        do
	    for par in EMAILA[$j] ADDRELAYS[$j] PORT[$j] USERNAM[$j] \#PASSW[$j]
            do
                pardot=$(echo $par | tr '[]' '..')
                sed -i -e "/^$pardot=/ d" /etc/genpdsdm/parameters
                [ "${par:0:1}" != "#" ] && unset $par || unset ${par:1: -1}[$j]
            done
            j=$(($j+1))
        done
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
DOMAINNAME=""
count=0
if [ ! -z "$HOSTNAME" ] ; then
    grep "$HOSTNAME" /etc/hosts > /tmp/hosts
    if [ $OS = raspbian ] ; then
	grep -v "127.0.1.1" /tmp/hosts > /tmp/hostsn
	mv /tmp/hostsn /tmp/hosts
    fi
    [ -f /tmp/hosts ] && count=$(cat /tmp/hosts | wc -l)
    [ $count -gt 1 ] && rm /tmp/hosts && exitmsg "There is more than 1 line in /etc/hosts with the text \"$HOSTNAME\"\n\
You should not have changed anything in /etc/hosts before running this script."
    if [ $count -eq 1 ] ; then
	DOMAINNAME=$(cat /tmp/hosts | tr "\t" " ")
	DOMAINNAME=${DOMAINNAME##*smtp.}
    fi
fi
[ -f /tmp/hosts ] && rm /tmp/hosts
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
	    echo "This name should not be smtp or mail or imap, these names will be used elsewhere in the server"
	    echo -n "Enter the name of the system: "
	    read HOSTNAME
	    echo ""
	    echo "An example of the domain name is: example.com; should at least contain one dot"
	    echo "The script requires the existence of a DNS for this domain with A MX records for the domain"
	    echo "The MX record should point to smtp.<domain_name> or mail.<domain_name>, which both should have"
	    echo "an A record. Also an imap.<domain_name> A record should exist, all with the same IP address"
	    echo -n "Enter the domain name: "
	    read DOMAINNAME
	else
            $dialog1 --form "\
Questions about host name and domain name\n\
The host name can be any name and consist of letters, digits, a \"_\"\n\
and/or \"-\". This name should not be smtp or mail or imap, these names\n\
will be used elsewhere in the server. An example of the domain name is:\n\
example.com; should at least contain one dot. The script requires the\n\
existence of a DNS for this domain with a MX record for the domain.\n\
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
    PROXYIP=$gipaddess
    wrren PROXYIP
    #
    # Check if there is already an entry in /etc/hosts for the server, if so remove it and enter such an entry.
    # The entry should be <host_ip_address> <host_name>.<domain_name> <hostname>
    #
    hostip=$(hostname -I)
    hostip=$(echo "$hostip" | tr "\t" " ")
    # keep only the IP4 address
    hostip=${hostip%% *}
    grep -q "$hostip" /etc/hosts
    [ $? -eq 0 ] && sed -i "/$hostip/ d" /etc/hosts
    #
    # Insert the entry in /etc/hosts after line with 127.0.0.1[[:blank:]]+localhost
    #
    sed -i -E "/^127.0.0.1[[:blank:]]+localhost/ a $hostip\t$HOSTNAME.$DOMAINNAME $HOSTNAME smtp.$DOMAINNAME" /etc/hosts
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
		grep DOMAINNAME_done /etc/genpdsdm/parameters
	       	[ $? -eq 0 ] && sed -i "/^DOMAINNAME_done/ d" /etc/genpdsdm/parameters
		exitmsg "The host name in /etc/hostname will be cleared,\n\
so when you invoke the script again, you will be asked again\n\
for the host name and the domain name."
		  ;;
    esac
    echo "PROXYIP=$PROXYIP" >> /etc/genpdsdm/parameters
    echo "DOMAINNAME_done=yes" >> /etc/genpdsdm/parameters
fi
dlog "Check $HOSTNAME.$DOMAINNAME is OK."
if [ "$HOSTNAME.$DOMAINNAME" != "$(hostname --fqdn)" ] ; then
    message="The command (hostname --fqdn) does NOT provide $HOSTNAME.$DOMAINNAME.\n\
This means the system needs to reboot to establish that."
    if [ $DIAL -ne 0 ] ; then
	/usr/bin/echo -e -n "\n\
${message}\nPress Enter to reboot or Ctrl+C to abort : "
	read answ
    else
	$dialog1 --msgbox "$message\nUse Yes to reboot or Cancel to abort" 6 0
	[ $? -ne 0 ] && exit
    fi
    reboot
fi
#
# Read other needed parameters
#
dlog "Start getting parameters"
if [ $NEW -eq 0 -o $OLD -eq 0 -o -z "$PARAMETERS_done" ] ; then
    message="\
==================================\n\
= Establishing needed parameters =\n\
=================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 5 0
    [ $DIAL -eq 0 ] && sleep 5
    #
    # Restore possibly earlier changed files
    #
    cp -a /var/adm/backup/genpdsdm/canonical.org /etc/postfix/canonical
    [ -f /etc/postfix/sasl_passwd ] && rm /etc/postfix/sasl_passwd
    #
    message="Questions about the relay host of your provider\n\
We assume the relay host is accessible via port 587\n\
(submission) and requires a user name and password.\n\
An MX record for this name will not be used."
    n=0
    while true ; do
	if [ $DIAL -ne 0 ] ; then
	    /usr/bin/echo -e "\n$message"
	    [ $OLD -eq 0 -o $n -ne 0 -a ! -z "$RELAYHOST" ] && /usr/bin/echo -e "\nA single Enter will take \"$RELAYHOST\" as its value"
	    echo -n -e "\nPlease enter the name of the relayhost: "
	    read relayhost
	    [ -z $relayhost ] && relayhost="$RELAYHOST"
	    [ $OLD -eq 0 -o $n -ne 0 -a ! -z "$USERNAME" ] && /usr/bin/echo -e "\nA single Enter will take \"$USERNAME\" as its value"
	    /usr/bin/echo -e -n "\nPlease enter your user name on the relay host, might be an e-mail address: "
	    read username
	    [ -z "$username" ] && username="$USERNAME"
	    [ $OLD -eq 0 -o $n -ne 0 -a ! -z "$PASSWORD" ] && /usr/bin/echo -e "\nA single Enter will take \"$PASSWORD\" as its value"
	    echo -n -e "\nPlease enter the password of your account on the relay host: "
	    read password
	    [ -z "$password" ] && password="$PASSWORD"
	else
	    [ $n -eq 0 ] && n=6
	    dlog "n=$n, message=$message"
	    $dialog1 --form "${message}\n\
The username may be an email address." $(($n+8)) 65 3 \
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
	dlog "relayhost=$RELAYHOST, username=$USERNAME, password=$PASSWORD"
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
	     n=$(($n+3))
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
	    [ -z "$lusername" ] && lusername="$LUSERNAME"
	    if [ -n "$lusername" ] ; then
		NAME=$(grep $lusername /etc/passwd)
		NAME=${NAME%:*} # remove shell
		NAME=${NAME%:*} # remove home folder
		NAME=${NAME##*:} # get comment field with name
		PNAME=${NAME}
	    fi
	    message=""
	    [ ! -z "$NAME" ] && message="\nA single Enter will take \"$NAME\" as its value"
	    message="${message}\nPlease enter the name of the administrator\n\
for this account"
	    [ $n -eq 0 -a -z "$NAME" ] && message="${message}, like 'John P. Doe' : " || message="${message} : "
	    /usr/bin/echo -e -n "$message"
	    read name
	    [ -z "$name" ] && name="$NAME"
	else
	    [ $n -eq 0 -a -z "$NAME" ] && message="${message}The full name is something like 'John P. Doe'."
	    [ $n -eq 0 ] && m=14 || m=$(($n+8))
	    $dialog1 --form "$message" $m 65 2 \
"Account name administrator : " 1 5 "$LUSERNAME" 1 35 20 20 \
"Full name                  : " 2 5 "$NAME" 2 35 20 20  2>/tmp/lu.tmp
	    [ $? -ne 0 ] && exitmsg "Script aborted by user or other error in asking name administrator."
	    lusername=$(head -1 /tmp/lu.tmp)
	    name=$(tail -1 /tmp/lu.tmp)
	    rm /tmp/lu.tmp
	    if [ -n "$lusername" ] ; then
                PNAME=$(grep $lusername /etc/passwd)
                PNAME=${PNAME%:*} # remove shell
                PNAME=${PNAME%:*} # remove home folder
                PNAME=${PNAME##*:} # get comment field with name
            fi
	fi
	n=0
	dlog "lusername=$lusername, name=$name, PNAME=$PNAME"
        LUSERNAME="$lusername"
	message=""
	[ -z "$LUSERNAME" ] && message="The account name of the administator is empty.\n" && n=$(($n+1))
        NAME="$name"
	[ -z "$NAME" ] && message="${message}The full name, comment in /etc/passwd, is empty.\n" && n=$(($n+1))
	if [ $n -eq 0 ] ; then
	    break
	else
	    message="${message}\nPlease try again.\n"
	    n=$(($n+2))
	fi
    done
    grep -q "$LUSERNAME" /etc/passwd
    if [ $? -eq 0 ] ; then
	message="The user \"$LUSERNAME\" already exists.\n"
        if [ -n "$PNAME" ] ; then
	    if [ "$PNAME" = "$NAME" ] ; then
		message="${message}The full name did not change.\n"
	    else
		message="${message}The full name has been replaced.\n"
	    fi
	    message="${message}The password remains the same."
	fi
	[ $DIAL -ne 0 ] && /usr/bin/echo -e "\n$message" || $dialog1 --infobox "$message" 5 65
       	[ $DIAL -eq 0 ] && sleep 5
        usermod -c "$NAME" "$LUSERNAME" > /dev/null
    else
        useradd -c "$NAME" -m -p genpdsdm "$LUSERNAME" > /dev/null
	message="The user $LUSERNAME has been created with password \"genpdsdm\"."
	[ $DIAL -ne 0 ] && /usr/bin/echo -e "\n$message" || $dialog1 --msgbox "$message" 5 50
    fi
    dlog "lusername=$LUSERNAME,name=$NAME"
    k=11
    message="When sending an email as this user the sender address\n\
will currently be \"${LUSERNAME}@${DOMAINNAME}\"\n\
This will be changed in a canonical name like\n \"john.p.doe@${DOMAINNAME}\"."
    [ $OLD -ne 0 ] && ENAME=""
    while true ; do
	if [ $DIAL -ne 0 ] ; then
	    [ $OLD -eq 0 -a ! -z "$ENAME" ] && message="${message}\nA single Enter will take \"$ENAME\" as its value"
            echo -n -e "${message}\nEnter the part you want before the @ : "
	    read ename
	    [ -z $ename ] && ename="$ENAME"
	else
	    $dialog1 --form "${message}" $k 60 1 "Part before @ : " 1 5 "$ENAME" 1 25 25 25 2> /tmp/fn.tmp
	    [ $? -ne 0 ] && exitmsg "Script aborted on user request or other error."
	    ename=$(head -1 /tmp/fn.tmp)
	    rm /tmp/fn.tmp
	fi
	n=0 # indicates success
	k=10 # height of window
        ENAME="$ename"
	[ -z "$ENAME" ] && message="The part before the @ is empty.\n\nPlease try again\n" && n=1 # means failure
	[ $n -eq 0 ] && break
    done
    dlog "ename=$ENAME"
    #
    # Question about additional domains to be considered local
    #
    # When OLD is true there might be LDOMAIN values, count number
    ad=0
    while [ "${LDOMAIN[$ad]}" != "" ] ; do
	ad=$(($ad+1))
    done
    message="Currently the server will consider email messages to the following domains as local:\n\
smtp.$DOMAINNAME, $DOMAINNAME, localhost, localhost.$DOMAINNAME, $HOSTNAME.$DOMAINNAME\n"
    i=0
    while [ $i -lt $ad ] ; do
	[ $i -eq 0 ] && message="${message}and additional domain(s): "
	message="${message}${LDOMAIN[$i]} "
	i=$(($i+1))
    done
    while true ; do
	[ $OLD -eq 0 -a $ad -ne 0 ] && \
	    message="${message}\nAre these additional domains OK? Else you need to enter all (again)." || \
	    message="${message}\nDo you want additional domains?"
	if [ $DIAL -ne 0 ] ; then
	    /usr/bin/echo -e -n "\n${message}\nY and y means OK, anything else means No : "
	    read answ
	else
	    $dialog1 --yesno "$message" 8 110
	    [ $? -eq 0 ] && answ="y"
	fi
	case $answ in
	    "y" | "Y" ) [ $OLD -eq 0 -a $ad -ne 0 ] && break
		        ;;
		*     ) if [ $OLD -eq 0 -a $ad -ne 0 ] ; then
			    LDOMAIN[0]=""
		        else
			    break
			fi
		        ;;
	esac
	ad=0 # new additional domains
	while true ; do
	    message="Enter the additional domain name; DNS entry will be checked.\nLeave empty to finish asking.\n"
	    if [ $DIAL -ne 0 ] ; then
		/usr/bin/echo -e -n "\n${message}Domain name: "
		read ldomain
	    else
		$dialog1 --form "$message" 9 75 1 "Domain name: " 1 1 "" 1 15 20 0 2> /tmp/ldomain.tmp
		ldomain=$(head -1 /tmp/ldomain.tmp)
		rm /tmp/ldomain.tmp
	    fi
	    [ "$ldomain" = "" ] && break
	    message=""
	    nslookup -query=MX $ldomain > /tmp/MXdomain
	    if [ $? -ne 0 ] ; then
		    message="$ldomain does not have an MX record\nPlease try again"
	    else
		grep -q smtp.$DOMAINNAME /tmp/MXdomain
		[ $? -ne 0 ] && message="MX record of $ldomain does not point to smtp.$DOMAINNAME\nPlease try again"
		rm /tmp/MXdomain
	    fi
	    if [ "$message" != "" ] ; then
		if [ $DIAL -ne 0 ] ; then
		    /usr/bin/echo -e -n "$message"
		else
		    $dialog1 --infobox "$message" 0 0
		    sleep 5
		fi
		continue
	    else
		LDOMAIN[$ad]="$ldomain"
		ad=$(($ad+1))
	    fi
	done
	break
    done
    #
    # Write one empty LDOMAIN in case the number has been less than before
    j=-1
    until [ $j -eq $ad ] ; do
	j=$(($j+1))
	wrren LDOMAIN[$j]
    done
    #
    # Adding hosts with list for blacklisted hosts
    #
    dlog "Adding hosts with list for blacklisted hosts"
    answ="y"
    if [ $OLD -eq 0 ] ; then
	if [ -n "$BLACKLISTHOSTS" ] ; then
	    message="Host(s) with blacklists is/are:\n$BLACKLISTHOSTS\n"
	    if [ "${BLACKLISTHOSTS#* }" = "$BLACKLISTHOSTS" ] ; then
		message="Host with blacklists is:\n$BLACKLISTHOSTS\nIs this one OK?"
	    else
		message="Hosts with blacklists are:\n$BLACKLISTHOSTS\nAre these OK?"
	    fi
	    if [ $DIAL -ne 0 ] ; then
		/usr/bin/echo -e -n "$message y or Y is OK,\n\
anything else is no and you need to specify again. : "
		read answ
		[ "$answ" = "Y" ] && answ="y"
	    else
		$dialog1 --yesno "${message}\nNo means you have to specify again." 8 60
		[ $? -eq 0 ] && answ="y" || answ="n"
	    fi
	else
	    answ="n"
	fi
    else
	answ="n"
    fi
    if [ "$answ" != "y" ] ; then
	message="Do you want any server with blacklisted hosts?"
	if [ $DIAL -ne 0 ] ; then
	    /usr/bin/echo -e -n "\n$message\nAnswer y or Y for yes, no is anything else : "
	    read answ
	else
	    $dialog1 --yesno "$message" 5 50
	    [ $? -eq 0 ] && answ="y"
	fi
	if [ "${answ:0:1}" = "y" -o "${answ:0:1}" = "Y" ] ; then
	    if [ $DIAL -ne 0 ] ; then
		while true
		do
		    echo -e "\nEnter a combination of 1,2, and 3, which belong to the following options:"
		    echo "1: server bl.spamcop.net"
		    echo "2: server cbl.abuseat.org"
		    echo "3: server zen.spamhaus.org\n: "
		    read answ
		    [ -z "$answ" ] && echo "Please enter the proper digits!!" && continue
		    list=""
		    error=1
		    while [ ${#answ} -ne 0 ]
		    do
			case ${answ:0:1} in
			    "1" ) list="${list}bl.spamcop.net " ;;
			    "2" ) list="${list}cbl.abuseat.org " ;;
			    "3" ) list="${list}zen.spamhaus.org " ;;
			    *   ) echo "Please enter the proper digits!!" && error=0 && break ;;
			esac
			answ="${answ:1}"
		    done
		    [ $error -eq 0 ] && continue
		    [ -n "$list" ] && list="${list% }"
		    break
		done
	    else
		message="Please select one or more of the given hosts with blacklists"
		n=10
		while true
		do
		    $dialog1 --checklist "$message" $n 65 3 'bl.spamcop.net' 1 'off' 'cbl.abuseat.org' 2 'off'\
			'zen.spamhaus.org' 3 'on' 2>/tmp/blacklist.tmp
		    list="$(cat /tmp/blacklist.tmp)"
		    if [ -z "$list" ] ; then
			[ "${message:0:1}" != "N" ] && message="No host selected, please try again\n$message" && n=11
		    else
			break
		    fi
		done
	    fi
	else
	    list=""
	fi
	BLACKLISTHOSTS="$list"
	wrren BLACKLISTHOSTS
    fi
    #
    # Parameters for self signed certificates
    #
    dlog "Parameters for self signed certificates"
    message="\
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
	if [ $DIAL -ne 0 ] ; then
	    #
	    # Country code
	    #
	    [ ! -z "$COUNTRYCODE" ] && \
		message="\n${message}\nA single Enter will take \"$COUNTRYCODE\" as its value"
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
	    [ -z "$stateprovince" ] && stateprovince="$STATEPROVINCE"
	    #
	    # Locality or City
	    #
	    [ ! -z "$LOCALITYCITY" ] && \
		echo "A single Enter will take \"$LOCALITYCITY\" as its value"
	    echo -n "Enter the name of the LOCALITY/CITY: "
	    read localitycity
	    [ -z "$localitycity" ] && localitycity="$LOCALITYCITY"
	    #
	    # Organization
	    #
	    [ ! -z "$ORGANIZATION" ] && \
		echo "A single Enter will take \"$ORGANIZATION\" as its value"
	    echo -n "Enter the name of the ORGANIZATION: "
	    read organization
	    [ -z "$organization" ] && organization="$ORGANIZATION"
	else
	    [ $n -eq 0 ] && n=14 || n=$(($n+7))
	    dlog "n=$n, Country code=$COUNTRYCODE"
	    $dialog1 --form "${message}" $n 0 4 \
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
    #
    # Additional relayhosts
    #
    dlog "Additional relayhosts"
    new=0
    j=0
    if [ $OLD -eq 0 ] ; then
	if [ "${EMAILA[0]}" = "" ] ; then
	    message="Currently there are no additional relayhosts\n\n"
	else
	    message="\
Currently you have the following additional relayhost(s) for\n\
email address(es) with access information:\n\n"
	    while [ "${EMAILA[$j]}" != "" ]
	    do
		message="${message}${EMAILA[$j]}: ${ADDRELAYS[$j]} ${PORT[$j]}\n\
                        ${USERNAM[$j]} ${PASSW[$j]}\n\n"
		dlog "${EMAILA[$j]}: ${ADDRELAYS[$j]} ${PORT[$j]} ${USERNAM[$j]} ${PASSW[$j]}"
		j=$(($j+1))
	    done
	    message="${message}\n"
	fi
	if [ $DIAL -ne 0 ] ; then
	    /usr/bin/echo -e -n "${message}Is this OK? Answer y or Y, otherwise you can add, change or delete some or all : "
	    read answ
	else
	    $dialog1 --yesno "${message}Is this OK? Answer Yes means no change,\n\
Answer No means you can change or delete some or all" $(($j*3+10)) 80
	    [ $? -eq 0 ] && answ="y" || answ="n"
	fi
	[ "$answ" = "y" -o "$answ" = "Y" ] && new=1 # means no change in zero or more additional relay hosts
    fi
    dlog "new=$new, if 0 additional relayhosts will be asked for"
    if [ $new -eq 0 ] ; then
	n=6
	message="\
Apart from sending all your messages with from addresses ...@$DOMAINNAME,\n\
or all the other addresses, to the relay host $RELAYHOST, you may want to\n\
have additional email adresses in the from addres, like some_user@gmail.com,\n\
which you want to send to an additional relay host, i.e. smtp.gmail.com, based\n\
on the from address. Do you want one or more of these additional relay hosts?\n"
	[ $OLD -eq 0 -a "${EMAILA[0]}" != "" ] &&  message="Do you want to delete all additional relay hosts?\n" && n=1
	if [ $DIAL -ne 0 ] ; then
	    /usr/bin/echo -e -n "\n${message}\nAnswer y or Y, anything else will be No : "
	    read answ
	else
	    $dialog1 --yesno "$message" $(($n+4)) 90
	    [ $? -eq 0 ] && answ="y"
	fi
	case "$answ" in
	    "y" | "Y" ) [ $OLD -eq 0 -a "${EMAILA[0]}" != "" ] && new=1 || new=0 ;;
	    *	      ) [ $OLD -eq 0 -a "${EMAILA[0]}" != "" ] && new=0 || new=1 ;;
	esac
    fi
    j=0
    if [ $new -eq 0 ] ; then
	# here, if there are old values, these may be changed
	while true
	do
	    change=1
	    [ $OLD -ne 0 ] && EMAILA[$j]=""
	    if [ $DIAL -ne 0 ] ; then
		# part without use of dialog
		dlog "Entering non-dialog asking for additional relayhosts"
		if [ "${EMAILA[$j]}" != "" ] ; then
		    /usr/bin/echo -e -n "\n\
Email address to be send to additional relay host is: ${EMAILA[$j]},\n\
enter = to not change anything for this email address,\n\
enter c or C to indicate other parameters need some changes,\n\
enter d or D to delete this entry,\n\
press Enter to delete this entry and finish asking for further addresses,\n\
or input a new value for the e-mail address : "
		    read emaila
		    [ "$emaila" = "=" ] && j=$(($j+1)) && continue
		    [ "$emaila" = "c" -o "$emaila" = "C" ] && emaila=${EMAILA[$j]} && change=0
		    [ "$emaila" = "d" -o "emaila" = "D" ] && EMAILA[$j]="" && continue
		    [ "$emaila" = "" ] && EMAILA[$j]="" && break
		else
		    /usr/bin/echo -e -n "\n\
Email address to be send to additional relay host,\n\
press Enter to end asking for these email addresses : "
		    read emaila
		    [ "$emaila" = "" ] && break
		fi
		if [ $change -eq 0 ] ; then
		    /usr/bin/echo -e -n "\
Relay host for this email address is ${ADDRELAYS[$j]},\n\
press Enter to not change it, otherwise enter the new value : "
		    read addrelays
		    [ "$addrelays" = "" ] && addrelays=${ADDRELAYS[$j]}
		else
		    /usr/bin/echo -e -n "\n\
Enter the relay host, like smtp.gmail.com, the connection will be made\n\
to the IP address in the A record of this name in the DNS. A check\n\
will be performed on the existance of such a record.\nAdditional relay host : "
		    read addrelays
		fi
		nslookup -query=a "$addrelays" > /dev/null
		if [ $? -ne 0 ] ; then
		    /usr/bin/echo "\nThe server $addrelays does not have an A record.\n\
This is not supported!! Try again."
		    continue
		fi
		if [ $OLD -eq 0 -a "${PORT[$j]}" != "" -a $change -eq 0 ] ; then
		    /usr/bin/echo -e -n "\nCurrently the port is : ${PORT[$j]} ; Press Enter to leave\n\
it this way, otherwise enter the port number, choices are 465 or 587.\n\
Port : "
		else
		    /usr/bin/echo -e -n "\nEnter the port for access to the relay host; choices are 465 or 587.\n\
Port : "
		fi
		read port
		[ "$port" = "" ] && port=${PORT[$j]}
		[ "$port" != "465" -a "$port" != "587" ] && echo "\nWrong port number. Try again." && continue
		if [ $OLD -eq 0 -a "${USERNAM[$j]}" != "" -a $change -eq 0 ] ; then
		    /usr/bin/echo -e -n "\n\
Currently the username for access to the relay host is ${USERNAM[$j]} ; Press Enter to leave\n\
it this way, otherwise the new username.\n\
Username : "
		else
		    /usr/bin/echo -e -n "\n\
Enter the username for access to the relay host; might be the same as\n\
the email address entered before. If so enter = , else the username\n\
Username : "
		fi
		read username
		[ "$username" = "=" ] &&  username="$emaila"
		[ "$username" = "" ] && username=${USERNAM[$j]}
		[ "$username" = "" ] && /usr/bin/echo -e "\nUsername is empty. Try again." && continue
		if [ $OLD -eq 0 -a "${PASSW[$j]}" != "" -a $change -eq 0 ] ; then
		    /usr/bin/echo -e -n "/nCurrently the password for access to the relay host is ${PASSW[$j]}.\n\
Press Enter to leave it this way, otherwise enter the new password.\n\
Password : "
		else
		    /usr/bin/echo -e -n "\nEnter the password for access to the relay host.\nPassword : "
		fi
		read passw
		[ $OLD -eq 0 -a "${PASSW[$j]}" != "" -a $change -eq 0 -a "$passw" = "" ] && "Password is empty. Try again." && continue
	    else
		dlog "Entering dialog part asking for additional relayhosts"
		# part using dialog
		message="\
In the following fields you are asked to enter the emailaddress in the\n\
from address you want to send to an additional relayhost. The name of the\n\
relay host must have an IP address in the DNS, which will be checked. Such\n\
a relay host uses either port 465 or 587 for access. Also a username and\n\
password is needed. The username may be the same as the email address.\n\
Cancel or an empty Email address ends these questions." && k=17
		[ $OLD -eq 0 -a "${EMAILA[$j]}" != "" ] && message="${message}\n\
Fields have values, so Cancel means that this entry will be deleted." && k=19
		dlog "dialog asking for ${j}th items"
		$dialog1 --form "$message" $k 90 5 \
"Email address    " 1 1 "${EMAILA[$j]}" 1 20 30 30 \
"Relay host       " 2 1 "${ADDRELAYS[$j]}" 2 20 30 30 \
"Port             " 3 1 "${PORT[$j]}" 3 20 4 4 \
"Username         " 4 1 "${USERNAM[$j]}" 4 20 30 30 \
"Password         " 5 1 "${PASSW[$j]}" 5 20 30 30 2>/tmp/erpup.tmp
		[ $? -ne 0 ] && EMAILA[$j]="" && break
		emaila="$(head -1 /tmp/erpup.tmp)"
		addrelays="$(head -2 /tmp/erpup.tmp | tail -1)"
		port="$(head -3 /tmp/erpup.tmp | tail -1)"
		username="$(head -4 /tmp/erpup.tmp | tail -1)"
		passw="$(tail -1 /tmp/erpup.tmp)"
		rm /tmp/erpup.tmp
		dlog "emaila=$emaila, addrelays=$addrelays, port=$port, usenam=$usernam, passw=$passw"
		[ "$emaila" = "" ] && break
		message=""
		k=5
		[ "$emaila" = "${emaila%@*}" ] && message="${message}Email address does not contain an @.\n" && k=$(($k+1))
		if [ "$addrelays" = "" ] ; then
		    message="${message}Relay host is empty.\n" ; k=$(($k+1))
		elif [ "$addrelays" = "${addrelays%.*}" ] ; then
		    message="${message}Relay host does not contain a dot (.)\n" && k=$(($k+1))
		else
		    nslookup -query=a "$addrelays" > /dev/null
		    if [ $? -ne 0 ] ; then
			message="${message}The server $addrelays does not have an A record.\n\
This is not supported!!\n" ; k=$(($k+2))
		    fi
		fi
		[ "$port" != "587" -a "$port" != "465" ] && message="${message}Port must be 587 or 465.\n" k=$(($k+1))
		[ "$username" = "" ] && message="${message}The username can not be empty.\n" && k=$(($k+1))
		[ "$passw" = "" ] && message="${message}The password can not be empty.\n" && k=$(($k+1))
		if [ $k -ne 5 ] ; then
		    message="${message}\nTry again." && k=$(($k+2))
		    dlog "message=$message"
		    $dialog1 --msgbox "$message" $k 50
		    [ $? -ne 0 ] && exitmsg "Script canceled by user or other error"
		    continue
		fi
	    fi
	    EMAILA[$j]="$emaila"
	    ADDRELAYS[$j]="$addrelays"
	    PORT[$j]="$port"
	    USERNAM[$j]="$username"
	    [ "$passw" != "" ] && PASSW[$j]=$passw
	    j=$(($j+1))
	done
	dlog "j=$j, emaila=$emaila, EMAILS[$j]=${EMAILA[$j]}"
	EMAILA[$j]="" 
    fi # end of new
    dlog "== Parameters read; save parameters in parameters =="
    j=0
    while [ "${EMAILA[$j]}" != "" ]
    do
	for par in EMAILA[$j] ADDRELAYS[$j] PORT[$j] USERNAM[$j] \#PASSW[$j] ; do
	    wrren $par
	done
	j=$(($j+1))
    done
    # Make sure next value for j is null
    EMAILA[$j]=""
    wrren EMAILA[$j]
    for par in RELAYHOST USERNAME \#PASSWORD LUSERNAME NAME ENAME ; do
	wrren $par
    done
    grep -q -E "^$ENAME:[[:blank:]]" /etc/aliases
    if [ $? -eq 0 ] ; then
	sed -i -e "/^$ENAME:[[:blank:]]/ c $ENAME:\t$LUSERNAME" /etc/aliases
    else
	echo -e "$ENAME:\t$LUSERNAME" >> /etc/aliases
    fi
    grep -q -E "^ca:[[:blank:]]" /etc/aliases
    if [ $? -eq 0 ] ; then
	sed -i -e "/^ca:[[:blank:]]/ c ca:\t\t$LUSERNAME" /etc/aliases
    else
	/usr/bin/echo -e "ca:\t\troot" >> /etc/aliases
    fi
    grep -q -E "^root:[[:blank:]]" /etc/aliases
    if [ $? -eq 0 ] ; then
        sed -i "/^root:[[:blank:]]/ c root:\t$LUSERNAME" /etc/aliases
    else
        /usr/bin/echo -e "root:\t$LUSERNAME" >> /etc/aliases
    fi
    newaliases
    for par in COUNTRYCODE STATEPROVINCE LOCALITYCITY ORGANIZATION ; do
	wrren $par
    done
    [ -z "$PARAMETERS_done" ] && echo PARAMETERS_done=yes >> /etc/genpdsdm/parameters
fi
dlog "== End needed parameters =="
#
# Configuration of the firewall
#
if [ -z "$FIREWALL_config" ] ; then
    message="\
============================\n\
= Configuring firewalld... =\n\
============================"
    interf=$(ip r | grep default)
    interf=${interf#*dev }
    interf=${interf% proto*}
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "\n$message" || $dialog1 --infobox  "$message" 5 0
    [ "$(systemctl is-enabled firewalld.service)" = "disabled" ] && run 'systemctl enable firewalld.service'
    [ "$(systemctl is-active firewalld.service)" = "inactive" ] && run 'systemctl start firewalld.service'
    [ "$(firewall-cmd --list-interface --zone=public)" != "$interf" ] && run "firewall-cmd --zone=public --add-interface=$interf"
    firewall-cmd --list-services --zone=public | grep -q " smtp "
    [ $? -ne 0 ] && run 'firewall-cmd --zone=public --add-service=smtp'
    localdomain=$(ip r | tail -1)
    localdomain=${localdomain%% *}
    [ "$(firewall-cmd --zone=internal --list-sources)" != "$localdomain" ] &&
	run "firewall-cmd --zone=internal --add-source=$localdomain"
    firewall-cmd --list-services --zone=internal | grep " imap "
    [ $? -ne 0 ] && run 'firewall-cmd --zone=internal --add-service=imap'
    firewall-cmd --list-services --zone=internal | grep " imaps "
    [ $? -ne 0 ] && run 'firewall-cmd --zone=internal --add-service=imaps'
    firewall-cmd --list-services --zone=public | grep -q " imaps "
    [ $? -ne 0 ] && run 'firewall-cmd --zone=public --add-service=imaps'
    run 'firewall-cmd --runtime-to-permanent'
    echo FIREWALL_config=yes >> /etc/genpdsdm/parameters
    [ $DIAL -eq 0 ] && sleep 5
fi
#
# Configuration of /etc/postfix/main.cf
#
if [ -z "$MAINCF_done" -o $NEW -eq 0 ] ; then
    message="\
====================================\n\
= Configuring /etc/postfix/main.cf =\n\
= and referenced files...          =\n\
===================================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox "$message" 6 0
    [ -f /var/adm/backup/genpdsdm/main.cf.org ] && cp -a /var/adm/backup/genpdsdm/main.cf.org /etc/postfix/main.cf
    if [ -f /var/adm/backup/genpdsdm/sasl_passwd.org ] ;then
	cp -a /var/adm/backup/genpdsdm/sasl_passwd.org /etc/postfix/sasl_passwd
    else
	[ -f /etc/postfix/sasl_passwd ] && rm /etc/postfix/sasl_passwd
    fi	
    if [ -f /var/adm/backup/genpdsdm/sender_dependent_relayhost.org ] ; then
	cp -a /var/adm/backup/genpdsdm/sender_dependent_relayhost.org /etc/postfix/sender_dependent_relayhost
    else
	[ -f /etc/postfix/sender_dependent_relayhost ] && rm /etc/postfix/sender_dependent_relayhost
    fi
    if [ -f /var/adm/backup/genpdsdm/sender_dependent_default_transport.org ] ; then
	cp -a /var/adm/backup/genpdsdm/sender_dependent_default_transport.org /etc/postfix/sender_dependent_default_transport
    else
	[ -f /etc/postfix/sender_dependent_default_transport ] && rm /etc/postfix/sender_dependent_default_transport
    fi
    if [ -f /var/adm/backup/genpdsdm/tls_per_site.org ] ; then
	cp -a /var/adm/backup/genpdsdm/tls_per_site.org /etc/postfix/tls_per_site
    else
	[ -f /etc/postfix/tls_per_site ] && rm /etc/postfix/tls_per_site
    fi
    echo -e "[$RELAYHOST]:587\t$USERNAME:$PASSWORD" >> /etc/postfix/sasl_passwd
    echo -e "[$RELAYHOST]:587\tMUST" >> /etc/postfix/tls_per_site
    j=0
    while [ "${EMAILA[$j]}" != "" ]
    do
	echo -e "[${ADDRELAYS[$j]}]:${PORT[$j]}\t${USERNAM[$j]}:${PASSW[$j]}" >> /etc/postfix/sasl_passwd
	echo -e "${EMAILA[$j]}\t[${ADDRELAYS[$j]}]:${PORT[$j]}" >> /etc/postfix/sender_dependent_relayhost
	echo -e "[${ADDRELAYS[$j]}]:${PORT[$j]}\tMUST" >> /etc/postfix/tls_per_site
	[ "${PORT[$j]}" = "465" ] && \
	    echo -e "${EMAILA[$j]}\t${ADDRELAYS[$j]#*.}_smtps:[${ADDRELAYS[$j]}]:${PORT[$j]}" >> \
		/etc/postfix/sender_dependent_default_transport
	j=$(($j+1))
    done
    echo "$LUSERNAME	$ENAME" >> /etc/postfix/canonical
    postmap /etc/postfix/sasl_passwd
    postmap /etc/postfix/sender_dependent_relayhost
    [ -f /etc/postfix/sender_dependent_default_transport ] && postmap /etc/postfix/sender_dependent_default_transport
    postmap /etc/postfix/tls_per_site
    postmap /etc/postfix/canonical
    postconf "inet_interfaces = all"
    postconf "proxy_interfaces = $PROXYIP"
    postconf "myhostname = smtp.$DOMAINNAME"
    postconf "mydomain = $DOMAINNAME"
    db_type=$(postconf default_database_type)
    db_type=${db_type##* }
    postconf "alias_maps = ${db_type}:/etc/aliases"
    str="mydestination = \$myhostname, \$mydomain, localhost, localhost.\$mydomain, $HOSTNAME.\$mydomain"
    j=0
    while [ "${LDOMAIN[$j]}" != "" ] ; do
	str=$str", ${LDOMAIN[$j]}"
	j=$(($j+1))
    done
    postconf "$str"
    postconf "myorigin = \$mydomain"
    postconf "mynetworks_style = subnet"
    postconf "canonical_maps = ${db_type}:/etc/postfix/canonical"
    if [ "${EMAILA[0]}" != "" ] ; then
	postconf "sender_dependent_relayhost_maps = ${db_type}:/etc/postfix/sender_dependent_relayhost"
	[ -f /etc/postfix/sender_dependent_default_transport ] && \
	    postconf "sender_dependent_default_transport_maps = ${db_type}:/etc/postfix/sender_dependent_default_transport"
	postconf "smtp_sender_dependent_authentication = yes"
	postconf "smtp_tls_per_site = ${db_type}:/etc/postfix/tls_per_site"
    fi
    postmap /etc/postfix/canonical
    str="smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_invalid_helo_hostname,\
      reject_non_fqdn_sender, reject_unknown_sender_domain, reject_non_fqdn_recipient, reject_unknown_recipient_domain,\
      reject_unauth_destination"
    blhs="$BLACKLISTHOSTS"
    while [ "$blhs" != "" ]
    do
	str="${str}, reject_rbl_client ${blhs%% *}"
	blh="${blhs#* }"
	[ "$blh" = "$blhs" ] && blhs="" || blhs="$blh"
    done
    postconf "$str"
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
    postconf "smtp_tls_CApath = /etc/ssl/certs"
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
    postconf "strict_rfc821_envelopes = yes"
    postconf "disable_vrfy_command = yes"
    grep -q MAINCF_done /etc/genpdsdm/parameters
    [ $? -ne 0 ] && echo "MAINCF_done=yes" >> /etc/genpdsdm/parameters
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
    [ -f /var/adm/backup/genpdsdm/master.cf.org ] && cp -a /var/adm/backup/genpdsdm/master.cf.org /etc/postfix/master.cf
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
/^#tlsmgr    unix/ s/#//
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
    j=0
    while [ "${EMAILA[$j]}" != "" ]
    do
	dlog "postconf ${ADDRELAYS[$j]#*.}_smtps ${PORT[$j]}"
	if [ "${PORT[$j]}" = "465" ] ; then
	    if [ $OS != rasbian ] ;then
		postconf -M ${ADDRELAYS[$j]#*.}_smtps/type="${ADDRELAYS[$j]#*.}_smtps unix - - n - - smtp -o smtp_tls_wrappermode=yes  -o smtp_tls_security_level=encrypt"
	    else
		postconf -M ${ADDRELAYS[$j]#*.}_smtps/type="${ADDRELAYS[$j]#*.}_smtps unix - - y - - smtp -o smtp_tls_wrappermode=yes  -o smtp_tls_security_level=encrypt"
	    fi
	fi
	j=$(($j+1))
    done
    grep -q policyd-spf /etc/passwd
    [ $? -ne 0 ] && useradd -c "SPF Policy Server for Postfix" -d /etc/policyd-spf -s "/sbin/nologin" -r policyd-spf
    grep -q MASTERCF_done /etc/genpdsdm/parameters
    [ $? -ne 0 ] && echo "MASTERCF_done=yes" >> /etc/genpdsdm/parameters
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
    ln -s /etc/ssl/certs $sslpath/cacerts
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
	-e "s/1024/2048/" \
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
    if [ ! -f /etc/dovecot/dh.pem ] ; then
	if [ -f /etc/genpdsdm/dh.pem ] ; then
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
    grep -q POSTFIXCERTIFICATES_done /etc/genpdsdm/parameters
    [ $? -ne 0 ] && echo "POSTFIXCERTIFICATES_done=yes" >> /etc/genpdsdm/parameters
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
    if [ -f /var/adm/backup/genpdsdm/dovecot.conf.org ] ; then
	cp -a /var/adm/backup/genpdsdm/dovecot.conf.org /etc/dovecot/dovecot.conf
	cp -a /var/adm/backup/genpdsdm/10-mail.conf.org /etc/dovecot/conf.d/10-mail.conf
	cp -a /var/adm/backup/genpdsdm/10-master.conf.org /etc/dovecot/conf.d/10-master.conf
	cp -a /var/adm/backup/genpdsdm/10-ssl.conf.org /etc/dovecot/conf.d/10-ssl.conf
	#cp -a /var/adm/backup/genpdsdm/dovecot-openssl.cnf.org /usr/share/dovecot/dovecot-openssl.cnf
	#[ -f /etc/ssl/private/dovecot.crt ] && rm /etc/ssl/private/dovecot.crt
	#[ -f /etc/ssl/private/dovecot.pem ] && rm /etc/ssl/private/dovecot.pem
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
    [ $(systemctl is-enabled dovecot.service) = "disabled" ] && systemctl enable dovecot.service 2>/dev/null
    [ $(systemctl is-active dovecot.service) = "inactive" ] && systemctl start dovecot.service
    grep -q -e "^DOVECOT_done" /etc/genpdsdm/parameters
    [ $? -ne 0 ] && echo "DOVECOT_done=yes" >> /etc/genpdsdm/parameters
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
	if [ ${OS:0:3} != "15." ] ; then
	    [ "$(systemctl is-enabled freshclam.timer)" != "enabled" ] && systemctl enable freshclam.timer 2>/dev/null
	    [ "$(systemctl is-active freshclam.timer)" != "active" ] && systemctl start freshclam.timer
	else
	    [ "$(systemctl is-enabled freshclam.service)" != "enabled" ] && systemctl enable freshclam.service 2>/dev/null
	    [ "$(systemctl is-active freshclam.service)" != "active" ] && systemctl start freshclam.service
	fi
	[ "$(systemctl is-enabled clamd.service)" != "enabled" ] && systemctl enable clamd.service 2>/dev/null
	sleep 10 #freshclam needs the first time some time to settle before clamd can be activated
	[ "$(systemctl is-active clamd.service)" != "active" ] && systemctl start clamd.service
    else
	[ "$(systemctl is-enabled clamav-freshclam.service)" != "enabled" ] && systemctl enable clamav-freshclam.service 2>/dev/null
	[ "$(systemctl is-active clamav-freshclam.service)" != "active" ] && systemctl start clamav-freshclam.service
	[ "$(systemctl is-enabled clamav-daemon.service)" != "enabled" ] && systemctl enable clamav-daemon.service 2>/dev/null
	sleep 10 #freshclam needs the first time some time to settle before clamd can be activated
	[ "$(systemctl is-active clamav-daemon.service)" != "active" ] && systemctl start clamav-daemon.service
    fi
    sa-update
    echo "CLAMAV_activated=yes" >> /etc/genpdsdm/parameters
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
	[ -f /var/adm/backup/genpdsdm/amavisd.conf.org ] && cp -a /var/adm/backup/genpdsdm/amavisd.conf.org /etc/amavisd.conf
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
	[ -f /var/adm/backup/genpdsdm/05-node_id.org ] && cp -a /var/adm/backup/genpdsdm/05-node_id.org /etc/amavis/conf.d/05-node_id
	cat <<EOF > /tmp/sedscript.txt
/^chomp/ s/^/#/
/^#\$myhostname/ c\
\$myhostname = \"smtp.$DOMAINNAME\" ;
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/05-node_id
	[ -f /var/adm/backup/genpdsdm/05-domain_id.org ] && cp -a /var/adm/backup/genpdsdm/05-domain_id.org /etc/amavis/conf.d/05-domain_id
	cat <<EOF > /tmp/sedscript.txt
/^chomp/ c\
\$mydomain = \"$DOMAINNAME\" ;
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/05-domain_id
	[ -f /var/adm/backup/genpdsdm/15-content_filter_mode.org ] && \
	    cp -a /var/adm/backup/genpdsdm/15-content_filter_mode.org /etc/amavis/conf.d/15-content_filter_mode
	cat <<EOF > /tmp/sedscript.txt
/^#@bypass_v/,/^#   \\\%bypass_v/ s/^#//
/^#@bypass_s/,/^#   \\\%bypass_s/ s/^#//
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/15-content_filter_mode
	[ -f /var/adm/backup/genpdsdm/20-debian_defaults.org ] && \
	    cp -a /var/adm/backup/genpdsdm/20-debian_defaults.org /etc/amavis/conf.d/20-debian_defaults
	cat <<EOF > /tmp/sedscript.txt
/^\$enable_dkim_verification/ {
s/0/1/
s/disabled to prevent warning/enabled to verify dkim/
}
EOF
	sed -i -f /tmp/sedscript.txt /etc/amavis/conf.d/20-debian_defaults
	[ -f /var/adm/backup/genpdsdm/50-user.org ] && cp /var/adm/backup/genpdsdm/50-user.org /etc/amavis/conf.d/50-user
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
    grep -q -E "^virusalert:[[:blank:]]" /etc/aliases
    if [ $? -eq 0 ] ; then
	sed -i -e "/^virusalert:[[:blank:]]/ c virusalert:\tpostmaster" /etc/aliases
    else
	/usr/bin/echo -e "virusalert:\tpostmaster" >> /etc/aliases && newaliases
    fi
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
    fi
    message="The DKIM public key to be entered in the DNS is present in the file:\n\
/var/db/dkim/${DOMAINNAME}.dkim${date}.txtrecord\n"
  [ $DIAL -ne 0 ] && /usr/bin/echo -e "\n$message" || $dialog1 --msgbox "$message" 6 80
    [ $(systemctl is-enabled amavis.service) = "disabled" ] && systemctl enable amavis.service 2>/dev/null
    [ $(systemctl is-active amavis.service) = "inactive" ] && systemctl start amavis.service
    grep -q AMAVIS_done /etc/genpdsdm/parameters
    [ $? -ne 0 ] && echo "AMAVIS_done=yes" >> /etc/genpdsdm/parameters
    [ $DIAL -eq 0 ] && sleep 5
fi
[ -f /tmp/sedscript.txt ] && rm /tmp/sedscript.txt
#
# Configuration of DMARC
#
if [ -z "$DMARC_done" -o $NEW -eq 0 -o $OLD -eq 0 ] ; then
    message="\
=========================\n\
= Configuring DMARC...  =\n\
========================="
    [ $DIAL -ne 0 ] && /usr/bin/echo -e "$message" || $dialog1 --infobox  "$message" 5 0
    if [ -f /var/adm/backup/genpdsdm/opendmarc.conf.org ] ; then
	cp -a /var/adm/backup/genpdsdm/opendmarc.conf.org /etc/opendmarc.conf
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
    grep -q -E "^dmarc-failures:[[:blank:]]" /etc/aliases
    if [ $? -eq 0 ] ; then
	sed -i -e "/^dmarc-failures:[[:blank:]]/ c dmarc-failures:\tpostmaster" /etc/aliases
    else
	/usr/bin/echo -e "dmarc-failures:\tpostmaster" >> /etc/aliases
    fi
    grep -q -E "^dmarc-reports-send:[[:blank:]]" /etc/aliases
    if [ $? -eq 0 ] ; then
	sed -i -e "/^dmarc-reports-send:[[:blank:]]/ c dmarc-reports-send:\tpostmaster" /etc/aliases
    else
	/usr/bin/echo -e "dmarc-reports-send:\tpostmaster" >> /etc/aliases
    fi
    newaliases
    [ -f /var/adm/backup/genpdsdm/opendmarc-ignore.hosts.org ] && \
	cp -a /var/adm/backup/genpdsdm/opendmarc-ignore.hosts.org /etc/opendmarc/ignore.hosts
    [ "$(systemctl is-enabled opendmarc.service)" = "disabled" ] && systemctl enable opendmarc.service 2>/dev/null
    [ "$(systemctl is-active opendmarc.service)" != "active" ] && systemctl start opendmarc.service
    grep -q DMARC_done /etc/genpdsdm/parameters
    [ $? -ne 0 ] && echo "DMARC_done=yes" >> /etc/genpdsdm/parameters
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
