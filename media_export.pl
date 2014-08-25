#!/usr/bin/perl
#
###### 
# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
# addtional libraries
use Getopt::Std;
use File::Basename;
#
######
#
use vars qw($EJECT $JB $LOCATION $MAILER $MMQ $NSRSERVER %options @POOLS $TIME $volume $volretent $used $MAILSERV);

# NetWorker  Server
$NSRSERVER="bocntbk12.boc.chevrontexaco.qnet";
# what is the name of our physical jukebox
$JB="bocntbk12_IBM";
#
# place pools here to be ejected daily
@POOLS=("PlatClone","GoldClone");
#
# The location to set our offsite tapes to
$LOCATION="offsite";
#
# how far back to catch offsite tapes.  this should cover a long weekend.
$TIME="last week";
#
# Mail Server
$MAILSERV="mailhost-hou150.chevrontexaco.net";
#
# configure the mail server
$MAILER="smtpmail \-s \"$JB export report to $LOCATION\" \-h $MAILSERV \-f gnmi\@chevron.com gnmi\@chevron.com";
# the query string for our mminfo query
$MMQ="!incomplete, !volrecycle, \%used > 100, savetime < $TIME, location=$JB";

# print "$mailer\n";
#####
# set up our options
#
# -c: config file
# -e: eject tapes
#
#
getopts('ec:',\%options);

####
# make command line switches do something
if ($options{e}) { $EJECT=1;} else { $EJECT=0;}
# 
##### read in config files
if ($options{c}) {
	if ( -e "$options{c}") { 
		print "reading $options{c}\n";
		no strict 'refs';
		open ( CONF, "$options{c}") || die "cannot open config: $!\n";
		my $conf = join "", <CONF>; 
		close CONF;
		eval $conf;
		die "Couldn't eval config file: $@\n" if $@;
		print "config file $conf loaded\n";
	} else {print "Config file not found, using defaults\n";}
}
#####
open (MAIL, "|$MAILER") || die ( "$MAILER failed: $!\n");
#

print MAIL "\n\n#######################################################";
print MAIL "#######################################################";
print MAIL "### Networker Pull list for the $JB jukebox ###\n";

# set up our formats here.
# Should print up real nice

format MAIL =
@<<<<<<<<<<<<<<<< @|||||||||||| @>>>>>>>>>>>>>>>>>
$volume,          $volretent,   $used
.

# Stip the format with a single "." on a line by itself
# 
foreach my $pool (@POOLS) { # iterate through out list of pools
	#
	# open mminfo and query 
	open (MMVOL, "mminfo -s $NSRSERVER -xc, -r volume,volretent,\%used -q \"pool=$pool\" -q \"$MMQ\"|") 
		or die ("unable to open mminfo: $!");
	#
	#temp array hack to load the @mmvol array
	my @mmvol=<MMVOL>;
	print @mmvol;
	#
	print MAIL "\n\nNetWorker Media Pool: $pool\n";
	foreach my $cline (@mmvol) {
		chomp($cline);
		print "$cline\n";
		($volume, $volretent, $used) = split (',', $cline);	
		#
		write MAIL;
		if ($EJECT) {
			# Set the location field in the volume db
			system ("mmlocate -s $NSRSERVER -u -n $volume $LOCATION");
			#
			# eject tapes from jukebox
			system ("nsrjb -s $NSRSERVER -j $JB -w $volume"); 
			#
			print "\n Ejecting $volume from $JB";
			# give everything a few seconds before processing the next eject
			sleep 2; 
		}
	}
}
close (MAIL);
