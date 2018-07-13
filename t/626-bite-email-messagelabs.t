use strict;
use warnings;
use Test::More;
use lib qw(./lib ./blib/lib);
require './t/600-bite-email-code';

my $enginename = 'MessageLabs';
my $enginetest = Sisimai::Bite::Email::Code->maketest;
my $isexpected = [
    { 'n' => '01', 's' => qr/\A5[.]0[.]0\z/, 'r' => qr/securityerror/, 'b' => qr/\A1\z/ },
    { 'n' => '02', 's' => qr/\A5[.]0[.]0\z/, 'r' => qr/userunknown/, 'b' => qr/\A0\z/ },
];

$enginetest->($enginename, $isexpected);
done_testing;

