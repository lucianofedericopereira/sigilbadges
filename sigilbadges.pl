#!/usr/bin/env perl

# sigilbadges -- generated SVG badges (logo + text) inserted into README.md
# via marker comments, in the same spirit as sigilmd and pdf-preview: no
# template language, no CPAN dependencies, one Perl script. Unlike
# pdf-preview, badge generation needs no external binary at all -- SVG is
# just text, so this is pure core Perl end to end.
#
# Grammar:
#   <!--[[ badge: logo=php label="PHP" message="8.5" ]]-->...<!--/-->
#     a single badge
#   <!--[[ badge-row: style=chip
#   logo=php label="PHP" message="8.5"
#   logo=node message="20.x"
#   ]]-->...<!--/-->
#     a responsive row of badges, one spec per line, all inside the tag
#     itself (the 'badge-row: key=value ...' header is optional and sets
#     defaults every line inherits/overrides). Per-badge specs live in the
#     tag rather than the body -- same idiom as 'badge:' and pdf-preview's
#     'pdf-gallery:' -- so the row survives being re-run: the body between
#     the markers is pure rendered output, fully regenerated every time.
#
# See README.md in this repo for the full spec.

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use FindBin qw($Bin);

my $file       = 'README.md';
my $badges_dir = 'assets/badges';
my $check      = 0;

GetOptions(
    'file=s'       => \$file,
    'badges-dir=s' => \$badges_dir,
    'check'        => \$check,
) or die "sigilbadges: bad arguments\n";

die "sigilbadges: file not found: $file\n" unless -e $file;

my $LOGO_DIR = "$Bin/assets/logos";
my $FONT     = q{-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif};

my %BRAND_COLOR = (
    docker     => '2496ED',
    node       => '5FA04E',
    php        => '777BB4',
    github     => '24292F',
    git        => 'F05032',
    html       => 'E34F26',
    laravel    => 'FF2D20',
    linux      => '3A3A3A',
    mongodb    => '47A248',
    mysql      => '4479A1',
    postgres   => '336791',
    python     => '3776AB',
    react      => '20232A',
    tailwind   => '06B6D4',
    team       => '7C3AED',
    typescript => '3178C6',
    vue        => '42B883',
    agile      => '0052CC',
    ai         => 'EC4899',
    api        => '6366F1',
    npm        => 'CB3837',
);

my %VALID_STYLE = map { $_ => 1 } qw(chip flat flat-square plastic for-the-badge);
my %VALID_KEY   = map { $_ => 1 } qw(logo label message color label-color logo-color style id link alt);

my $original = slurp_text($file);
my $content  = $original;

# ---------------------------------------------------------------------------
# Locate every <!--[[ ... ]]--> opening marker, in order, with byte offsets.
# (Same scan/pair/inline-detection technique as sigilmd and pdf-preview.)
# ---------------------------------------------------------------------------

my @markers;
while ($content =~ /<!--\[\[\s*(.*?)\s*\]\]-->/gs) {
    push @markers, {
        raw        => $1,
        open_start => $-[0],
        open_end   => $+[0],
    };
}

for my $i (0 .. $#markers) {
    my $m          = $markers[$i];
    my $window_end = ($i < $#markers) ? $markers[$i + 1]{open_start} : length($content);
    my $window     = substr($content, $m->{open_end}, $window_end - $m->{open_end});

    if ($window =~ /<!--\/-->/) {
        $m->{body_end}  = $m->{open_end} + $-[0];
        $m->{close_end} = $m->{open_end} + $+[0];
        $m->{body}      = substr($content, $m->{open_end}, $m->{body_end} - $m->{open_end});
        $m->{has_close} = 1;
    }
    else {
        $m->{has_close} = 0;
        $m->{body}      = '';
    }

    my $prev_nl     = rindex($content, "\n", $m->{open_start} - 1);
    my $line_prefix = substr($content, $prev_nl + 1, $m->{open_start} - $prev_nl - 1);
    $m->{inline}    = ($line_prefix =~ /\S/) ? 1 : 0;
}

# ---------------------------------------------------------------------------
# Pass 1: classify every marker, validate it, and collect the set of badges
# that need generating (id => spec).
# ---------------------------------------------------------------------------

my %badges;    # id => spec hashref
my @all_ids;   # in declaration order, for duplicate detection with context

for my $m (@markers) {
    my $raw = $m->{raw};

    if ($raw =~ /^badge:\s*(.+)$/) {
        my %kv = parse_kv($1, "'<!--[[ $raw ]]-->'");
        my $spec = build_spec(\%kv, "'<!--[[ $raw ]]-->'");
        my $id = register_badge($spec, "'<!--[[ $raw ]]-->'");
        $m->{type} = 'badge';
        $m->{id}   = $id;
    }
    elsif ((split /\n/, $raw, 2)[0] =~ /^badge-row$/ || (split /\n/, $raw, 2)[0] =~ /^badge-row:\s*(.*)$/) {
        # Per-badge specs live in the marker's own tag (one per line, after
        # the 'badge-row' header line) -- never in the disposable body --
        # so the row survives being re-run, same as 'badge:' and pdf-preview's
        # 'pdf-gallery:'. The body between the markers is pure rendered
        # output and gets fully regenerated every time.
        my ($header, @lines) = split /\n/, $raw;
        my ($header_args) = $header =~ /^badge-row:\s*(.*)$/;
        my %defaults = defined $header_args ? parse_kv($header_args, "'<!--[[ $header ]]-->' header") : ();
        my @ids;
        my $line_no = 0;
        for my $line (@lines) {
            $line_no++;
            next if $line =~ /^\s*$/;
            next if $line =~ /^\s*#/;
            my $ctx = "badge-row line $line_no";
            my %kv = (%defaults, parse_kv($line, $ctx));
            my $spec = build_spec(\%kv, $ctx);
            push @ids, register_badge($spec, $ctx);
        }
        die "sigilbadges: badge-row has no badge lines (in '<!--[[ $raw ]]-->')\n"
            unless @ids;
        $m->{type} = 'badge-row';
        $m->{ids}  = \@ids;
    }
    elsif ($raw =~ /^\@?\$[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*/) {
        # sigilmd's own reference syntax (<!--[[ $table.key ]]--> / <!--[[
        # @table.key ]]-->) shares this exact <!--[[ ]]--> bracket
        # convention with no namespace to tell tools apart. Left untouched
        # -- unambiguous since sigilbadges has no marker starting with '$'
        # or '@', so skipping it can't mask a real sigilbadges typo. Its
        # table-*declare* markers (a bare identifier, e.g. "config") are
        # NOT whitelisted here -- that shape is indistinguishable from a
        # mistyped 'badge:' marker, so it still hard-errors on purpose.
        $m->{type} = 'foreign';
    }
    else {
        die "sigilbadges: unrecognized marker '<!--[[ $raw ]]-->' -- expected 'badge: <key=value ...>' or 'badge-row'\n";
    }
}

# ---------------------------------------------------------------------------
# Render every distinct badge exactly once, write to disk unless --check.
# ---------------------------------------------------------------------------

my %svg_changed; # path => 1 if bytes differ from what's on disk

for my $id (sort keys %badges) {
    my $spec = $badges{$id};
    my $path = "$badges_dir/$id.svg";
    my $svg  = render_badge($spec);

    my $existing = -f $path ? slurp_text($path) : undef;
    my $changed  = (!defined $existing) || ($existing ne $svg);
    $svg_changed{$path} = $changed;
    $spec->{path} = $path;
    $spec->{svg}  = $svg;

    if ($changed && !$check) {
        make_path(dirname($path));
        write_text($path, $svg);
    }
}

# ---------------------------------------------------------------------------
# Pass 2: splice generated markdown into the file, back-to-front.
# ---------------------------------------------------------------------------

for my $m (reverse @markers) {
    next if $m->{type} eq 'foreign';

    my $generated;

    if ($m->{type} eq 'badge') {
        $generated = render_link($badges{ $m->{id} });
    }
    else {
        my @cards = map { render_link($badges{$_}) } @{ $m->{ids} };
        $generated = "<p align=\"center\">\n" . join("\n", @cards) . "\n</p>";
    }

    my $replacement = $m->{inline} ? $generated : "\n$generated\n";
    $replacement .= '<!--/-->' unless $m->{has_close};

    my $splice_start = $m->{open_end};
    my $splice_end   = $m->{has_close} ? $m->{body_end} : $m->{open_end};
    substr($content, $splice_start, $splice_end - $splice_start) = $replacement;
}

# ---------------------------------------------------------------------------
# Write or check.
# ---------------------------------------------------------------------------

my $any_svg_changed = grep { $_ } values %svg_changed;
my $readme_changed   = ($content ne $original);

if ($check) {
    if ($readme_changed || $any_svg_changed) {
        print "sigilbadges: out of date -- run without --check to regenerate\n";
        print "  - $file needs updating\n" if $readme_changed;
        for my $p (sort keys %svg_changed) {
            print "  - $p needs updating\n" if $svg_changed{$p};
        }
        exit 1;
    }
    print "sigilbadges: $file and all badges are up to date\n";
    exit 0;
}

if ($readme_changed) {
    write_text($file, $content);
    print "sigilbadges: wrote $file\n";
}
my $written = grep { $_ } values %svg_changed;
print "sigilbadges: wrote $written badge SVG(s)\n" if $written;
print "sigilbadges: everything already up to date\n" unless $readme_changed || $written;

exit 0;

# ---------------------------------------------------------------------------
# Marker-level helpers.
# ---------------------------------------------------------------------------

# Tokenizes 'key=value key="quoted value" ...' into a hash. Hard-errors on
# anything that doesn't parse cleanly -- no silent partial matches.
sub parse_kv {
    my ($str, $context) = @_;
    my %kv;
    while ($str =~ /\G\s*([A-Za-z][A-Za-z0-9_-]*)=(?:"([^"]*)"|(\S*))/gc) {
        my ($key, $qval, $bval) = ($1, $2, $3);
        die "sigilbadges: unknown key '$key' in $context\n" unless $VALID_KEY{$key};
        die "sigilbadges: duplicate key '$key' in $context\n" if exists $kv{$key};
        $kv{$key} = defined $qval ? $qval : $bval;
    }
    my $rest = substr($str, pos($str) // 0);
    die "sigilbadges: could not parse '$rest' in $context -- expected key=value or key=\"quoted value\"\n"
        if $rest =~ /\S/;
    return %kv;
}

sub build_spec {
    my ($kv, $context) = @_;

    if (defined $kv->{logo}) {
        die "sigilbadges: unknown logo '$kv->{logo}' in $context -- see assets/logos/ for available names\n"
            unless -f "$LOGO_DIR/$kv->{logo}.svg";
    }

    my $style = $kv->{style} // 'chip';
    die "sigilbadges: unknown style '$style' in $context -- expected one of: " . join(', ', sort keys %VALID_STYLE) . "\n"
        unless $VALID_STYLE{$style};

    my $color = $kv->{color} // ($kv->{logo} ? $BRAND_COLOR{ $kv->{logo} } : '555555');
    die "sigilbadges: invalid color '$kv->{color}' in $context -- expected a bare hex value, e.g. color=336791\n"
        if defined $kv->{color} && $kv->{color} !~ /^[0-9A-Fa-f]{6}$/;
    die "sigilbadges: invalid label-color '$kv->{'label-color'}' in $context -- expected a bare hex value\n"
        if defined $kv->{'label-color'} && $kv->{'label-color'} !~ /^[0-9A-Fa-f]{6}$/;
    die "sigilbadges: invalid logo-color '$kv->{'logo-color'}' in $context -- expected a bare hex value\n"
        if defined $kv->{'logo-color'} && $kv->{'logo-color'} !~ /^[0-9A-Fa-f]{6}$/;

    if (defined $kv->{id}) {
        die "sigilbadges: invalid id '$kv->{id}' in $context -- expected [A-Za-z0-9_-]+\n"
            unless $kv->{id} =~ /^[A-Za-z0-9_-]+$/;
    }

    return {
        logo        => $kv->{logo},
        label       => $kv->{label},
        message     => $kv->{message},
        color       => uc($color),
        label_color => uc($kv->{'label-color'} // '555555'),
        logo_color  => uc($kv->{'logo-color'} // 'FFFFFF'),
        style       => $style,
        id          => $kv->{id},
        link        => $kv->{link},
        alt         => $kv->{alt},
    };
}

sub register_badge {
    my ($spec, $context) = @_;

    my $id = $spec->{id};
    if (!defined $id) {
        $id = $spec->{logo} // slugify($spec->{label}) // slugify($spec->{message});
        die "sigilbadges: cannot derive a filename for $context -- set logo=, label=, message=, or id=\n"
            unless defined $id;
    }
    die "sigilbadges: duplicate badge id '$id' ($context) -- set id= to disambiguate\n"
        if exists $badges{$id};

    $badges{$id} = $spec;
    return $id;
}

sub slugify {
    my ($s) = @_;
    return undef unless defined $s && length $s;
    $s = lc $s;
    $s =~ s/[^a-z0-9]+/-/g;
    $s =~ s/^-+|-+$//g;
    return length $s ? $s : undef;
}

# ---------------------------------------------------------------------------
# Rendering.
# ---------------------------------------------------------------------------

sub render_link {
    my ($spec) = @_;
    my $alt = $spec->{alt};
    if (!defined $alt) {
        my $text = join(' ', grep { defined && length } ($spec->{label}, $spec->{message}));
        $alt = length($text) ? $text : $spec->{logo};
    }
    $alt = $spec->{id} unless defined $alt && length $alt;
    my $img = qq{<img src="} . xml_escape($spec->{path}) . qq{" alt="} . xml_escape($alt) . qq{">};
    return defined $spec->{link}
        ? qq{<a href="} . xml_escape($spec->{link}) . qq{">$img</a>}
        : $img;
}

sub render_badge {
    my ($spec) = @_;
    return $spec->{style} eq 'chip' ? render_chip($spec) : render_split($spec);
}

sub render_chip {
    my ($spec) = @_;
    my $pad       = 8;
    my $icon_box  = 18;
    my $height    = 28;
    my $font_size = 12;
    my $has_logo  = defined $spec->{logo};

    my $text = join(' ', grep { defined && length } ($spec->{label}, $spec->{message}));
    die "sigilbadges: badge has no logo, label, or message to render\n" if !$has_logo && !length($text);

    my $text_x = $pad + ($has_logo ? $icon_box + 6 : 0);
    my $text_w = length($text) ? text_width($text, $font_size, 600) : 0;
    my $width  = $has_logo && !length($text)
        ? $pad * 2 + $icon_box
        : $text_x + $text_w + $pad;

    my $color2 = darken($spec->{color});

    my @svg;
    push @svg, qq{<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">};
    push @svg, qq{  <defs><linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0%" stop-color="#$spec->{color}"/><stop offset="100%" stop-color="#$color2"/></linearGradient></defs>};
    push @svg, qq{  <rect width="$width" height="$height" rx="6" fill="url(#bg)"/>};
    push @svg, icon_markup($spec->{logo}, $pad, ($height - $icon_box) / 2, $icon_box, $spec->{logo_color}) if $has_logo;
    if (length $text) {
        my $ty = $height / 2 + $font_size * 0.35;
        push @svg, qq{  <text x="$text_x" y="$ty" fill="#fff" font-family="$FONT" font-size="$font_size" font-weight="600">} . xml_escape($text) . qq{</text>};
    }
    push @svg, qq{</svg>};
    return join("\n", @svg) . "\n";
}

sub render_split {
    my ($spec) = @_;
    my $style = $spec->{style};
    my $ftb   = ($style eq 'for-the-badge');

    my $label   = $spec->{label};
    my $message = $spec->{message};
    die "sigilbadges: style '$style' needs logo=, label=, or message= (nothing to show)\n"
        unless defined($spec->{logo}) || (defined $label && length $label) || (defined $message && length $message);

    if ($ftb) {
        $label   = uc($label)   if defined $label;
        $message = uc($message) if defined $message;
    }

    my $height    = $ftb ? 28 : ($style eq 'plastic' ? 20 : 20);
    my $font_size = $ftb ? 11 : 11;
    my $weight    = $ftb ? 700 : 600;
    my $rx        = $style eq 'flat' ? 3 : $style eq 'plastic' ? 4 : 0;
    my $pad       = $ftb ? 10 : 8;
    my $icon_box  = $ftb ? 14 : 14;
    my $has_logo  = defined $spec->{logo};

    my $has_label   = defined $label && length $label;
    my $has_message = defined $message && length $message;

    # Two-tone (label | message) only when BOTH are given, matching
    # shields.io's own convention. With just one of the two, this collapses
    # to a single colored segment using $color (which already carries the
    # brand-color default) rather than the generic $label_color gray --
    # otherwise a logo-only or label-only badge would render as a flat gray
    # chip regardless of its brand color.
    my $two_tone = $has_label && $has_message;

    my $left_w = 0;
    my $right_w = 0;

    if ($two_tone) {
        my $left_text_x = $pad + ($has_logo ? $icon_box + 6 : 0);
        $left_w  = $left_text_x + text_width($label, $font_size, $weight) + $pad;
        $right_w = $pad * 2 + text_width($message, $font_size, $weight);
    }
    else {
        my $text = $has_label ? $label : $has_message ? $message : undef;
        my $text_x = $pad + ($has_logo ? $icon_box + 6 : 0);
        $right_w = defined $text ? $text_x + text_width($text, $font_size, $weight) + $pad
                 : $has_logo     ? $pad * 2 + $icon_box
                 :                 die "sigilbadges: style '$style' needs logo=, label=, or message=\n";
    }
    my $width = $left_w + $right_w;

    my @svg;
    push @svg, qq{<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">};
    if ($rx > 0) {
        push @svg, qq{  <clipPath id="clip"><rect width="$width" height="$height" rx="$rx"/></clipPath>};
        push @svg, qq{  <g clip-path="url(#clip)">};
    }
    else {
        push @svg, qq{  <g>};
    }
    push @svg, qq{    <rect width="$left_w" height="$height" fill="#$spec->{label_color}"/>} if $left_w > 0;
    push @svg, qq{    <rect x="$left_w" width="$right_w" height="$height" fill="#$spec->{color}"/>} if $right_w > 0;
    if ($style eq 'plastic') {
        my $half = $height / 2;
        push @svg, qq{    <rect width="$width" height="$half" fill="#fff" opacity="0.12"/>};
    }
    push @svg, qq{  </g>};

    push @svg, icon_markup($spec->{logo}, $pad, ($height - $icon_box) / 2, $icon_box, $spec->{logo_color}) if $has_logo;

    my $ty         = $height / 2 + $font_size * 0.35;
    my $icon_shift = $has_logo ? ($icon_box + 6) / 2 : 0;

    if ($two_tone) {
        push @svg, qq{  <text x="} . ($left_w / 2 + $icon_shift) . qq{" y="$ty" fill="#fff" font-family="$FONT" font-size="$font_size" font-weight="$weight" text-anchor="middle">} . xml_escape($label) . qq{</text>};
        push @svg, qq{  <text x="} . ($left_w + $right_w / 2) . qq{" y="$ty" fill="#fff" font-family="$FONT" font-size="$font_size" font-weight="$weight" text-anchor="middle">} . xml_escape($message) . qq{</text>};
    }
    elsif ($has_label || $has_message) {
        my $text = $has_label ? $label : $message;
        push @svg, qq{  <text x="} . ($right_w / 2 + $icon_shift) . qq{" y="$ty" fill="#fff" font-family="$FONT" font-size="$font_size" font-weight="$weight" text-anchor="middle">} . xml_escape($text) . qq{</text>};
    }
    push @svg, qq{</svg>};
    return join("\n", @svg) . "\n";
}

sub icon_markup {
    my ($name, $x, $y, $box, $color) = @_;
    my $svg = slurp_text("$LOGO_DIR/$name.svg");
    my ($viewbox) = $svg =~ /viewBox="([^"]*)"/;
    my ($inner)   = $svg =~ m{<svg[^>]*>(.*)</svg>}s;
    $inner = recolor_logo($inner, $color);
    return qq{  <svg x="$x" y="$y" width="$box" height="$box" viewBox="$viewbox">$inner</svg>};
}

sub recolor_logo {
    my ($inner, $color) = @_;
    return $inner if uc($color) eq 'FFFFFF';
    (my $out = $inner) =~ s/#fff\b/#$color/gi;
    $out =~ s/#ffffff\b/#$color/gi;
    return $out;
}

# ---------------------------------------------------------------------------
# Text width heuristic. No font-metrics library is available without adding
# a dependency, so this approximates proportional-sans widths with a small
# per-character table (narrow/wide overrides) and bucket fallbacks. Good
# enough to size a badge; not pixel-exact kerning.
# ---------------------------------------------------------------------------

my %CHAR_W = (
    ' ' => 0.28, '.' => 0.22, ',' => 0.22, ':' => 0.24, ';' => 0.24,
    "'" => 0.20, '!' => 0.24, '|' => 0.20, 'i' => 0.24, 'l' => 0.22,
    'I' => 0.26, 'j' => 0.24, 'f' => 0.34, 't' => 0.34, 'r' => 0.38,
    '(' => 0.32, ')' => 0.32, '[' => 0.30, ']' => 0.30, '-' => 0.32,
    '_' => 0.55, '/' => 0.32,
    'M' => 0.85, 'W' => 0.88, 'm' => 0.82, 'w' => 0.74,
    '@' => 0.90, '%' => 0.82, 'G' => 0.74, 'O' => 0.76, 'Q' => 0.76, 'D' => 0.74,
);

sub char_width {
    my ($c) = @_;
    return $CHAR_W{$c} if exists $CHAR_W{$c};
    return 0.62 if $c =~ /[0-9]/;
    return 0.68 if $c =~ /[A-Z]/;
    return 0.56;
}

sub text_width {
    my ($str, $font_size, $weight) = @_;
    my $w = 0;
    $w += char_width($_) for split //, $str;
    $w *= 1.04 if ($weight // 400) >= 700; # bold runs slightly wider
    return $w * $font_size;
}

sub darken {
    my ($hex, $factor) = @_;
    $factor //= 0.78;
    my ($r, $g, $b) = map { hex($_) } unpack('A2A2A2', $hex);
    $_ = int($_ * $factor) for ($r, $g, $b);
    return sprintf('%02X%02X%02X', $r, $g, $b);
}

sub xml_escape {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

# ---------------------------------------------------------------------------
# File I/O.
# ---------------------------------------------------------------------------

sub slurp_text {
    my ($path) = @_;
    open my $fh, '<', $path or die "sigilbadges: cannot read $path: $!\n";
    local $/;
    my $data = <$fh>;
    close $fh;
    return defined $data ? $data : '';
}

sub write_text {
    my ($path, $data) = @_;
    open my $fh, '>', $path or die "sigilbadges: cannot write $path: $!\n";
    print {$fh} $data;
    close $fh;
    return;
}
