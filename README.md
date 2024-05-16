# GENPDSDM
=====================

**Gen**erate system with **P**ostfix, **D**ovecot, **S**PF, **D**KIM and D**M**ARC
## Description
GENPDSDM is a bash script to generate in a headless system a email system (postfix) to receive (stored in IMAP server dovecot) and send messages with a number of available security features. This system serves it own domain. The supported secutity features are SPF, DKIM, and DMARC supported by AmaVis, which includes ClamAV and Spamassassin. It is primairely designed for openSUSE Leap 15.5 on a Raspberry Pi 4B. However it is usable on Tumbleweed and other architectures as well. Tested on Raspberry Pi OS (bookworm) and in a Virtual Host on Debian (bookworm).

## Documentation
The documentation, which describes what will be done by this script is in the [openSUSE wiki](https://en.opensuse.org/Mail_server_HOWTO) and in the files `genpdsdmrpi.pdf`, which is generated from `genpdsdmrpi.odt`.

## License
This software and documentation can be distributed and used under the GNU GENERAL PUBLIC LICENSE (GPL) version 2 or later.

## Contributing
Issues should be submitted via github and be well documented and patches thorouhgly tested.

### Warnings
When using dovecot a file /etc/dovecot/dh.pem is needed and will be generated if it is not present. This may take more than an hour to generate; the script will finish but the generation will continue. After generating you can save this file and, when later needed before a new generation of the system, store it in that location and the generation will be skipped.

Also the generated private key for DKIM signing and the public key, which needs to be put in the DNS as a TXT record, are better safely stored. They are located in the folder `/var/db/dkim/`. When present in that location a new pair will not be generated. The first part of the filenames is the domain name.

When defining the domain name, the script will perform some checks on the presence of needed records in the DNS, both your own and the name of a relayhost.
### Things the script can't do
There is no known general API to enter values in a DNS, so this is something you need to do yourself. Obviously you need to have A and, if you use IPv6, AAAA records, for access to your email server (port 25 and possibly 587), with names {mail,smtp}.\<your_domain> and with dovecot (port 993), with imap.\<your_domain>. You also need to enter the generated DKIM public key as a TXT record and TXT records for SPF and DMARC (How will be covered in the partly written document, `genmailmodule.pdf` generated from `genmailmodule.odt`).
### Bugs
There is no support for IPv6.