#!/usr/bin/env perl
use strict;
use warnings;
use Stow;
use JSON::PP;

my $input;
{ local $/; $input = <STDIN>; }
my $request = decode_json($input);
$ENV{HOME} = $request->{home};
my $stow = Stow->new(dir => $request->{repo}, target => $request->{home},
                    ignore => [$request->{pattern}], 'no-folding' => 1);
my @ignored;
for my $item (@{$request->{paths}}) {
    push @ignored, $item if $stow->ignore($request->{repo}, $item->[0], $item->[1]);
}
print encode_json(\@ignored);
