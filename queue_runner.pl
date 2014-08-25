#!/usr/bin/perl
# queue_runner.pl
# Job Queue processor
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
######
# Variable processing
# 
# Make our variables global
# any new config variable belongs here
#
use vars qw($NSRSERVER $CLONETMP $QUEUEDIR $CLONEWRAPPER $DEBUG $TEST $SKIPCHECK
$LOGFILE $LOGLOC $NSRBIN $NSRCLONE $CONFIG %options $SAVEGROUP $STOPFILE 
 $LOCKDIR $LOCKFILE $LOGFILE $MAXTRIES $NSRADMIN @PHYCLONEDRIVES $mainpid);


#####
# set the defaults here and then optionally read in config
# 
## ## start config block ##
# 
#
#
# Config File 
#
# break this out to readable outside conf file

#
# NetWorker server
$NSRSERVER=("bocntbk12.boc.chevrontexaco.qnet");
#
# The device names of the Physical Clone drives as seen by NetWorker
#  (insure that all windows devices have 
#  double-escaped backslashes e.g. \\\\ = \)
@PHYCLONEDRIVES=qw("\\\\\\\\.\\\\Tape4801101" "\\\\\\\\.\\\\Tape4801102" "\\\\\\\\.\\\\Tape4801103" "\\\\\\\\.\\\\Tape4801104" "\\\\\\\\.\\\\Tape4801105" "\\\\\\\\.\\\\Tape4801106");
#
# setup the temp dir we'll use
$CLONETMP="./tmp/";
#
# Location of Queue Directory
$QUEUEDIR="./queuedir";
#
# Logs go here
$LOGLOC="./log";
#
# find our NetWorker executibles  here
# $NSRBIN="c:/Progra~1/Legato/nsr/bin";

# 
# stopfile to stop additional processing
$STOPFILE="./stop";

#
#lockfile to disallow multiple copies
#
$LOCKDIR="./lock";

#
#Logging function
#
$LOGFILE="$LOGLOC/queue_runner.log";

# Location of clone command
$NSRCLONE="nsrclone";

# Location of nsradmin command
#$NSRADMIN="$NSRBIN/nsradmin";
$NSRADMIN="nsradmin";

# Number of clone attempts before an error is thrown
$MAXTRIES="3";




##### end variable default
#
# initialize some variables
$DEBUG=0;
$CONFIG="";
$TEST=0;
$mainpid=$$;


# Lock file
#
$LOCKFILE="$LOCKDIR/queue_runner.lock";

#if ( $^O =~ /Win/ ) {
#  use Win32;
#  use WIN32::Process;
#  $LOGFILE=~ s/\//\\/g;
#}

#####
# set up our options
#
# -D: debug
# -s: NetWorker server
# -c: config file
# -t: test only, works very nice with -D
#
#
getopts('Dstc:',\%options);

####
# make command line switches do something
#
# just makes code easier to read, really.
if ($options{D}) { $DEBUG=1;}
if ($options{s}) { $SAVEGROUP=1;}
if ($options{t}) { $TEST=1;}
# 






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
# use to clear the lockfiles
sub dieunlock {
	# unlock and log
	my ($error) = @_;
	unlink ($LOCKFILE);
	logme(message => "$LOCKFILE Removed");
	#
	unlink ("$LOCKFILE") or dielog ("Error removing $LOCKFILE: $!");
	# log the error
	logme(message => "$error", 
		level => 'ERROR');
	logme(message => "queue_runner ended");
	die ("$error\n");
} # end dieunlock()


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
	} else {die "Config file not found please specify with -c file\n";}
}
#####


###
if ($DEBUG) {
use Data::Dumper;
# log if we have debug on
logme ( message => "Debug on... level:$DEBUG");
}




########################################
# Main line of program
#


##### 
# Check for a stopfile. 
# If it's set do no more cloning, but complete remaining jobs.
if (-e $STOPFILE) {
	print "Stopfile set: Remaining clone process will stop\n";
	logme( message => "Stopfile found: queue processing ended.  Remaining clone processes will finish." );
	exit(0);
}
####
# Check for a lockfile
if (-e $LOCKFILE) {
	print "Lockfile $LOCKFILE set: ending processing\n";
	logme( message => "Lockfile found: queue processing not started.");
	exit(0);
}
###
# Check to see what drive is avalible for use
my @drives = checkdrive();
# 
my $dn = @drives;
logme(message=>"$dn drives avalible");
# take the list of drives and loop through 
# it, and start a clone process for each free drive
for (my $i = 1;$i <= $dn;$i++) {
	#
	# Read in the list of in process queue files 
	# and select the highest priority queuefile
	my $queuefile = queue_read();
	#
	# Log the Current queue file containing the SSID's to clone
	logme(message => "Sending the queuefile $queuefile to clone processing");
	print "Sending the queuefile $queuefile to clone processing\n" if $DEBUG > 3;
	# start the clone operation and pass
	# the queue file selected earlier
	my ($clonequeuef,$clonetargetpool ) = clone_call($queuefile);
	# Test to make sure that clone_call() didn't choke on a
	# queuefile. If it did, skip to the next one.
	unless ($clonetargetpool){
		logme(message=>"skipping to next queuefile");
		next;
	}
	# 
	# make the clone happen
	logme(message=>"passing queuefile: $clonequeuef and Clone Pool: $clonetargetpool to clone_processor",
	level=>"DEBUG") if $DEBUG > 3;
	clone_processor($clonequeuef,$clonetargetpool);
	
} # end the drive clone loop

endclone(0);


#
#
############

###########
#
# all the subroutines live here
#
# checkdrive()
#
# compare the avalible drives from get_drives() to the 
# drives listed in the @PHYCLONEDRIVES array and
# return the allowed/listed drives as an array.
#
sub checkdrive {
	
	#if ($TEST) {
	#	my $d = "rd=mars:/dev/nrst0";
	#	return($d);
	#}

	##
	# check for available read (VTL) devices
	# read and write drives will probably need to be configured 
	# on each clone storage node

	# list avalible drives with get_drives()
	my @d = get_drives();
	
	# compare @d to defined list of drives
	#
	my %union;
	my %isect;

	print Dumper(@d) if $DEBUG >6;
	print Dumper(@PHYCLONEDRIVES) if $DEBUG >6;
	#
	# find the intersection of the set of avalible drive (@d) and
	# the physical drives allowable (@PHYCLONEDRIVES).
	# note that we are assuming at least a 1:1 ratio of virtual read
	# drives and physical write drives, so we're not going to 
	# concern ourself with looking for read drives
	foreach my $e (@d,@PHYCLONEDRIVES) {
		logme(message=> "checkdrive(): drv: $e",
			level=>"DEBUG") if $DEBUG > 5;
		$union{$e}++ && $isect{$e}++}
	my @drvout = keys %isect;
	#logme(message=> "Avalible drives: @drvout"
	#	level=> "DEBUG") if $DEBUG;
	logme (message=>"check_drives() returned drives: @drvout",
		level=> "DEBUG") if $DEBUG;
	# pass out the allowed drives
	return(@drvout);
	# if matching phy and virt drive pair exists, pass to queue-runner loop
	#
} # end checkdrive 
#
#
# get_drives()
#
# find tape drives that are: enabled and not in use 
# and return a list of them as an array
#
sub get_drives {
	#
	#
	# open nsradmin with the output going to filehandle
	# 
	# running these commands:
	# show enabled;NSR operation;name
	# print type: NSR device
	# 
	logme(message=> "connecting to nsradmin: $NSRADMIN -s $NSRSERVER -i nsradmin.txt",
	level=>"DEBUG") if $DEBUG >4;
	open (NSRADM, "$NSRADMIN -s $NSRSERVER -i nsradmin.txt |") or dielog "Cannot start nsradmin";

	#open (NSRADM, " < nsradm_test.txt") || dielog "Cannot start nsradmin";
	# should output a drive report that looks like this:
	#	
	#	name: "\\\\.\\Tape0";
	#	enabled: Yes;
	#	NSR operation: ;
	#
	my @nsradm_ret = <NSRADM>;
	print @nsradm_ret if $DEBUG >6;
	# initalize some vars
	my @avail_drives; # put each avalible drive here
	my $e=0; # does the line say "enabled"? increment this.
	my $n=0; # does the line say "name:"?  incrment this
	my $drvname=""; #store the open drive here until we push it onto an array
	print "\nSorting and finding drives:";

	foreach (@nsradm_ret) {
		my @nsradm_lines = split ;
		# loop through and find enabled drives
		foreach my $devck (@nsradm_lines) {
			logme(message=>"current nsradm line = $devck",
				level=>"DEBUG")if $DEBUG > 5;
			chomp($devck);
			# 
			# check to see if it's a name
			if ($devck eq "name:") {
				print "n";
				$n = 1; # set this to select and set the name
				next;
			} # end of if name	
			#
			# if enabled set $x and return
			if ($devck eq "Yes;") {
				$e = 1;
				print "e";
				logme (message=> "Found an enabled drive: $drvname",
					level=>"DEBUG") if $DEBUG > 5;
				next;
			} # end of if enabled
			# if disabled 
			if ($devck eq "No;") {
				$e = 0;
				$n = 0;
			 	logme(message=> "Drive $drvname disabled",
					level=>"DEBUG") if $DEBUG > 5;
			 	next;
		 	} # end of if disabled
			# set the drive name
			if ($n > 0) {
				$drvname=$devck;
				chop($drvname);
				$n = 0;
				logme (message=> "Found drive $drvname",
					level=>"DEBUG") if $DEBUG;
				next;

			} # end of set name	
			
		 	# if blank nsr exists for enabled
		 	if ($e > 0){
				if ($devck eq ";") {
				 	logme(message=> "Found a free drive: $drvname",
					level=> "DEBUG") if $DEBUG > 4;
				 	push(@avail_drives, $drvname);
				 	$e = 0;
					$n = 0;
				 	next ;
				} # end if 
		 	} # end of if blank nsr
		} #end of drive seeking foreach loop
	} # end of foreach
	print "\n";
	logme(message=> "get_drives() found avalible drives:  \@avail_drives",
	level=>"DEBUG") if $DEBUG;
	return @avail_drives;
} # end get_drives()
###

#####
# Take saveset SSID queue files from the queue directory by priority
# priority by file extension (*.qf1 highest to *.qf9 lowest) and return 
# the highest priority queue file as a scalar. 
#
# Levels:
# qf1 - reserved of future use/unused
# qf2 - manual emergency clone 
# qf3 - highest priority
# qf4 - high priority
# qf5 - medium priority
# qf6 - medium low priority
# df7 - low priority
# qf8 - reserved of future use/unused
# qf9 - reserved of future use/unused
#
sub queue_read {
	#
	# set up some locals
	my @qlist;
	# read in fileames from $QUEUEDIR to array
	#
	logme(message => "Reading files from $QUEUEDIR") if $DEBUG;
	opendir(QDIR, $QUEUEDIR) or dielog("couldn't open $QUEUEDIR: $!");
	my @qfiles = readdir QDIR;
	closedir QDIR;
	#
	# we're expecting the direcory of files to look something like this:
	#
	# file9_Clonepool1-q1-t0.df2
	# file2_Clonepool1-q1-t0.qf4
	# file2_Clonepool2-q2-t0.qf4
	# file1_Clonepool1-q1-t0.qf7
	# file5_Clonepool3-q1-t1.qf3.inp
	# ..
	# file4_Clonepool5-q2-t1.qf5.inp
	# parse out filename into hash
	#
	# clean up the filenames and push to a new array
	#
	print "Reading queue directory:";
	logme(message=>"Reading queue directory");
	foreach my $qfile (@qfiles){

		logme(message=> "$qfile");
		# 
		if ($qfile =~/(ssq-\w{2,16}-\d+-q\d-t\d)(\.qf\d)$/){
			my $qfname=$1;
			my $qfpri=$2;
			#
			# Print a little visual cue to let an observer 
			# know that something is actually happening
			print "r";
			#
			# populate the keyed hash using the filename as the key,
			# but only use files ending with qf[0-9]
			if ($qfpri =~ /\.qf\d$/) {
				# Print a little visual cue to let an observer 
				# know that something is actually happening
				print "w";
				push(@qlist,$qfname.$qfpri);
			}
			print " $qfname$qfpri\n" if $DEBUG > 5;
			# If we were entering the data by hand, 
			# the data structure would look something like this:
			# @qlist = ( "file9_t0.qf2", "file2_t0.qf4", "file5_t0.qf3", "file1_t0.qf7");
			#
		}
	} # end the queue reader loop
	print "\n";
	if ($DEBUG >6  ){
		print "The filelist before sorting:\n"; 
		print @qlist."\n";
		print "\n";
	}
	# Sort by the file extention subroutine
	sub file_ext {
		# find the last part of each string
		substr($a,-1) cmp substr($b,-1)
		}
	# sort the filenames by the second string (extention)
	my @sortqlist = sort file_ext @qlist;
	if ($DEBUG > 6 ){
		print "The filelist after sorting:\n";
		print ( Dumper(@sortqlist));
		print "\n";
	}
	# select "topmost" queuefile and pop off the list to clone-wrapper
	my @revqlist = reverse @sortqlist;
	my $qf_ret = pop(@revqlist) ;
	if ($qf_ret) {
		logme( message => "queue_read returning file: $qf_ret", 
			level => "DEBUG") if $DEBUG;
		return ($qf_ret);
	} else {
		logme(message=>"No queuefiles found, program ending.");
		logme(message=>"PID:$$ ##################################",level=>"STOP");
		exit();
	}

} #end queue_read
###
#
# clone_call()
#
# read in the queue file name as a scalar, increment the number of tries,
# append the .inp extenton, return the name of the file and the pool name 
# in that order as two seperate scalar variables.
# In addition insure that there are no more than $MAXERRORS failures of
# the inproccess queue file, and rename the queuefile if an error occurs
# 
sub clone_call {
	my $qfile=$_[0];
	# Here's an example of a queue file name we'll be matching
	#	  (ssq-)(ClonePool)(-6032-q1-t)(0)(.qf4)
	$qfile =~/(ssq-)(\w{2,16})(-\d+-q\d-t)(\d)(\.qf\d)$/;
	# pull sections out of the regex above
	my $tries = $4;
	my $dpool = $2;
	$tries++;
	# reconsitute the filename with the incremented number of ties
	my $inpfile = "$QUEUEDIR/$1$dpool$3$tries$5.inp";
	print "\n$dpool\n$tries\n" if $DEBUG >4;
	my $qinfile="$QUEUEDIR/$qfile";
	# check the incoming queue file, if there are more than 
	# 3 retries append the .err extention
	if ($tries > $MAXTRIES) {
		logme(message=> "Too many tries for $qfile. This Queue File will not be retried",
			level=>"ERROR");
		# move the file out of the way and stop 
		# the clone attempt
		my $qferr = "$qinfile.err";
		print "$qinfile\n";
		rename ($qinfile, "$qferr") or dielog("Problem renaming failed $qfile:$!");
		logme(message=>"$qinfile moved to $qferr");
		return (undef , undef);
	} else {
	
		open(QFILE, "< $qinfile") || dielog("Can't open $qinfile for reading: $!");
		my @queue = <QFILE> ;
		close QFILE;
		# move the *.qf[1-9] file to .inp to show 
		# that the clone is in process.
	
		logme(message=>"Creating in progress file: $inpfile");

		open (INPFILE, "> $inpfile") or dielog ("Creating $inpfile failed: $!");
		# search through the file until ^tries* is found and dump
		# the file to an array
		print "reading and rewriting queue:";
		foreach(@queue) {
				my $qline1 =$_;
			chomp($qline1);
			# 
			# print the ssid/cloneid pair to the new inprogress file
			print "ss"; # visual indicator
			print INPFILE "$qline1\n";
		}
		print "**\n";
		close INPFILE;
		unless ($TEST){
			unlink $qinfile or dielog("error removing old queue $qinfile :$!");
		}
		#
		# call clone_processor and let it start nsrclone 
		# in the background.  
		return($inpfile,$dpool);
		#
	} #end of else
} # end of clone_call()	
#
# clone_processor()
# 
# fork() off a process to handle cloning and staging while trapping any error messages
# in the logs. On success move the queue file out of the way. On any other message 
# increase the priority increment the number of tries using the reset_queuefile() function
#
# NOTE: in a UNIX/Linux system, the main line of the program will return leaving the 
# forked process to run in the backround. In Windows the fork() system call is not 
# supported and is simulated by Perl, so under Windows the main line will exit, howeever the 
# program will not return until the clone section below completes.
#
sub clone_processor {

	# ingnore children.  This will keep dead 
	# processes from hanging around
	$SIG{CHLD}="IGNORE";
	
	# pass the queue files to nsrclone wrapper for processing
	
	my $dqueuefile = $_[0];
	my $destpool = $_[1];
	my $pid;
	# Clone Fork 
	# fork() off another process to handle the cloning/staging.
	logme(message=>"cloning from $dqueuefile using $destpool");
	#
	# fork out to a clone process
	unless ($pid = fork) {
		unless (fork) {
			# create the temp file
			my($inpqfile, $inpqpath, undef) = fileparse($dqueuefile,"qf\d");
			# Here's an example of a queue file name we'll be matching
			#	  	(ssq-ClonePool-6032-q1-t0)(.qf4)
			#$dqueuefile =~/(ssq-\w{2,16}-\d+-q\d-t\d)(\.qf\d)$/;
			#my $inpqfile=$1.$2;
			print "$inpqfile/n";
			# 
			# use a lock file to insure that queuefile is not ran twice
			my $cllock = "$LOCKDIR/clone-$mainpid-$inpqfile-lock";
			open(CLONELOCK, "> $cllock") || dielog("Unable to open clone lock file $cllock: $!");
			logme(message=>"creating lockfile: $cllock");
			# Write out the queue file name to the lock file.  
			print CLONELOCK "queuefile: $dqueuefile\n";
			print CLONELOCK "parentpid: $mainpid\n";
			#
			# run nsrclone from an open() call in order
			# trap sucess and error messages from nsrclone
			open( NSRCLONE, "$NSRCLONE -s $NSRSERVER -b$destpool -v -S -f $dqueuefile 2>&1|") 
				or dielog ("$NSRCLONE Failed: $!");
			# on completion, report the error level and any 
			# error messages to the parent and exit
			my @cloneout = <NSRCLONE>;
			close(NSRCLONE);
			print Dumper(@cloneout) if $DEBUG > 6 ;
			my $success=0;
			# 
			# test for sucess or failure
			foreach (@cloneout) {
				my $cl_out = $_;
				chomp($cl_out);
				if ( /Successfully\ cloned\ all/) {
					$success=1;}
				print "clone output line:$cl_out\n" if $DEBUG > 4;
				logme(message=> "$cl_out", 
					level=> "CLONE");
			} #endforeach
			# 
			# move the queufile out of the way if sucessful or requeue if not
			if ($success) {
				rename($dqueuefile, $inpqfile."done") 
					or dielog("Rename of queuefile failed: $!");
			} else {
				logme(message=>"requeueing queuefile",
					level=>"ERROR");
				reset_queuefile($dqueuefile);
			}
			# remove the clone file
			close (CLONELOCK);
			unlink($cllock) 
				or logme(message=>"unable to remove clone lock file $cllock : $!",
					level=>"ERROR");

			logme(message=>"clone processes finished, clone parent PID:$mainpid exiting");

			exit 0;
		}
		exit 0;
	}
	sleep 1;
} # end of clone_processor()

#  reset_queuefile()
#  quickly rename an inp file back to a .qf# file 
#  and increment the tries section of the filename
#
sub reset_queuefile {
	my $queuefile=$_[0];
	# pull out the priority and increment it
	$queuefile =~/(ssq-\w{2,16}-\d+-q\d-t\d\.qf)(\d)\.inp/;
	my $qf_pri=$2;
	$qf_pri-- unless ($qf_pri<3);
	my $qfn= "$1$qf_pri";
	rename($queuefile, $QUEUEDIR."/".$qfn) or logdie("problems renaming queuefile : $!");
	logme(message=>"queuefile moved to $qfn");
	return(0);
}

# endclone()
# put an indicator in the log and exit the program
sub endclone {
	# put a visual indicator in the log to show the end of the run
	logme(message=>"PID:$$ ##################################",level=>"STOP");
	# clear the line
	print "\n";
	exit(0);
}

####  END
