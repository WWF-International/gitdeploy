use strict;

my $pipe_fname = "/tmp/gitdeploy_test";

our $BASE_DIR = "$ENV{HOME}/git";
# directories in which a `git pull` will be done

my @dirs = (
	"$BASE_DIR/wwf-uk.earthhour-wordpress"
);

while(1) {
	open FH, "<", $pipe_fname || die "couldn't open";
	close FH;
	print "Awake\n";
	for (@dirs) {
		print "Updating: $_\n";
		system "git --git-dir='$_' pull";
		print "done\n";
	}
	print "Waiting...\n";
}
