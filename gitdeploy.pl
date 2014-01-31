use strict;

my $pipe_fname = "/tmp/gitdeploy_test";

our $BASE_DIR = "$ENV{HOME}/git";
# directories in which a `git pull` will be done

my @dirs = (
	"$BASE_DIR/wwf-uk.earthhour-wordpress"
);

if (! -p $pipe_fname) { die "named pipe $pipe_fname doesn't exist"; }

while(1) {
	open FH, "<", $pipe_fname || die "couldn't open";
	close FH;
	print "Awake\n";
	for (@dirs) {
		die "Error: $_ not a directory" unless -d $_;
		print "Updating: $_\n";
		system "git --git-dir='$_' pull";
		print "done\n";
	}
	print "Waiting...\n";
}
