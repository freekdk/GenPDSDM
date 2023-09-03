# GENPDSDM
=================

Generate system with Postfix, Dovecot, SPF, DKIM and DMARC
## Description
GENPDSDM is a bash script to generate in a headless system an email system (postfix) to receive (stored in IMAP server dovecot) and send messages with all available security features. This system serves it own domain. The supported secutity features are SPF, DKIM, and DMARC supported by AmaVis, which includes ClamAV and Spamassassin. It is primairely designed for openSUSE Leap 15.5 on a Raspberry Pi 4B. However it might be usable on Tumbleweed and other architectures as well.
## Documentation
The documentation, which describes what will be done by this script is in the [openSUSE wiki](https://en.opensuse.org/Mail_server_HOWTO) and in the files genpdsdm.pdf, which is generated with genpdsdm.odt.
## License
This software and documentation can be distributed and used under the GNU GENERAL PUBLIC LICENSE (GPL) version 2 or later.
## Contributing
Issues should be submitted via github and be well documented and patches thorouhgly tested.

## Parallel development
There is ongoing work on enhancing the generation of postfix with these security features in two packages in openSUSE, postfix and yast2-mail.
Two files in the packet postfix are under development, /usr/sbin/config.postfix and /etc/sysconfig/postfix. The last one, a file with parameter definitions, is the one that gets configured in yast2-mail. The script config.postfix uses these parameters to configure postfix. The script yast2-mail.sh is meant to indicate what needs to be implemented in the yast2-mail module, but for now it can be used to do the configuration this module should do.
Apart from assigning values to the parameters in /etc/sysconfig/postfix by yast2-mail it also prepares the postfix system by giving the system a host name and a domain name and, if requested, the data needed for a relayhost. Authenticated access can be chosen to use dovecot, otherwise cyrus will be used. The needed packages will be installed and configured. Email with cyrus will be delivered in /var/spool/mail/\<user>, with dovecot mail goes in ~/Maildir/ in the home folder of the user. When AmaVis, SPF and/or DMARC checking and/or DKIM checking and signing is requested, these packages are installed and configured. Also the firewall will be configured to allow access to the necessary ports.
The script also generates certificates to provide secured access to the email server and, if dovecot is chosen, the imap server.
### Warnings
When using dovecot a file /etc/dovecot/dh.pem is needed and will be generated if it is not present. This may take more than an hour to generate; the script will finish but the generation will continue.
When defining the domain name, the script will perform some checks on the presence of needed records in the DNS, both your own and the name of a relayhost.
### Things the script can't do
There is no known general API to enter values in a DNS, so this is something you need to do yourself. Obviously you need to have A and, if you use IPv6, AAAA records, for access to your email server (port 25 and possibly 587), with names {mail,smtp}.\<your_domain> and with dovecot (port 993), with imap.\<your_domain>. You also need to enter the generated DKIM public key as a TXT record and TXT records for SPF and DMARC (How will be covered in a to be written document).