#!/usr/bin/perl
#
# prune.pl - remove already cloned savesets
#

###### 
# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
# addtional libraries
use Getopt::Std;
use File::Path;
#
use vars qw($NSRSERVER $DEBUG $NSRMMINFO $LOGFILE $LOGLOC 
$NSRBIN $CONFIG %options $RETENTION @VJUKEBOX $TEST @LOCATIONS);
#
# Variables 
#
#
# how long to retain data on the target media
$RETENTION=4;
# 
# The locations of the data to be removed
@LOCATIONS=qw( bocntbk12_VTL1a );
#

####  Code starts here.  No user set vars below this line
#
#
#####
# set up our options
#
# -D: debug
# -c: config file
# -t: test only, works very nice with -D
#
#
getopts('Dtc:',\%options);

####
# make command line switches do something
#
# just makes code easier to read, really.
if ($options{D}) { $DEBUG=1;} else { $DEBUG=0;}
if ($options{t}) { $TEST=1;} else { $TEST=0;}
###

##### read in config files
if ($options{c}) {
	if ( -e "$options{c}") { 
		print "reading $options{c}\n";
		no strict 'refs';
		open ( CONF, "$options{c}") || die "cannot open config: $!\n";
		my $conf = join "", <CONF>; 
		close CONF;
		eval $conf;
		dielog("Couldn't eval config file: $@") if $@;
		print "config file loaded\n";
	} else {print "Config file not found, using defaults\n";}
}
#####


#####
# canned functions
#
# logme function
# usage:
# &logme(message => "subroutine: $status", level => "DEBUG");
sub logme {
	# set up the data structure to hold the data to log
	my %args = (
		'message'        => '',
		# default level is INFO
		'level'          => 'INFO',
                @_,
	);
	# use GMT (ZULU) time to log. localtime() may be substituted for gmtime() as desired.
	my $date=gmtime();
	# preset printing to stdout off
	my $use_stdout=0;
	# if we can't open a logfile to append send output to stdout
	$use_stdout=1 unless(open(LOGFILE, ">>$LOGFILE"));
	# turn off buffering on the filehandle
	{ my $logfh = select LOGFILE;
		$| = 1;
		select $logfh;
	}

	chomp($date);
	# write to stdout
	if ( $use_stdout ) {
		printf("%s: %s - %s\n",$date,$args{level},$args{message});
	# write to our logfile
	}else {
		printf(LOGFILE "%s: %s - %s\n",$date,$args{level},$args{message});
		close(LOGFILE);
	}
} #end logme subroutine

# a quick function to log and die a process on error
sub dielog {
	my ($error) = @_;
	
	logme(message => "$error", 
		level => 'ERROR');
	logme(message => "queue_runner ended");
	print "$error\n";
	exit();
} # end dielog()
#


#####
# standard operations
#
# log if there is a logfile
if ($LOGFILE) {
	print "using $LOGFILE as the logfile\n";
	#
	# put a visual indicator in the log to show the start of the run
	logme ( message => "################################################",
		level=> "START");
	logme ( message => "$0 starting. PID: $$");
}
else {
	print "logging to console\n";
}

##### read in config files
if ($options{c}) {
	if ( -e "$options{c}") { 
		print "reading $options{c}\n";
		no strict 'refs';
		open ( CONF, "$options{c}") || die "cannot open config: $!\n";
		my $conf = join "", <CONF>; 
		close CONF;
		eval $conf;
		dielog("Couldn't eval config file: $@") if $@;
		print "config file loaded\n";
	} else {print "Config file not found, using defaults\n";}
}
#####
if ($DEBUG) {
use Data::Dumper;
# log if we have debug on
logme ( message => "Debug on... level:$DEBUG");
}
logme (message=> "Test only.. no SSID's will be removed") if ($TEST);

########################################
# Main line of program
#

# sort through  all the Virtual Tape Libraries configured in
# @VJUKEBOX and find all the cloned savesets and return the ssid/cloneid
# of the saveset copy on each vtl listed in @VJUKEBOXES and delete from 
# the media database.  Run nsrim -X to croscheck all media and ss.  This will 
# insure that any virtual volumes with all savesets remive  are recyclable.
#
foreach my $vtl (@VJUKEBOX) {
	# do an mmifo query to select all the cloned media in a given VTL
	open (PRUNE, "mminfo -q\"location=$vtl,savetime<$RETENTION,copies>1\" -r \"ssid,cloneid\" -xc\/|") 
		or logdie ("unable to open mminfo : $!");
	my @pruneme=<PRUNE>;

	# loop through and delete the VTL copy of each selected saveset
	foreach my $pruneid (@pruneme) {
		chomp($pruneid);
		logme(message=>"Removing SSID/CLONEID: $pruneid",
			level=>"DEBUG") if $DEBUG;
		# delete the ssid/cloneid on the target 
		system("nsrmm -y -d -S $pruneid") unless ($TEST);
	}
	#
	# clear out the deleted SSIDs
	system("nsrim -X");
} # end foreach vtl prune loop
# end
