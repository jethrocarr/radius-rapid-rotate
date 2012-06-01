#!/usr/bin/perl -w
#
# Radius Rapid Rotate (R3)
# Logrotation script for FreeRadius accounting logs.
#
# Copyright (C) 2012 Prophecy Networks Ltd
#
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
#
# Execute with -h for help on available options. All key configuration can
# be adjusted in-file or on runtime via CLI options.
#
#

use strict;
use Getopt::Std;
use Sys::Hostname;
use POSIX qw(strftime);
use Fcntl qw/:DEFAULT :flock/;


## Configuration ##

my $log_path_radius 	= "/var/log/radius/radacct/";
my $log_path_dest	= "/var/log/radius/archive/";
my $lock		= "/var/lock/rapidradiusrotate.lock";

my @rotatefiles		= ("detail", "auth-detail", "reply-detail", "pre-proxy-detail", "post-proxy-detail");

my $debug		= 0;

my $date		= strftime "%Y%m%e", localtime;
my $time		= strftime "%H%M", localtime;

my $hostname		= hostname;
$hostname		=~ s/\.(\S*)$//g;



## Runtime Options ##


my $options = {};
my $program = ($0 =~ /([^\/]+)$/)[0];

if (!getopts('vs:d:', $options))
{
    die "usage: $program [-v] [-s source] [-d destination] [-h hostname]\n";
}

$debug = defined $options->{'v'};

if ($options->{'s'})
{
	$log_path_radius = $options->{'s'};
}

if ($options->{'d'})
{
	$log_path_dest = $options->{'d'};
}

if (!-d $log_path_radius)
{
	die "Fatal: Unexpected failure: \"$log_path_radius\"no such FreeRadius source directory or no permissions granted.\n";
}

if (!-d $log_path_dest)
{
	die "Fatal: Unexpected failure: \"$log_path_dest\"no such destination directory or no permissions granted.\n";
}



## Application ##

print "Executing $program for host $hostname in debug mode at $date $time.\n" if $debug;


# verify there is no other copy of this process running
sysopen(LOCK, $lock, O_RDWR|O_CREAT, 0666);

if (!flock(LOCK, LOCK_EX | LOCK_NB))
{
	die("Fatal: Unable to obtain lock on \"$lock\", is there another process running?\n");
}


#
# The process here is simple - we need to browse the directory structure and for each IP and each log file, we need to
# move the current log file and rename it.
#
# Target naming format is radacct-{SERVER_HOSTNAME}-{IPADDRESS}-{TYPE}-{YYYYMMDD}-{HHMM}.log
#
# Before: /var/log/radius/radacct/192.168.0.1/detail
# After: /newpath/radacct-ServerHostname-192.168.0.1-detail-20120530-1601.log
#

my @nas_addresses = glob("$log_path_radius/*");

foreach my $address (@nas_addresses)
{
	$address =~ /^\S*\/(\S*)$/;
	my $address_short = $1;

	print "Processing for NAS address: $address ($address_short)\n" if $debug;


	# We look for the log files - FreeRadius needs to be configured to use names
	# without date information.

	foreach my $file (@rotatefiles)
	{
		if (-f "$address/$file")
		{
			my $log_old = "$address/$file";
			my $log_new = "$log_path_dest/radacct-$hostname-$address_short-$file-$date-$time.log";
			
			print "Rotating $log_old to $log_new\n" if $debug;

			if (!rename($log_old, $log_new))
			{
				die("Fatal: Unable to rotate log file \"$log_old\" to \"$log_new\"!\n");
			}
		}
		else
		{
			print "Skipping type $file due to no file \"$address/$file existing\" \n" if $debug;
		}
	}

}

print "Log rotation process complete!\n" if $debug;


