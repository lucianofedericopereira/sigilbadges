use strict;
use warnings;
use Test::More tests => 24;
use File::Temp qw(tempdir);
use FindBin ();

my $SCRIPT = "$FindBin::RealBin/../sigilbadges.pl";

# Every run below points --file/--badges-dir at absolute paths inside a
# fresh tempdir, so nothing here ever touches this repo's own README.md or
# assets/badges/ — sigilbadges.pl has no --base option (unlike its sibling
# treegen2), it just opens whatever --file/--badges-dir it's given relative
# to the subprocess's cwd, so an absolute path is what keeps this isolated
# regardless of where `prove` itself is invoked from.
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

# --- a single badge: logo + label + message, default brand color -------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, qq{# Demo\n\n<!--[[ badge: logo=php label="PHP" message="8.5" ]]-->x<!--/-->\n});

    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, 'a single badge marker exits 0');
    ok(-f "$dir/badges/php.svg", 'badge id defaults to the logo name, and the SVG is written');

    my $svg = slurp("$dir/badges/php.svg");
    like($svg, qr/PHP 8\.5|PHP/, 'the rendered SVG contains the label text');
    like($svg, qr/#777BB4/i, "php's default brand color is used when color= is omitted");

    my $content = slurp($readme);
    like($content, qr{<img src="\Q$dir\E/badges/php\.svg" alt="PHP 8\.5">}, 'the marker body is replaced with an <img> using label+message as alt text');
}

# --- explicit id=, color=, style=, and link= -----------------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, qq{<!--[[ badge: id=my-badge message="v1.0" color=336791 style=flat link="https://example.com" ]]-->\n});

    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, 'explicit id/color/style/link all parse');
    ok(-f "$dir/badges/my-badge.svg", 'id= overrides the derived filename stem');

    my $svg = slurp("$dir/badges/my-badge.svg");
    like($svg, qr/#336791/i, 'explicit color= is honored');
    unlike($svg, qr/linearGradient/, "style=flat doesn't use the chip style's gradient");

    my $content = slurp($readme);
    like($content, qr{<a href="https://example\.com"><img[^>]*></a>}, 'link= wraps the <img> in an <a href>');
}

# --- alt= override -------------------------------------------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, qq{<!--[[ badge: logo=node message="20.x" alt="Node twenty" ]]-->\n});
    my ($status) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, 'logo + message with an explicit alt= exits 0');
    my $content = slurp($readme);
    like($content, qr/alt="Node twenty"/, 'alt= overrides the derived alt text');
}

# --- inline vs block placement -------------------------------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, "See status: <!--[[ badge: id=s message=\"ok\" ]]-->x<!--/--> right here.\n");
    my ($status) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, 'an inline marker (non-whitespace before it on the line) exits 0');
    my $content = slurp($readme);
    # The opening marker tag itself is never rewritten (only the body
    # between the markers is) — so "inline" means no newline gets inserted
    # around the *replacement*, not that the tag disappears.
    like($content, qr/\]\]--><img[^>]*><!--\/--> right here\./, 'an inline marker is replaced in place, with no newline inserted around it');
}

# --- idempotent re-run: unchanged SVG bytes are not rewritten ------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, qq{<!--[[ badge: logo=react message="18.x" ]]-->\n});
    my ($status1, $out1) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status1, 0, 'first run exits 0');
    like($out1, qr/wrote/, 'first run reports it wrote something');

    my ($status2, $out2) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status2, 0, 'second run on an already-rendered file exits 0');
    like($out2, qr/everything already up to date/, 'second run is a true no-op: nothing left to write');
}

# --- missing file -----------------------------------------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my ($status, $out) = run_cli('--file', "$dir/nope.md");
    isnt($status, 0, 'a missing --file is an error');
    like($out, qr/file not found/, 'the error names the problem');
}

# --- bad CLI arguments --------------------------------------------------------
{
    my ($status, $out) = run_cli('--not-a-real-flag');
    isnt($status, 0, 'an unrecognized flag is rejected');
    like($out, qr/bad arguments/, 'the error names the problem');
}

# --- unclosed marker: still renders, self-closes -------------------------------
{
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, qq{<!--[[ badge: id=open message="hi" ]]-->\n});
    my ($status) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    is($status, 0, 'a marker with no matching <!--/--> close comment still renders');
    my $content = slurp($readme);
    like($content, qr/<!--\/-->/, 'a synthetic close comment is appended');
}
