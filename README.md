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