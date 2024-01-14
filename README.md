# GENPDSDM
=====================

**Gen**erate system with **P**ostfix, **D**ovecot, **S**PF, **D**KIM and D**M**ARC
## Description
GENPDSDM is a bash script to generate in a headless system an email system (postfix) to receive (stored in IMAP server dovecot) and send messages with all available security features. This system serves it own domain. The supported secutity features are SPF, DKIM, and DMARC supported by AmaVis, which includes ClamAV and Spamassassin. It is primairely designed for openSUSE Leap 15.5 on a Raspberry Pi 4B. However it is usable on Tumbleweed and other architectures as well.

## Documentation
The documentation, which describes what will be done by this script is in the [openSUSE wiki](https://en.opensuse.org/Mail_server_HOWTO) and in the files `genpdsdm.pdf`, which is generated from `genpdsdm.odt`. Documentation for the parallel development for the openSUSE packets **postfix** and **yast2-mail** is in `genmailmodule.pdf`, generated from `genmailmodule.odt`.

## License
This software and documentation can be distributed and used under the GNU GENERAL PUBLIC LICENSE (GPL) version 2 or later.

## Contributing
Issues should be submitted via github and be well documented and patches thorouhgly tested.

## Parallel development
There is ongoing work on enhancing the generation of postfix with these security features in two packages in openSUSE, postfix and yast2-mail.
Three files in the packet postfix and amavisd-new are under development, `/sbin/config.postfix`, `/etc/sysconfig/postfix` and `/etc/sysconfig/mail`. These last two, are files with parameter definitions, which gets configured in the script `yast2-mail.sh`. The script config.postfix uses these parameters to configure postfix and dovecot, if choose so. The script `yast2-mail.sh` is meant to indicate what needs to be implemented in the yast2-mail module, but for now it can be used to do the configuration this module should do.
Apart from assigning values to the parameters in `/etc/sysconfig/postfix` and `/etc/sysconfig/mail` by yast2-mail it also prepares the postfix system by giving the system a host name and a domain name and, if requested, the data needed for a relayhost. Authenticated access can be chosen to use dovecot, otherwise cyrus will be used. The needed packages will be installed and configured. Email with cyrus will be delivered in /var/spool/mail/\<user>, with dovecot mail goes in ~/Maildir/ in the home folder of the user. When AmaVis, SPF and/or DMARC checking and/or DKIM checking and signing is requested, these packages are installed and configured. Also the firewall will be configured to allow access to the necessary ports.
The script also generates certificates to provide secured access to the email server and, if dovecot is chosen, the imap server.
### Warnings
When using dovecot a file /etc/dovecot/dh.pem is needed and will be generated if it is not present. This may take more than an hour to generate; the script will finish but the generation will continue. After generating you can save this file and, when later needed before a new generation of the system, store it in that location and the generation will be skipped.

Also the generated private key for DKIM signing and the public key, which needs to be put in the DNS as a TXT record, are better safely stored. They are located in the folder `/var/db/dkim/`. When present in that location a new pair will not be generated. The first part of the filenames is the domain name.

When defining the domain name, the script will perform some checks on the presence of needed records in the DNS, both your own and the name of a relayhost.
### Things the script can't do
There is no known general API to enter values in a DNS, so this is something you need to do yourself. Obviously you need to have A and, if you use IPv6, AAAA records, for access to your email server (port 25 and possibly 587), with names {mail,smtp}.\<your_domain> and with dovecot (port 993), with imap.\<your_domain>. You also need to enter the generated DKIM public key as a TXT record and TXT records for SPF and DMARC (How will be covered in the partly written document, `genmailmodule.pdf` generated from `genmailmodule.odt`).