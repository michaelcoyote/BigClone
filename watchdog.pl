#!/usr/bin/perl
#
#
# watchdog.pl
# Run from “cron” every 10-30 minutes
# Generate a hard error on these events
#  *.qf[1-4] files older than a configured time (4 hours?)
#  *.qf[5-9] files older than a configured time (12 hours?)
#  $CLONEPROCID.inp files older than a configured time (12 hours)
#  clone process lock file without clone process
#
#
###### 
# Do not remove or disable without good documented reason.
#
use strict;
use warnings;
# addtional libraries
use Getopt::Std;
use File::stat;
#
use vars qw($NSRSERVER $CLONETMP $QUEUEDIR $CLONEWRAPPER $DEBUG $TEST 
$LOGFILE $LOGLOC $NSRBIN $NSRCLONE $CONFIG %options $SAVEGROUP $STOPFILE 
 $LOCKDIR $LOCKFILE $LOGFILE $MAXTRIES $NSRADMIN @PHYCLONEDRIVES $mainpid);
#
#
#
#
# setup the temp dir we'll use
$CLONETMP="./tmp/";
#
# Location of Queue Directory
$QUEUEDIR="./queuedir";
#
# Logs go here
$LOGLOC="./log";
$LOGFILE="$LOGLOC/watchdog.log";
####  Code starts here.  No user set vars below this line
#
#
#
#####
# set up our options
#
# -D: debug
# -c: config file
#
#
getopts('Dc:',\%options);

####
# make command line switches do something
#
# just makes code easier to read, really.
if ($options{D}) { $DEBUG=1;} else { $DEBUG=0;}


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
#
#
#
# 
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
	# select((select(DEV), $| = 1)[0]); 
	if ( $use_stdout ) {
		printf("%s: %s - %s\n",$date,$args{level},$args{message});
	# write to our logfile
	}else {
		printf(LOGFILE "%s: %s - %s\n",$date,$args{level},$args{message});
		close(LOGFILE);
	}
} #end logme subroutine





### Generate a hard error on these events
# *.qf[1-4] files older than a configured time (4 hours?)
# *.qf[5-9] files older than a configured time (12 hours?)
# *.inp files older than a configured time (12 hours)

#check_qf("ssq-ClonePool-6032-q1-t0.qf4","3660");
check_qf("422861");


# clone process lock file without clone process  
# 	(difficult as clone proc id changes in windows)

# check for file over a given age in hours 
sub check_qf {
	my $age = $_[0];
	#logme(message => "Reading files from $QUEUEDIR") if $DEBUG;
	#
	my @qlist;
	opendir(QDIR, $QUEUEDIR) 
		or dielog("couldn't open $QUEUEDIR: $!");
	my @qfiles = readdir QDIR;
	closedir QDIR;
	foreach my $qfile (@qfiles){

		#logme(message=>"checking $qfile");
		#
		$qfile =~ /(ssq-\w{2,16}-\d+-q\d-t\d)(\.qf\d)$/;
		my $qfname=$1;
		my $qfpri=$2;
		#
		my $qfall="$QUEUEDIR/$qfile";
		my $qfstat = stat($qfall) or warn "cant stat $qfall: $!";
		#
		# populate array
		# but only use files ending with qf[0-9]
		my $fileage = (time() - $qfstat->mtime);
		logme(message=>"$qfile is $fileage seconds old");
		if ($fileage > $age) {
			#push(@qfold, $qfile);
			logme(message=>"$qfile is older than $age seconds old. Possibly Stale");
		}
	}
}


#  quickly rename an inp file back to a 
#  qf# file and increment the tries
sub reset_queuefile {
	my $queuefile=$_[0];
	# pull out the priority and increment it
	$queuefile =~/(ssq-\w{2,16}-\d+-q\d-t\d\.qf)(\d)\.inp/;
	my $qf_pri=$2;
	$qf_pri-- unless ($qf_pri < 3);
	my $qfn= "$1$qf_pri";
	rename($queuefile, $QUEUEDIR."/".$qfn) or logdie("problems renaming queuefile : $!");
	logme("queuefile moved to $qfn");
	return(0);
}

