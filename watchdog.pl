#!/usr/bin/perl
#
#
# watchdog.pl
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
$LOCKDIR $LOCKFILE $LOGFILE $MAXTRIES $NSRADMIN @PHYCLONEDRIVES $mainpid $f $a
$QUEUEAGEMIN $WDLOGFILE $INFILEAGEMIN $LOCKAGEMIN $MAILSERV $MAILER );
#
#
#
# The age of the queue files in minutes
$QUEUEAGEMIN=900;
# age of the *.inp files in minutes
$INFILEAGEMIN=900;

# Age of lock files in minutes
$LOCKAGEMIN=900;

# Mail Server
$MAILSERV="mailhost-hou150.chevrontexaco.net";
#
# configure the mail server
$MAILER="smtpmail \-s \"Stale Clone Queuefiles Report \" \-h $MAILSERV \-f gnmi\@chevron.com gnmi\@chevron.com";


#
# setup the temp dir we'll use
$CLONETMP="./tmp/";
#
# Location of Queue Directory
$QUEUEDIR="./queuedir";
#
# Logs go here
$LOGLOC="./log";
$WDLOGFILE="$LOGLOC/watchdog.log";

#
$LOCKDIR="./lock";
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
getopts('Dvc:',\%options);

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
	} else {die "Config file not found please specify with -c file\n";}
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
	$use_stdout=1 unless(open(LOGFILE, ">>$WDLOGFILE"));
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



open (MAIL, "|$MAILER") || die ( "$MAILER failed: $!\n");
#

print MAIL "\n";

### Generate a hard error on these events
# *.qfn files older than a configured time (12 hours?)
# *.inp files older than a configured time (12 hours)

#check_qf("ssq-ClonePool-6032-q1-t0.qf4","3660");


format MAIL =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<@|||||||||||||||||
$f,                                                              $a
.

check_qf();
check_lock();

# check for queuefiles over a given age in hours 
sub check_qf {
	#
	my (@qfold,@infold,@qfok,@infok);
	opendir(QDIR, $QUEUEDIR) 
		or dielog("couldn't open $QUEUEDIR: $!");
	my @qfiles = readdir QDIR;
	closedir QDIR;
	foreach my $qfile (@qfiles){
		#
		chomp($qfile);
		if ($qfile =~ /ssq-\w{2,16}-\d+-q\d-t\d\.qf\d$/) {
			#
			my $qfall="$QUEUEDIR/$qfile";
			my $qfstat = stat($qfall) or warn "cant stat $qfall: $!";
			#
			# populate array
			# but only use files ending with qf[0-9]
			my $qfileage = int(((time() - $qfstat->mtime)/60));
			logme(message=>"$qfile is $qfileage minutes old");
			if ($qfileage > $QUEUEAGEMIN) {
				push(@qfold, $qfile.",".$qfileage);
				logme(message=>"$qfile is older than $QUEUEAGEMIN minutes old. Possibly Stale");
			} else {
				push(@qfok, $qfile.",".$qfileage);
			} #seperate the old from the new files
		} # qfile regex end if
		if ($qfile =~ /ssq-\w{2,16}-\d+-q\d-t\d\.qf\d\.inp$/) {
			#
			my $infall="$QUEUEDIR/$qfile";
			my $infstat = stat($infall) or warn "cant stat $infall: $!";
			#
			# populate array
			# but only use files ending with qf[0-9]
			my $infileage = int(((time() - $infstat->mtime)/60));
			logme(message=>"$qfile is $infileage minutes old");
			if ($infileage > $INFILEAGEMIN) {
				push(@infold, $qfile.",".$infileage);
				logme(message=>"$qfile is older than $INFILEAGEMIN minutes old. Possibly Stale");
			} else {
				push(@infok, $qfile.",".$infileage);
			}
		}
	} # end filesorting foreach
	
	print( MAIL "\nPossibly Stale Queuefiles\n");
	print(MAIL "Queue File Name                                  File Age In Minutes\n");
	print (MAIL "---------------------------------------------------------------------\n");
	foreach my $qold (@qfold) {
		($f,$a) = split (/,/, $qold);
		write MAIL;
	}	
	print(MAIL "\nPossibly Stale Inprogress Files\n");
	print(MAIL "Inprogress File Name                             File Age In Minutes\n");
	print (MAIL "---------------------------------------------------------------------\n");
	foreach my $infold (@infold) {
		($f,$a) = split (/,/, $infold);
		write MAIL;
	}
	print "\n";

}





sub check_lock {
	#
	my (@lockfileold,@lockfileok);
	opendir(LDIR, $LOCKDIR) 
		or dielog("couldn't open $LOCKDIR: $!");
	my @lockfiles = readdir LDIR;
	closedir LDIR;
	foreach my $lockfile (@lockfiles){
		#
		chomp($lockfile);
		if ($lockfile =~ /ssq-\w{2,16}-\d+-q\d-t\d\.qf\d\.lock$/) {
			#
			my $lfall="$LOCKDIR/$lockfile";
			my $lfstat = stat($lfall) or warn "cant stat $lfall: $!";
			#
			# populate array
			# but only use files ending with qf[0-9]
			my $lockfileage = int(((time() - $lfstat->mtime)/60));
			logme(message=>"$lockfile is $lockfileage minutes old");
			if ($lockfileage > $LOCKAGEMIN) {
				push(@lockfileold, $lockfile.",".$lockfileage);
				logme(message=>"$lockfile is older than $LOCKAGEMIN minutes old. Possibly Stale");
			} else {
				push(@lockfileok, $lockfile.",".$lockfileage);
			} #seperate the old from the new files
		} # qfile regex end if
	} # end filesorting foreach
	print( MAIL "\nPossibly Stale Lock Files\n");
	print( MAIL "Lock File Name                                   File Age In Minutes\n");
	print ( MAIL "---------------------------------------------------------------------\n");
	foreach my $lockold (@lockfileold) {
		($f,$a) = split (/,/, $lockold);
		write;
	}	

}



sub check_inp {
	my $infage = int( $_[0]);
	#logme(message => "Reading files from $QUEUEDIR") if $DEBUG;
	#
	my @inflist;
	opendir(NDIR, $QUEUEDIR) 
		or dielog("couldn't open $QUEUEDIR: $!");
	my @nfiles = readdir NDIR;
	closedir NDIR;
	my (@nfold, @nfok);
	foreach my $nfile (@nfiles){


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

print MAIL "\n";

close (MAIL);


