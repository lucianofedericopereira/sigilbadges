use strict;
use warnings;
use Test::More tests => 15;
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

# --- header defaults, inherited and overridden per line -------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, <<'MD');
<!--[[ badge-row: style=chip
logo=react message="18.x"
logo=node message="20.x" style=flat
]]-->
<!--/-->
MD

    my ($status) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, 'a badge-row header with two lines exits 0');
    ok(-f "$dir/badges/react.svg", 'the first row line renders (inherits style=chip from the header)');
    ok(-f "$dir/badges/node.svg", 'the second row line renders (overrides style=flat)');

    my $react_svg = slurp("$dir/badges/react.svg");
    like($react_svg, qr/linearGradient/, 'react used the inherited chip style');
    my $node_svg = slurp("$dir/badges/node.svg");
    unlike($node_svg, qr/linearGradient/, "node's own style=flat overrides the header default");

    my $content = slurp($readme);
    like($content, qr{<p align="center">}, 'a badge-row renders its cards inside a centered <p>');
}

# --- comment and blank lines inside the row are skipped -------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, <<'MD');
<!--[[ badge-row:
logo=docker message="ready"

# a comment line, ignored
logo=postgres message="16"
]]-->
<!--/-->
MD
    my ($status) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, 'blank and #-comment lines inside a row are skipped, not errors');
    ok(-f "$dir/badges/docker.svg", 'docker line still renders');
    ok(-f "$dir/badges/postgres.svg", 'postgres line still renders');
}

# --- an empty row (no badge lines at all) is an error ----------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, qq{<!--[[ badge-row: style=chip ]]-->\n<!--/-->\n});
    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    isnt($status, 0, 'a badge-row with no badge lines is an error');
    like($out, qr/badge-row has no badge lines/, 'the error names the problem');
}

# --- duplicate ids within/across markers, with id= to disambiguate --------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, <<'MD');
<!--[[ badge-row:
logo=docker message="a"
logo=docker message="b"
]]-->
<!--/-->
MD
    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    isnt($status, 0, 'two row lines deriving the same id (both logo=docker) collide');
    like($out, qr/duplicate badge id/, 'the error names the problem and suggests id=');
}

# --- badge-row with no header line at all (bare 'badge-row') --------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, <<'MD');
<!--[[ badge-row
logo=vue message="3.x"
]]-->
<!--/-->
MD
    my ($status) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, "a bare 'badge-row' header (no ': key=value' defaults) is valid");
    ok(-f "$dir/badges/vue.svg", 'its one line still renders');
}
