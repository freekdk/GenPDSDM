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

