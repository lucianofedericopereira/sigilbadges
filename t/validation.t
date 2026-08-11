use strict;
use warnings;
use Test::More tests => 27;
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

# One tempdir/badges-dir shared by every case below: each case is its own
# marker in its own file, so nothing here depends on ordering or on a
# previous case's output.
sub check {
    my ($label, $marker, $expect_ok, $err_re) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $readme = "$dir/README.md";
    write_file($readme, "$marker\n");
    my ($status, $out) = run_cli('--file', $readme, '--badges-dir', "$dir/badges");
    if ($expect_ok) {
        is($status, 0, "$label: exits 0");
    } else {
        isnt($status, 0, "$label: exits non-zero");
    }
    like($out, $err_re, "$label: error message matches") if $err_re;
}

check('unknown key', '<!--[[ badge: bogus=1 ]]-->', 0, qr/unknown key 'bogus'/);
check('duplicate key', '<!--[[ badge: message="a" message="b" ]]-->', 0, qr/duplicate key 'message'/);
check('unparseable trailing garbage', '<!--[[ badge: message="a" !!! ]]-->', 0, qr/could not parse/);
check('unknown logo', '<!--[[ badge: logo=cobol ]]-->', 0, qr/unknown logo 'cobol'/);
check('unknown style', '<!--[[ badge: message="x" style=bogus ]]-->', 0, qr/unknown style 'bogus'/);
check('invalid color (not hex)', '<!--[[ badge: message="x" color=blue ]]-->', 0, qr/invalid color 'blue'/);
check('invalid color (short hex)', '<!--[[ badge: message="x" color=fff ]]-->', 0, qr/invalid color 'fff'/);
check('invalid label-color', '<!--[[ badge: message="x" label-color=zzzzzz ]]-->', 0, qr/invalid label-color/);
check('invalid logo-color', '<!--[[ badge: message="x" logo-color=zzzzzz ]]-->', 0, qr/invalid logo-color/);
check('invalid id', '<!--[[ badge: message="x" id="not valid!" ]]-->', 0, qr/invalid id/);
check('empty chip: no logo/label/message', '<!--[[ badge: id=empty-chip color=336791 ]]-->', 0, qr/no logo, label, or message/);
check('cannot derive a filename with nothing at all', '<!--[[ badge: color=336791 ]]-->', 0, qr/cannot derive a filename/);
check('unrecognized marker type', '<!--[[ bogus-thing: x=1 ]]-->', 0, qr/unrecognized marker/);
check('valid color is accepted case-insensitively', '<!--[[ badge: message="x" color=AbCdEf ]]-->', 1, undef);
