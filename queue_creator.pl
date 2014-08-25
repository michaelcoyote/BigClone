#!/usr/bin/perl
# 
# queue_creator.pl
# Job Queue processor
# 
#
# The object of this script is to take a backup pool (or multiple 
# backup pools) and create a queue for the savesets to 
# clone a single clone pool.
#

###### 
# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
# addtional libraries
use Getopt::Std;
use File::Path;

use vars qw($NSRSERVER $CLONETMP $DEBUG $NSRMMINFO $TEST 
$LOGFILE $LOGLOC $NSRBIN $CONFIG %options $PRIORITY
$i $LOGFILE $mmquerystring $QUEUEDIR @POOLS $DESTPOOL
 $QUEUES $DAYS @ssidout %worklist $volume $SKIPCHECK);

####  Code starts here.  No user set vars below this line
#
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
getopts('Dthc:',\%options);


if ($options{h}) {
	print <<EOF;

$0: Cloning Queue Creator Program

Syntax: $0 [-D | -t | -h | -c <Config File>]

	-h : Help
	-D : Run the Program in Debug Mode
	-t : Run the Program in Test mode
	-c : Configuration file must be passed in.
EOF
	exit;
}

if ($options{D}){
#Eanble Debug Mode
	$DEBUG=1;
} else {$DEBUG=0;}
if($options{t}) {
# Enable Test mode
	$TEST=1;
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
		die "Couldn't eval config file: $@\n" if $@;
		print "config file loaded\n";
	} else {die "Config file not found please specify with -c file\n";}
} else {die "must have a config file";}
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
	die "$error\n";
 
} # end dielog()
########

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


###
if ($DEBUG) {
use Data::Dumper;
# log if we have debug on
logme ( message => "Debug on... level:$DEBUG");
}



#################
#
# Main line of the program
#
# Main subroutine calls
#
if ($SKIPCHECK){ 
	ss_sort(ss_gather(@POOLS));
} else {
	ss_sort(queue_compare(ss_gather(@POOLS)));
}


########
#
#
#
###
#
# ss_gather()
#
# Saveset list gathering Loop
# obtain list of complete Save Set IDs for each pool passed in to the 
# function. Seperate each save set into nonspanning and spanning savesets
# and dump into correct files.  Pass the list out as an array.
sub ss_gather {
	my @ssidout;
	foreach my $pool (@_){
		logme(message=> "ss_gather",
			level=>"DEBUG");
	
		#
		# read in the output of mminfo and dump into filehandle SSID.
		# output is 4 comma seperated fields.  If you change the 
		# reporting (-r) output of mminfo you will need to address this 
		# in the sorting loop
		print "Running mminfo against the NetWorker Server.\n"; 
		logme(message=> 
			"running mminfo: $NSRMMINFO -s $NSRSERVER -xc, -r sumflags,volume,ssid,cloneid -q \"pool=$pool\" -q \"$mmquerystring\"",
		level=> "DEBUG") if $DEBUG;
		open (SSID, "$NSRMMINFO -s $NSRSERVER -xc, -r sumflags,volume,ssid,cloneid -q \"pool=$pool\" -q \"$mmquerystring\"|") 
			or dielog( "Problem contacting mminfo: $!");
		#
		# read the 4 fields and dump to the array @ssidtmp.
		my @ssidtmp=<SSID>;
		# for debug
		if ($DEBUG > 6) {
			foreach(@ssidtmp) {
				logme(message=>"ssidtmp: $_",
					level=> "DEBUG");
			}
		}
		close (SSID);
		push (@ssidout, @ssidtmp);
	}
	return (@ssidout);
} # end ss_gather()
#
# 
# queue_compare()
# compare incoming list to queue and filter previously 
# selected savesets passing the list of unique save sets 
# through as an array
sub queue_compare {
	my @newssids=@_;
	my @oldssids;
	my @uniquessids;
	logme(message=>"queue_compare");
	#print(Dumper(@newssids)."\n");
	# get all files in the queue directory 
	# and dump them to an array of filenames
	my @qfiles = <$QUEUEDIR/*>;
	foreach my $qf (@qfiles) {
		logme(message=>"reading $qf",
			level=>"DEBUG") if $DEBUG;
		open (QF, "< $qf") or logme(message=>"cannot open $qf: $!",
		level=>"ERROR");
			my @tqf = <QF>;
			foreach my $qline (@tqf) {
				#print "queue line: $qline\n";
				if ($qline =~ /^[0-9]..*/) {
					chomp($qline);
					my @baz = split("/",$qline,2);
					push (@oldssids, $baz[0]);
					logme(message=>"queue line: $baz[0]",
						level=> "DEBUG") if $DEBUG;
				}
			}
	}
	#
	# read all the ssids and place them into an array of ssids
	# find the new ssids
	my %seen;
	# build lookup table
	foreach my $pssid (@oldssids){
		chomp $pssid;
		$seen{$pssid} =1;
	}
	#print("seen ssids array:\n".Dumper(%seen)."\n");
	foreach my $ss (@newssids) {
		chomp($ss);
		my @foo = split (',',$ss,4);
		logme(message=>"looking for SSID: $foo[2]",
			level=>"DEBUG") if $DEBUG;
    		unless ($seen{$foo[2]}){
			logme(message=>"SSID not seen: $foo[2]",
				level=>"DEBUG") if $DEBUG;
			push(@uniquessids, "$foo[0],$foo[1],$foo[2],$foo[3]");
		}
	}
	#print("unique ssids array:\n".Dumper(@uniquessids)."\n");
	return(@uniquessids);
}
#
#
# Sorting Loop.
# here I take the array from the Saveset gathering Loop above and sort 
# though it line by line.  All i'm doing here is reading in the list 
# of savesets and sorting out the ones i want like complete and "head" 
# savesets and creating a "worklist" keyed against the tape volume ID
#
sub ss_sort {
	logme(message=> "Sorting SaveSets");

#	logme(message=> print $DEBUG);
	foreach (@_) {
		print "." if $DEBUG;
		my ($flags, $volume, $ssid, $cloneid) = split (',');
		#print "flags: $flags\n";
		#
		if ($flags eq "flags") {  
			next; # skip the column first row
		}
		if ($flags =~ m/^c/) {  	# find complete savesets
			# for testing
			#print "DEBUG: $ssid \n";
			#print COMP "$volume,$ssid\\$cloneid\n";
			#
			# Print an "x" per complete save set to show progress.  
			# this can be commented out if desired
			print "x" if $DEBUG;
			
			# Dump the ssid and cloneid pair into 
			# a hash of hashes using the volume 
			# number as the key
			$worklist{$volume} = [] unless exists $worklist{$volume};
			logme(message=>"Volume: $volume - Found head SSID: $ssid ",
			level=>"DEBUG") if $DEBUG > 4;
			push(@{$worklist{$volume}},$ssid."/".$cloneid);
			#
			next; 
		}
		if ($flags =~ m/^h/) { # find head of spanning savesets
			# for testing
			#print "$ssid is not continious\n";
			
			# Print a "+" per "spanning" saveset to show progress
			# this can be commented out if desired
			print "\+" if $DEBUG;
			
			#
			#
			$worklist{$volume} = [] unless exists $worklist{$volume};
			push(@{$worklist{$volume}},$ssid."/".$cloneid);
			next; 
		}

	} ## Close foreach()
	print "\n";
	# Drive Queue Loop
	# loop through each volume and sort into a number of queues determined by the 
	# number of queues set in $QUEUES. The limitation is that each volume's savesets 
	# can only go to one queue and can cannot be divided between queues.  This allows NetWorker
	# to clone more efficiently. If the number of volumes is less than the number of queues, then
	# only the amount of queues for each volume will be created.
	#
	# Steps:
	# * take the list of savesets and sort by volume number
	# * alternately assign the savesets of each volume to a queue (the number of queues set in $QUEUES)
	# * take the next volume and assign to the next queue
	# * when all queues have been filled, return to the first queue and add the next volume's save sets
	# * save the ssid/cloneid as a hash value keyed by the queue number 
	#
	my %queue;
	foreach $volume (sort keys %worklist){
		#
		($i++ >= $QUEUES) && ($i=1);
		logme(message=>"Queue number: $i",
		level=>"DEBUG") if $DEBUG;
		logme(message=> "Volume: $volume",
			level=>"DEBUG") if $DEBUG;
		my @sssort = @{$worklist{$volume}};
		foreach my $sscl (@sssort) {
			my $q=$i;
			chomp($sscl);
			logme(message=>"queue $q SSID: $sscl",
				level=>"DEBUG") if $DEBUG;
			push (@{$queue{$q}},$sscl );
		}
	} # end Drive queue loop

# Queue File Loop
# Loop through the queues and create queuefiles in the queuedir 
# that queue_runner.pl can read from.
	foreach my $qout (sort keys %queue ) {
		my $queuefile="$QUEUEDIR/ssq-$DESTPOOL-$$-q$qout-t0.qf$PRIORITY";
		logme (message=>"saving queue $qout to: $queuefile");
		open ( SSDQ, ">>$queuefile") || dielog ("Error writing queuefile $$queuefile:$!");
		my @ssids = @{$queue{$qout}};
		foreach my $s (@ssids) {
		print (SSDQ $s."\n");
		}
		close (SSDQ);
	}
} # end ss_sort()
# put a visual indicator in the log to show the end of the run
logme(message=>"PID:$$ ##################################",level=>"STOP");
# clear the line
print "\n";
#
