#!/usr/bin/perl -w
use feature qw(say);
use strict;
use YAML::Tiny;
use Getopt::Std;
use IO::Handle;
use Proc::Daemon;
use Sys::Syslog;

my $BRANCH_TAG  = "gitdeploy/branch_name";
my $CONFIG_FILE = "/etc/gitdeploy.yml";

# parse command-line options
my %opts;
getopts('dnkf:', \%opts);
if ($opts{f}) {
	$CONFIG_FILE = $opts{'f'};
}

# initialise to the default config
my %CONF = (
	pipef   => "/tmp/gitdeploy_test",
	pidf    => "/var/run/gitdeploy.pid",
	basedir => "/tmp",
	user    => "gitdeployadm",
	repos   => [], # empty set of repos by default
	remote  => "origin",
);

sub conf_valid {
	my $conf = shift;
	if (!defined $conf || !$conf->isa("YAML::Tiny")) {
		warn "Reading YAML file did not produce a YAML::Tiny object " . ref $conf;
		return 0;
	}
	if ($#{$conf} < 0) {
		warn "YAML file did not contain any documents";
		return 0;
	}
	if (!defined $conf->[0]->{repos} || ref($conf->[0]->{repos}) ne "ARRAY") {
		warn "No repos or badly formatted repos";
		return 0;
	}
	if (!-d $conf->[0]->{basedir}) {
		warn "Base dir doesn't exist or isn't reachable";
		return 0;
	}
	chdir($conf->[0]->{basedir});
	for (@{$conf->[0]->{repos}}) {
		if (! -d $_) {
			warn "Repo $_ doesn't exist";
			return 0;
		}
	}
	return 1;
}

# attempt to read config file
(-f $CONFIG_FILE) || die "Config file $CONFIG_FILE doesn't exist";
my $fconf = YAML::Tiny->read($CONFIG_FILE);
die "Could not parse $CONFIG_FILE ($@)" unless conf_valid $fconf;

# only read the first document
$fconf = $fconf->[0];

# place the config into the %CONF var, leaving the defaults in for any key that
# doesn't appear in the conf file
for (keys %$fconf) {
	$CONF{$_} = $fconf->{$_};
}

chdir($CONF{basedir});

# make sure we aren't already running
my $pid = 0;
if (-f $CONF{pidf}) {
	open PIDF, "<", $CONF{pidf} || die "PID file exists, but I can't read it";
	$pid = <PIDF>;
	close PIDF;
	# send signal zero to see if it's alive
	if (kill(0, $pid) == 0) {
		# it's dead
		$pid = 0;
		say "Deleting stale PID file $CONF{pidf}";
		unlink $CONF{pidf};
	}
}

# were we asking to kill?
if ($opts{k}) {
	my $sig = 1; # HUP
	die "Not running (-k option)" unless ($pid > 0);
	kill $sig, $pid;
	say "Sent signal $sig to $pid";
	# all we wanted to do with this option, so exit
	exit;
}

# are we already running? if so it's in an error
die "Already running! (pid: $pid)" if ($pid > 0);

# what user to run as?
my @user = getpwnam($CONF{user});
die "Could not find user $CONF{user}" unless ($#user >= 2);

# if we are neither super user, nor the user that we want to run as, then we
# have a problem...
die "Cannot change user, need to be root for that" if ($< != $user[2] && $< != 0);

# -n means run in foreground
unless ($opts{n}) {
	# fork a daemon and exit
	my $child_pid = Proc::Daemon->new(
		work_dir      => $CONF{basedir},
		pid_file      => $CONF{pidf},
		setuid        => $user[2],
	)->Init;

	if ($child_pid) {
		# parent
		say "Daemon $child_pid started";
		# parent should exit now
		exit;
	}
}
# this is the child / daemon process, or foreground

# open the log file
openlog("gitdeploy", "pid", "daemon");

# wraps the message in some handy logfile type business
sub logm {
	print @_,"\n" if ($opts{n});
	syslog("info", "%s", join("", @_));
}

sub logdie {
	syslog("err", "%s", join("", @_));
	die @_;
}

logm "Starting (pid:$$)";
logm "Monitoring " . ($#{$CONF{repos}} + 1) . " repos";

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
	closelog;
	unlink $CONF{pidf};
	exit;
}

# and set this up as the signal handler
$SIG{INT} = \&clean_exit;
$SIG{HUP} = \&clean_exit;

# these functions deal with GIT; first arg is the git-dir
sub git_cmd {
	my ($repo, $cmd) = @_;
	return `git --git-dir='$repo' $cmd`;
}

sub git_branch {
	my $valid = git_cmd $_[0], "tag -l $BRANCH_TAG";
	if (!$valid) {
		return undef;
	} else {
		chomp(my $branch = git_cmd($_[0], "cat-file blob $BRANCH_TAG"));
		return $branch;
	}
}

sub git_head {
	chomp(my $head = git_cmd($_[0], 'log --pretty=%H -n1 HEAD'));
	logm "HEAD: $head";
	return $head;
}

sub git_changed_files {
	my ($gitdir, $old, $new) = @_;
	chomp(my @flist = `git --git-dir='$gitdir' diff --name-only $old..$new`);
	return @flist;
}

# now enter main loop
while(1) {
	logm "Waiting for wakeup call";
	open FH, "<", $CONF{pipef} || die "couldn't open";
	close FH;
	logm "Awake";
	for (@{$CONF{repos}}) {
		logdie "Error: $_ not a directory" unless -d $_;
		system "git --git-dir='$_' fetch --tags";
		my $branch = git_branch($_);
		if (!$branch) {
			logm "WARNING: invalid branch for repo $_";
			next;
		}
		my $start_head = git_head($_);
		logm "Updating: $_ ($branch)";
		my $retval = system "git --git-dir='$_' checkout -q --detach remotes/$CONF{remote}/$branch";
		logm "-> ", ($retval == 0) ? "SUCCESS" : "FAILURE ($retval)";
		my $new_head = git_head($_);
		if ($start_head ne $new_head) {
			# head has changed .. show what changed
			logm "Changed files: " . join(", ", git_changed_files($_, $start_head, $new_head));
		} else {
			logm "HEAD hasn't changed";
		}
	}
}
