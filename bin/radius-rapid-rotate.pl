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
use File::Copy;
use POSIX qw(strftime);
use Fcntl qw/:DEFAULT :flock/;


## Configuration ##

my $log_path_radius 	= "/var/log/radius/radacct/";
my $log_path_tmp	= "/var/log/radius/R3tmp/";		# needs to be on the same filesystem as $log_path_radius
my $log_path_dest	= "/var/log/radius/archive/";
my $log_path_dest_mount	= 0;					# 0 == don't check, 1 == check if a filesystem is mounted here.

my $lock		= "/var/lock/rapidradiusrotate.lock";

my @rotatefiles		= ("detail", "auth-detail", "reply-detail", "pre-proxy-detail", "post-proxy-detail");

my $debug		= 0;

my $date		= strftime "%Y%m%d", localtime;
my $time		= strftime "%H%M", localtime;

my $hostname		= hostname;
$hostname		=~ s/\.(\S*)$//g;



## Runtime Options ##


my $options = {};
my $program = ($0 =~ /([^\/]+)$/)[0];

if (!getopts('vcs:d:t:', $options))
{
    die "usage: $program [-v] [-c] [-s source] [-d destination] [-t tmpspace] [-h hostname]\n";
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

if (defined $options->{'c'})
{
	$log_path_dest_mount = 1;
}

if ($options->{'t'})
{
	$log_path_tmp = $options->{'t'};
}


if (!-d $log_path_radius)
{
	die "Fatal: Unexpected failure: \"$log_path_radius\"no such FreeRadius source directory or no permissions granted.\n";
}

if (!-d $log_path_dest)
{
	die "Fatal: Unexpected failure: \"$log_path_dest\"no such destination directory or no permissions granted.\n";
}

if (! -d $log_path_tmp)
{
	die "Fatal: Unexpected failure: \"$log_path_tmp\"no such destination directory or no permissions granted.\n";
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
# move the current log file and rename it into the tmp directory.
#
# Target naming format is radacct-{SERVER_HOSTNAME}-{IPADDRESS}-{TYPE}-{YYYYMMDD}-{HHMM}.log
#
# Before: /var/log/radius/radacct/192.168.0.1/detail
# After: /newpath/20120530-1601-radacct-ServerHostname-192.168.0.1-detail.log
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
			my $log_new = "$log_path_tmp/$date-$time-radacct-$hostname-$address_short-$file.log";
			
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


#
# All the logs are now in the temporary space, now we need to copy them
# one-by-one to the final destination.
#
# We use this split tmp/dest directory method, since it protects us from losing
# data if the archive directory is a remote archive and is unavailable - logs
# will simply pool in the temp directory until they can be moved.
#

print "Moving tmp files to final destination....\n" if $debug;

if ($log_path_dest_mount)
{
	# we need to validate if the remote archive location is a currently valid
	# mountpoint. We chomp the path to remove trailing /

	my $mountpath	= chomp($log_path_dest);
	my $mount 	= `mount | grep $mountpath`;
	chomp($mount);
	
	if (!$mount)
	{
		print "Unable to find an active mount for $log_path_dest\n";
		print "Logs rotated but stuck in $log_path_tmp until issue is resolved.\n";
		die("Fatal: Archive destination error");
	}


	# make sure the archive destination is writable - a read-only mounted share isn't
	# much good to us. ;-)

	if (!-w $log_path_dest)
	{
		print "Warning: Unable to write to the mount point $log_path_dest\n";
		print "Logs rotated but stuck in $log_path_tmp until issue is resolved.\n";
		die("Fatal: Archive destination error");
	}
}


my @tmp_files = glob("$log_path_tmp/*");

foreach my $file (@tmp_files)
{
	$file =~ /^\S*\/(\S*)$/;
	my $file_short = $1;

	print "Archiving file $file_short...\n" if $debug;

	if (!copy($file, "$log_path_dest/$file_short"))
	{
		die("Fatal: Unable to archive log file \"$file_short\" to \"$log_path_dest\"!\n");
	}
	else
	{
		print "Deleting archived file $file_short from tmp space\n" if $debug;

		unlink($file);
	}
}


print "Log rotation process complete!\n" if $debug;


