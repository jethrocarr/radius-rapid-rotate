#!/usr/bin/perl -w
#
# easypackage.pl
#
# Copyright (C) 2012 Jethro Carr
# Copyright (C) 2012 Prophecy Networks Ltd
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
#
# This utility makes it easy to build packages from your unpacked source tree.
#
# It make a copy of the source, remove any CVS/SVN folders, rename it to the
# desired version, rename .spec file to the desired version, then finally
# it will tar & bzip it.
#
# Then you can choose to copy the required files to /usr/src/redhat/ in
# order to build an RPM.
#
#
#

use strict;

## SETTINGS ##
my $input;


## PROGRAM ##


if ($0 ne "./easypackage.pl")
{
	die("Error: Please run this script from within it's directory. (./easypackage)\n");
}

# change down to the root of the source tree.
chdir("../") || die("Error: Package is not in expected form.\n");


# get version
print "Please enter version (eg: 20080419_beta0):\n";
my $version = get_question('^\S*$');

# determine final name
my $name_base		= "radius-rapid-rotate";
my $name_withversion	= "radius-rapid-rotate-$version";


# make sure destination data does not exist.
if (-e "/tmp/$name_withversion" || -e "/tmp/$name_withversion.tar.bz2")
{
	print "Warning: The dir or tarball /tmp/$name_withversion already exists. Do you wish to replace it? (y/n)\n";
	$input = get_question('^[y|n]$');

	if ($input eq "n")
	{
		print "No changes have been made\n";
		exit 0;
	}
	
	system("rm -rf /tmp/$name_base*");
}

# create new dir
system("mkdir /tmp/$name_withversion");
system("cp -avr * /tmp/$name_withversion/");

# we have finished with the orignal source
chdir("/tmp");

# remove CVS  & SVN stuff
system("find $name_withversion/* -type d | grep CVS | sed \"s/^/rm -rf /\" | sh");
system("find $name_withversion/* -type d | grep .svn | sed \"s/^/rm -rf /\" | sh");

# remove a config file if one exists
system("rm -f $name_withversion/htdocs/include/config-settings.php");
system("rm -f $name_withversion/testsuite/include/config-settings.php");

# insert version into spec file and write changed version to /tmp/ location
open(IN, "$name_withversion/resources/$name_base.spec") || die("Unable to open spec file");
open(OUT, ">/tmp/$name_base.spec") || die("Unable to open /tmp/$name_base.spec");

while (my $line = <IN>)
{
	if ($line =~ /^Version:/)
	{
		$line = "Version: $version\n";
	}
	
	print OUT $line;
}
close(IN);
close(OUT);


# create tarball.
system("tar -cjvf $name_withversion.tar.bz2 $name_withversion");

# remove source dir
system("rm -rf $name_withversion/");



# transfer RPM components to correct location?
print "Would you like to place source + spec into /usr/src/redhat?\n";
$input = get_question('^[y|n]$');

if ($input eq "y")
{
	system("cp $name_withversion.tar.bz2 /usr/src/redhat/SOURCES/");
	system("cp $name_base.spec /usr/src/redhat/SPECS/");

	print "Execute rpmbuild -ba /usr/src/redhat/SPECS/$name_base.spec to build RPM.\n";
}



print "Complete!\n";
print "\n";
print "Tarball:\t/tmp/$name_withversion.tar.bz2\n";
print "Spec:\t/tmp/$name_base.spec\n";
exit 0;


### FUNCTIONS ###

# get_question
#
# Gets user input from CLI and does verification
#
sub get_question {
        my $regex = shift;
        my $complete = 0;


        while (!$complete)
        {
                my $input = <STDIN>;
                chomp($input);

                if ($input =~ /$regex/)
                {
                        return $input;
                }
                else
                {
                        print "Invalid input! Please re-enter.\n";
			print "Retry: ";
                }
        }

}


