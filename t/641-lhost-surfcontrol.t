use strict;
use warnings;
use Test::More;
use lib qw(./lib ./blib/lib);
require './t/600-bite-email-code';

my $enginename = 'SurfControl';
my $enginetest = Sisimai::Bite::Email::Code->maketest;
my $isexpected = [
    { 'n' => '01', 's' => qr/\A5[.]0[.]\d+\z/, 'r' => qr/filtered/,    'b' => qr/\A1\z/ },
    { 'n' => '02', 's' => qr/\A5[.]0[.]\d+\z/, 'r' => qr/systemerror/, 'b' => qr/\A1\z/ },
    { 'n' => '03', 's' => qr/\A5[.]0[.]\d+\z/, 'r' => qr/systemerror/, 'b' => qr/\A1\z/ },
];

$enginetest->($enginename, $isexpected);
done_testing;

