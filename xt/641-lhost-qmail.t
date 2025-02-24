use strict;
use warnings;
use Test::More;
use lib qw(./lib ./blib/lib);
require './t/600-lhost-code';

my $enginename = 'qmail';
my $samplepath = sprintf("./set-of-emails/private/email-%s", lc $enginename);
my $enginetest = Sisimai::Lhost::Code->maketest;
my $isexpected = [
    { 'n' => '01001', 'r' => qr/filtered/       },
    { 'n' => '01002', 'r' => qr/undefined/      },
    { 'n' => '01003', 'r' => qr/hostunknown/    },
    { 'n' => '01004', 'r' => qr/userunknown/    },
    { 'n' => '01005', 'r' => qr/hostunknown/    },
    { 'n' => '01006', 'r' => qr/userunknown/    },
    { 'n' => '01007', 'r' => qr/hostunknown/    },
    { 'n' => '01008', 'r' => qr/userunknown/    },
    { 'n' => '01009', 'r' => qr/userunknown/    },
    { 'n' => '01010', 'r' => qr/hostunknown/    },
    { 'n' => '01011', 'r' => qr/hostunknown/    },
    { 'n' => '01012', 'r' => qr/userunknown/    },
    { 'n' => '01013', 'r' => qr/userunknown/    },
    { 'n' => '01014', 'r' => qr/rejected/       },
    { 'n' => '01015', 'r' => qr/rejected/       },
    { 'n' => '01016', 'r' => qr/hostunknown/    },
    { 'n' => '01017', 'r' => qr/userunknown/    },
    { 'n' => '01018', 'r' => qr/userunknown/    },
    { 'n' => '01019', 'r' => qr/mailboxfull/    },
    { 'n' => '01020', 'r' => qr/filtered/       },
    { 'n' => '01021', 'r' => qr/userunknown/    },
    { 'n' => '01022', 'r' => qr/userunknown/    },
    { 'n' => '01023', 'r' => qr/userunknown/    },
    { 'n' => '01024', 'r' => qr/userunknown/    },
    { 'n' => '01025', 'r' => qr/(?:userunknown|filtered)/ },
    { 'n' => '01026', 'r' => qr/mesgtoobig/     },
    { 'n' => '01027', 'r' => qr/mailboxfull/    },
    { 'n' => '01028', 'r' => qr/userunknown/    },
    { 'n' => '01029', 'r' => qr/filtered/       },
    { 'n' => '01030', 'r' => qr/userunknown/    },
    { 'n' => '01031', 'r' => qr/userunknown/    },
    { 'n' => '01032', 'r' => qr/networkerror/   },
    { 'n' => '01033', 'r' => qr/mailboxfull/    },
    { 'n' => '01034', 'r' => qr/mailboxfull/    },
    { 'n' => '01035', 'r' => qr/mailboxfull/    },
    { 'n' => '01036', 'r' => qr/userunknown/    },
    { 'n' => '01037', 'r' => qr/hostunknown/    },
    { 'n' => '01038', 'r' => qr/filtered/       },
    { 'n' => '01039', 'r' => qr/mailboxfull/    },
    { 'n' => '01040', 'r' => qr/mailboxfull/    },
    { 'n' => '01041', 'r' => qr/userunknown/    },
    { 'n' => '01042', 'r' => qr/(?:userunknown|filtered)/ },
    { 'n' => '01043', 'r' => qr/rejected/       },
    { 'n' => '01044', 'r' => qr/blocked/        },
    { 'n' => '01045', 'r' => qr/systemerror/    },
    { 'n' => '01046', 'r' => qr/mailboxfull/    },
    { 'n' => '01047', 'r' => qr/userunknown/    },
    { 'n' => '01048', 'r' => qr/mailboxfull/    },
    { 'n' => '01049', 'r' => qr/mailboxfull/    },
    { 'n' => '01050', 'r' => qr/userunknown/    },
    { 'n' => '01051', 'r' => qr/undefined/      },
    { 'n' => '01052', 'r' => qr/suspend/        },
    { 'n' => '01053', 'r' => qr/filtered/       },
    { 'n' => '01054', 'r' => qr/userunknown/    },
    { 'n' => '01055', 'r' => qr/mailboxfull/    },
    { 'n' => '01056', 'r' => qr/userunknown/    },
    { 'n' => '01057', 'r' => qr/userunknown/    },
    { 'n' => '01058', 'r' => qr/userunknown/    },
    { 'n' => '01059', 'r' => qr/filtered/       },
    { 'n' => '01060', 'r' => qr/suspend/        },
    { 'n' => '01061', 'r' => qr/filtered/       },
    { 'n' => '01062', 'r' => qr/filtered/       },
    { 'n' => '01063', 'r' => qr/userunknown/    },
    { 'n' => '01064', 'r' => qr/userunknown/    },
    { 'n' => '01065', 'r' => qr/mailboxfull/    },
    { 'n' => '01066', 'r' => qr/userunknown/    },
    { 'n' => '01067', 'r' => qr/userunknown/    },
    { 'n' => '01068', 'r' => qr/userunknown/    },
    { 'n' => '01069', 'r' => qr/filtered/       },
    { 'n' => '01070', 'r' => qr/hostunknown/    },
    { 'n' => '01071', 'r' => qr/norelaying/     },
    { 'n' => '01072', 'r' => qr/hostunknown/    },
    { 'n' => '01073', 'r' => qr/suspend/        },
];

plan 'skip_all', sprintf("%s not found", $samplepath) unless -d $samplepath;
$enginetest->($enginename, $isexpected, 1, 0);
done_testing;

