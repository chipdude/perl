#!/usr/bin/perl -w

#
# cmpVERSION - compare two Perl source trees for modules
# that have identical version numbers but different contents.
#
# withg -d option, output the diffs too
#
# Original by slaven@rezic.de, modified by jhi.
#

use strict;

use ExtUtils::MakeMaker;
use File::Compare;
use File::Find;
use File::Spec::Functions qw(rel2abs abs2rel catfile catdir curdir);
use Getopt::Std;

sub usage {
die <<'EOF';
usage: $0 [ -d ] source_dir1 source_dir2
EOF
}

my %opts;
getopts('d', \%opts) or usage;
@ARGV == 2 or usage;

for (@ARGV[0, 1]) {
    die "$0: '$_' does not look like Perl directory\n"
	unless -f catfile($_, "perl.h") && -d catdir($_, "Porting");
}

my $dir2 = rel2abs($ARGV[1]);
chdir $ARGV[0] or die "$0: chdir '$ARGV[0]' failed: $!\n";

# Files to skip from the check for one reason or another,
# usually because they pull in their version from some other file.
my %skip;
@skip{
    './lib/Carp/Heavy.pm',
    './lib/Exporter/Heavy.pm',
    './win32/FindExt.pm'
} = ();
my $skip_dirs = qr|^\./t/lib|;

my @wanted;
my @diffs;
find(
     sub { /\.pm$/ &&
	       $File::Find::dir !~ $skip_dirs &&
	       ! exists $skip{$File::Find::name}
	       &&
	       do { my $file2 =
			catfile(catdir($dir2, $File::Find::dir), $_);
		    (my $xs_file1 = $_)     =~ s/\.pm$/.xs/;
		    (my $xs_file2 = $file2) =~ s/\.pm$/.xs/;
		    my $eq1 = compare($_, $file2) == 0;
		    my $eq2 = 1;
		    if (-e $xs_file1 && -e $xs_file2) {
		        $eq2 = compare($xs_file1, $xs_file2) == 0;
		    }
		    return if $eq1 && $eq2;
		    my $version1 = eval {MM->parse_version($_)};
		    my $version2 = eval {MM->parse_version($file2)};
		    return unless
			defined $version1 &&
			defined $version2 &&
                        $version1 eq $version2;
		    push @wanted, $File::Find::name;
		    push @diffs, [ "$File::Find::dir/$_", $file2 ] unless $eq1;
		    push @diffs, [ "$File::Find::dir/$xs_file1", $xs_file2 ]
								   unless $eq2;
		} }, curdir);
for (sort @wanted) {
    print "$_\n";
}
exit unless $opts{d};
for (sort { $a->[0] cmp $b->[0] } @diffs) {
    print "\n";
    system "diff -du '$_->[0]' '$_->[1]'";
}

