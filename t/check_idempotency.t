use strict;
use warnings;
use Test::More tests => 12;
use File::Temp qw(tempdir);
use FindBin ();

my $SCRIPT = "$FindBin::RealBin/../sigilbadges.pl";

sub run_cli {
    my (@args) = @_;
    my $cmd = join(' ', 'perl', quotemeta($SCRIPT), map { quotemeta($_) } @args);
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

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "$path: $!";
    local $/;
    return <$fh>;
}

# The full --check lifecycle a CI job actually relies on: a fresh file is
# "out of date" (README not yet spliced, badge not yet on disk); --check
# must refuse to touch either while reporting that; a real run then writes
# both; and immediately after, --check must exit 0 and, critically, leave
# every byte untouched — the exact property the composite action's
# dogfooding job (.github/workflows/ci.yml's docs-fresh job) depends on.
my $dir = tempdir(CLEANUP => 1);
my $readme = "$dir/README.md";
my $badges_dir = "$dir/badges";
write_file($readme, qq{<!--[[ badge: logo=python message="3.12" ]]-->\n<!--/-->\n});
my $original = slurp($readme);

{
    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', $badges_dir, '--check');
    isnt($status, 0, '--check on a not-yet-rendered file exits non-zero');
    like($out, qr/out of date/, 'the error says it is out of date');
    like($out, qr/\Q$readme\E needs updating/, 'the error names the README as needing an update');
    ok(!-f "$badges_dir/python.svg", '--check never writes the badge SVG');
    is(slurp($readme), $original, '--check never writes the README');
}

{
    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', $badges_dir);
    is($status, 0, 'a real (non---check) run exits 0');
    ok(-f "$badges_dir/python.svg", 'the real run writes the badge SVG');
    isnt(slurp($readme), $original, 'the real run rewrites the README');
}

my $rendered = slurp($readme);
my $svg_bytes = slurp("$badges_dir/python.svg");

{
    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', $badges_dir, '--check');
    is($status, 0, '--check on a freshly-rendered file exits 0');
    like($out, qr/up to date/, 'the message says it is up to date');
    is(slurp($readme), $rendered, '--check leaves the README byte-for-byte unchanged');
    is(slurp("$badges_dir/python.svg"), $svg_bytes, '--check leaves the badge SVG byte-for-byte unchanged');
}
