#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_dir}"

perl -MEncode=decode,FB_CROAK <<'PL'
use strict;
use warnings;
use utf8;

my $emoji_pattern = qr/
    \p{Extended_Pictographic}
    | \p{Regional_Indicator}
    | [\x{1F3FB}-\x{1F3FF}]
    | [\x{200D}\x{20E3}\x{FE0F}]
/x;

open my $files, '-|', 'git', 'ls-files', '-z'
    or die "Could not enumerate tracked files: $!\n";
local $/ = "\0";
my @violations;

while (my $path = <$files>) {
    $path =~ s/\0\z//;
    next if $path eq '';

    my $bytes;
    if (-l $path) {
        $bytes = readlink $path;
        next if !defined $bytes;
    } else {
        open my $input, '<:raw', $path or next;
        local $/;
        $bytes = <$input>;
        close $input;
    }
    next if !defined $bytes || $bytes =~ /\0/;

    my $text;
    eval { $text = decode('UTF-8', $bytes, FB_CROAK); 1 } or next;
    my @lines = split /\R/, $text, -1;
    for my $index (0 .. $#lines) {
        my @matches = $lines[$index] =~ /($emoji_pattern)/g;
        next if !@matches;
        my $codepoints = join ', ', map { sprintf 'U+%04X', ord $_ } @matches;
        push @violations, "$path:" . ($index + 1) . ": $codepoints: $lines[$index]";
    }
}
close $files;

if (@violations) {
    print STDERR "Emoji characters found in tracked text files:\n";
    print STDERR join("\n", @violations), "\n";
    exit 1;
}

print "No emoji characters found in tracked text files.\n";
PL
