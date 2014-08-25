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
use vars qw($MAILER $NSRSERVER %options $COMPRESS %VTLS $TIME $volume $volretent $used $MAILSERV $vtl $size $szdisk $remaindisk);

# NetWorker  Server
$NSRSERVER="bocntbk12.boc.chevrontexaco.qnet";
# what is the name of our virtual jukebox and their capacities in GB
%VTLS=(
	bocntbk12_IBM=>'1500', 
	bocntbk12_VTL1a=>'4000'
);
#
# Mail Server
$MAILSERV="mailhost-hou150.chevrontexaco.net";

# "compression" in percent
$COMPRESS=.6;
#
# configure the mail server
$MAILER="smtpmail \-s \"VTL Space report for $NSRSERVER \" \-h $MAILSERV \-f gnmi\@chevron.com gnmi\@chevron.com";

# print "$mailer\n";
#####
# set up our options
#
# -c: config file
# -e: eject tapes
#
#
getopts('c:',\%options);

####
# make command line switches do something
#if ($options{e}) { $EJECT=1;} else { $EJECT=0;}
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
	} else {die "Config file not found please specify with -c file\n";}
}
#####
open (MAIL, "|$MAILER") || die ( "$MAILER failed: $!\n");
#

print MAIL "\n\n";

# set up our formats here.
# Should print up real nice
format MAIL_TOP =
VTL Name          Size Written     Size on Disk    Size Remaining
                      (GB)              (GB)           (GB)
-------------------------------------------------------------------
.
format MAIL =
@<<<<<<<<<<<<<<<<<  @########.##  @########.##   @########.##
$vtl,        	      $size,           $szdisk,    $remaindisk
.
# End the format with a single "." on a line by itself
# 
foreach $vtl (keys(%VTLS)) { # iterate through our list of VTLs
	#
	# open mminfo and query 
	open (MMVOL, "mminfo -s $NSRSERVER -xc, -r \"written\" -q \"location=$vtl\"|") 
		or die ("unable to open mminfo: $!");
	#
	#temp array hack to load the @mmvol array
	my @mmvol=<MMVOL>;
	#
	$size=0;
	my @volsum;
	foreach my $volsz (@mmvol) {
		chomp($volsz);
		$volsz =~ s/\ B// ;
		$volsz =~ s/\ KB/000/ ;
		$volsz =~ s/\ MB/000000/ ;
		$volsz =~ s/\ GB/000000000/ ;
		$volsz =~ s/\ TB/000000000000/ ;
		#print "$volsz\n";
		push (@volsum, $volsz);
		}
	for (my $i=0;$i < @volsum; $i++){
		$size=$size+$volsum[$i];
	}
	$szdisk=$size*$COMPRESS;
	$size=$size/1000000000;
	$szdisk=$szdisk/1000000000;
	$remaindisk=$VTLS{$vtl}-$szdisk;
	write MAIL;
}
close (MAIL);
