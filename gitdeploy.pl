#!/usr/bin/perl -w
use feature qw(say);
use strict;
use YAML::Tiny;
use Getopt::Std;
use IO::Handle;
use Proc::Daemon;

my $CONFIG_FILE = "/etc/gitdeploy.yml";

# parse command-line options
my %opts;
getopts('df:', \%opts);
if ($opts{f}) {
	$CONFIG_FILE = $opts{'f'};
}

# initialise to the default config
my %CONF = (
	pipef   => "/tmp/gitdeploy_test",
	logf    => "/var/log/gitdeploy.log",
	pidf    => "/var/run/gitdeploy.pid",
	basedir => "/tmp",
	repos   => [] # empty set of repos by default
);

# attempt to read config file
(-f $CONFIG_FILE) || die "Config file $CONFIG_FILE doesn't exist";
my $fconf = YAML::Tiny->read($CONFIG_FILE);
# only read the first document
$fconf = $fconf->[0];

# place the config into the %CONF var, leaving the defaults in for any key that
# doesn't appear in the conf file
for (keys %$fconf) {
	$CONF{$_} = $fconf->{$_};
}

# fork a daemon and exit
my $child_pid = Proc::Daemon->new(
	work_dir     => $CONF{basedir},
	pid_file     => $CONF{pidf},
	child_STDOUT => ">>$CONF{logf}",
	child_STDERR => ">>$CONF{logf}"
)->Init;

if ($child_pid) {
	# parent
	say "Daemon $child_pid started";
	# parent should exit now
	exit;
}
# this is the child / daemon process

# open the log file
open LOG, ">>", $CONF{logf} || die "Couldn't open logfile $CONF{logf} for writing";
LOG->autoflush();
# make log file default place for output
select LOG;

# wraps the message in some handy logfile type business
sub logm {
	print "[", (scalar localtime), "] ", @_, "\n";
}

sub logdie {
	logm @_;
	die @_;
}

logm "Starting (pid:$$)";

# create the named pipe if it doesn't exist
if (! -p $CONF{pipef}) {
	logm "Creating named pipe $CONF{pipef}";
	unlink $CONF{pipef} if -f $CONF{pipef};
	require POSIX;
	# don't forget umask(1) will filter the mode here ...
	POSIX::mkfifo($CONF{pipef}, 0622) or
		die("Could not create named pipe $CONF{pipef}");
}

# for the startup, log each configured repo; and make sure it exists
for (@{$CONF{repos}}) {
	logm "repo: $_";
	logdie "ERROR: repo $_ doesn't exist" unless -d $_;
}

# call this when we want to finish cleanly
sub clean_exit {
	my $sig = shift;
	logm (($sig ? "received signal $sig; " : ""), "exiting");
	close LOG;
	exit;
}

# and set this up as the signal handler
$SIG{INT} = \&clean_exit;
$SIG{HUP} = \&clean_exit;

if ($opts{d}) { logm "debug exit"; exit };
# now enter main loop
while(1) {
	logm "Waiting for wakeup call";
	open FH, "<", $CONF{pipef} || die "couldn't open";
	close FH;
	logm "Awake";
	for (@{$CONF{repos}}) {
		logdie "Error: $_ not a directory" unless -d $_;
		logm "Updating: $_";
		my $retval = system "git --git-dir='$_' pull -q";
		logm "\t", ($retval == 0) ? "SUCCESS" : "FAILURE ($retval)";
	}
}
