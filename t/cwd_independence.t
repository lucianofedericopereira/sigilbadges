use strict;
use warnings;
use Test::More tests => 6;
use File::Temp qw(tempdir);
use FindBin ();
use Cwd qw(getcwd);

# sigilbadges.pl resolves its bundled logos via FindBin's $Bin (the
# script's own real location), not the process's current working
# directory — this matters because the composite action (action.yml) sets
# working-directory to the caller's checkout, and $ACTION_PATH/sigilbadges.pl
# is invoked from there, not from inside the action's own repo. If logo
# lookup were ever accidentally written relative to cwd instead, every
# `logo=` badge would break the moment this runs as an action rather than
# from within a checkout of this repo itself.
my $SCRIPT = "$FindBin::RealBin/../sigilbadges.pl";

sub run_cli_from {
    my ($cwd, @args) = @_;
    my $cmd = join(' ', 'cd', quotemeta($cwd), '&&', 'perl', quotemeta($SCRIPT), map { quotemeta($_) } @args);
    my $out = `$cmd 2>&1`;
    my $status = $? >> 8;
    return ($status, $out);
}

sub write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} $content;
    close $fh;
}

my $home = tempdir(CLEANUP => 1);         # invocation cwd: has nothing to do with the repo
my $work = tempdir(CLEANUP => 1);         # where --file/--badges-dir actually live
my $readme = "$work/README.md";
write_file($readme, qq{<!--[[ badge: logo=docker message="ready" ]]-->\n<!--/-->\n});

my ($status, $out) = run_cli_from($home, '--file', $readme, '--badges-dir', "$work/badges");
is($status, 0, 'invoking from an unrelated cwd still exits 0');
ok(-f "$work/badges/docker.svg", "the docker logo still resolves via the script's own location, not cwd");

my $svg = do {
    open my $fh, '<', "$work/badges/docker.svg" or die $!;
    local $/;
    <$fh>;
};
like($svg, qr/<svg/, 'the badge SVG contains real logo markup, not an empty/failed icon lookup');

# Sanity check on the harness itself: prove the two tempdirs really are
# different from each other and from wherever this test file happens to
# run from, so the assertions above aren't accidentally passing only
# because $home and $work coincide.
isnt($home, $work, 'the invocation cwd and the working files genuinely differ');
isnt(getcwd(), $home, "the test process's own cwd is not the tempdir we cd into for the subprocess");
ok(-d $home, 'the unrelated cwd tempdir exists and was actually used as cwd for the subprocess');
