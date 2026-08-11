use strict;
use warnings;
use Test::More tests => 1;
use FindBin ();

# sigilbadges.pl is a single top-level script, not a library — it runs
# GetOptions and the whole marker-scan/render pipeline the instant it's
# loaded, with no `unless caller` guard. That means it can never be
# `require`d for white-box unit testing (doing so would execute it against
# whatever README.md happens to sit in the test process's cwd). Every test
# in this suite instead shells out to it as a real subprocess, the same way
# a CI job or the composite action does — this file only confirms it
# compiles.
my $script = "$FindBin::RealBin/../sigilbadges.pl";
my $out = `perl -c "$script" 2>&1`;
like($out, qr/syntax OK/, 'sigilbadges.pl compiles cleanly');
