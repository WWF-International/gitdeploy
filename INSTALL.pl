#!/usr/bin/perl -w
#
use strict;
use File::Path qw(make_path);
use File::Basename qw(fileparse);

my $BASEDIR = "deploy";

my %FILES = (
	"gitdeploy.pl"          => "usr/bin/gitdeploy",
	"gitdeploy.example.yml" => "etc/gitdeploy.example.yml",
	"Proc/Daemon.pm"        => "usr/share/perl5/vendor_perl/Proc/Daemon.pm",
	"Proc/Daemon.pod"       => "usr/share/perl5/vendor_perl/Proc/Daemon.pod"
);

for my $src (keys %FILES) {
	my $dst = "$BASEDIR/$FILES{$src}";
	my ($file, $dir, $suffix) = fileparse($dst);
	make_path($dir, 0755);
	system "cp -v $src $dst";
}
