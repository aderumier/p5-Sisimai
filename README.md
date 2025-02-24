![](https://libsisimai.org/static/images/logo/sisimai-x01.png)

[![License](https://img.shields.io/badge/license-BSD%202--Clause-orange.svg)](https://github.com/sisimai/p5-Sisimai/blob/master/LICENSE)
[![Coverage Status](https://img.shields.io/coveralls/sisimai/p5-Sisimai.svg)](https://coveralls.io/r/sisimai/p5-Sisimai)
[![Build Status](https://travis-ci.org/sisimai/p5-Sisimai.svg?branch=master)](https://travis-ci.org/sisimai/p5-Sisimai) 
[![Perl](https://img.shields.io/badge/perl-v5.10--v5.30-blue.svg)](https://www.perl.org)
[![CPAN](https://img.shields.io/badge/cpan-v4.25.4-blue.svg)](https://metacpan.org/pod/Sisimai)

- [**README-JA(日本語)**](README-JA.md)
- [What is Sisimai](#what-is-sisimai)
    - [Key features](#key-features)
    - [Command line demo](#command-line-demo)
- [Setting Up Sisimai](#setting-up-sisimai)
    - [System requirements](#system-requirements)
    - [Install](#install)
        - [From CPAN](#from-cpan)
        - [From GitHub](#from-github)
- [Usage](#usage)
    - [Basic usage](#basic-usage)
    - [Convert to JSON](#convert-to-json)
    - [Read bounce object](#read-bounce-object)
    - [Callback feature](#callback-feature)
    - [One-Liner](#one-liner)
    - [Output example](#output-example)
- [Sisimai Specification](#sisimai-specification)
    - [Differences between bounceHammer and Sisimai](#differences-between-bouncehammer-and-sisimai)
    - [Other specification of Sisimai](#other-specification-of-sisimai)
- [Contributing](#contributing)
    - [Bug report](#bug-report)
    - [Emails could not be parsed](#emails-could-not-be-parsed)
- [Other Information](#other-information)
    - [Related sites](#related-sites)
    - [See also](#see-also)
- [Author](#author)
- [Copyright](#copyright)
- [License](#license)


What is Sisimai
===============================================================================
Sisimai is a Perl module for analyzing RFC5322 bounce emails and generating
structured data from parsed results. Sisimai is the system formerly known as
bounceHammer 4. __Sisimai__ is a coined word: Sisi (the number 4 is pronounced
__Si__ in Japanese) and MAI (acronym of __Mail Analyzing Interface__).

![](https://libsisimai.org/static/images/figure/sisimai-overview-1.png)

Key features
-------------------------------------------------------------------------------
* __Convert Bounce Mails to Structured Data__
  * Supported formats are Perl(Hash, Array) and JSON(String)
* __Easy to Install, Use.__
  * `cpan`, `cpanm`, or `cpm`
  * git clone & make
* __High Precision of Analysis__
  * 2 times higher than bounceHammer
  * Support 24 known MTAs and 5 unknown MTAs
  * Support 22 major MSPs(Mail Service Providers)
  * Support  2 major Cloud Email Delivery Services(JSON format)
    * **WILL BE REMOVED AT Sisimai 4.25.5**
  * Support Feedback Loop Message(ARF)
  * Can detect 29 error reasons
* __Faster than bounceHammer 2.7.13p3__
  * About 2.0 times faster

Command line demo
-------------------------------------------------------------------------------
The following screen shows a demonstration of Sisimai at the command line using
Perl(p5-Sisimai) and Ruby(rb-Sisimai) version of Sisimai.
![](https://libsisimai.org/static/images/demo/sisimai-dump-01.gif)

Setting Up Sisimai
===============================================================================

System requirements
-------------------------------------------------------------------------------
More details about system requirements are available at
[Sisimai | Getting Started](https://libsisimai.org/en/start/) page.

* [Perl 5.10.1 or later](http://www.perl.org/)
* [__Class::Accessor::Lite__](https://metacpan.org/pod/Class::Accessor::Lite)
* [__JSON__](https://metacpan.org/pod/JSON)


Install
-------------------------------------------------------------------------------
### From CPAN

```shell
$ cpanm --sudo Sisimai
--> Working on Sisimai
Fetching http://www.cpan.org/authors/id/A/AK/AKXLIX/Sisimai-4.25.2.tar.gz ... OK
...
1 distribution installed
$ perldoc -l Sisimai
/usr/local/lib/perl5/site_perl/5.20.0/Sisimai.pm
```

### From GitHub

```shell
$ cd /usr/local/src
$ git clone https://github.com/sisimai/p5-Sisimai.git
$ cd ./p5-Sisimai
$ make install-from-local
--> Working on .
Configuring Sisimai-4.25.2 ... OK
1 distribution installed
```

Usage
===============================================================================

Basic usage
-------------------------------------------------------------------------------
`Sisimai->make()` method provides feature for getting parsed data as Perl Hash
reference from bounced email messages like following.

```perl
#! /usr/bin/env perl
use Sisimai;
my $v = Sisimai->make('/path/to/mbox'); # or path to Maildir/

# Beginning with v4.23.0, both make() and dump() method of Sisimai class can
# read bounce messages from variable instead of a path to mailbox
use IO::File;
my $r = '';
my $f = IO::File->new('/path/to/mbox'); # or path to Maildir/
{ local $/ = undef; $r = <$f>; $f->close }
my $v = Sisimai->make(\$r);

# If you want to get bounce records which reason is "delivered", set "delivered"
# option to make() method like the following:
my $v = Sisimai->make('/path/to/mbox', 'delivered' => 1);

if( defined $v ) {
    for my $e ( @$v ) {
        print ref $e;                   # Sisimai::Data
        print ref $e->recipient;        # Sisimai::Address
        print ref $e->timestamp;        # Sisimai::Time

        print $e->addresser->address;   # shironeko@example.org # From
        print $e->recipient->address;   # kijitora@example.jp   # To
        print $e->recipient->host;      # example.jp
        print $e->deliverystatus;       # 5.1.1
        print $e->replycode;            # 550
        print $e->reason;               # userunknown

        my $h = $e->damn();             # Convert to HASH reference
        my $j = $e->dump('json');       # Convert to JSON string
        print $e->dump('json');         # JSON formatted bounce data
    }
}
```

Convert to JSON
-------------------------------------------------------------------------------
`Sisimai->dump()` method provides feature for getting parsed data as JSON string
from bounced email messages like following.

```perl
#! /usr/bin/env perl
use Sisimai;

# Get JSON string from parsed mailbox or Maildir/
my $j = Sisimai->dump('/path/to/mbox'); # or path to Maildir/
                                        # dump() is added in v4.1.27
print $j;                               # parsed data as JSON

# dump() method also accepts "delivered" option like the following code:
my $j = Sisimai->dump('/path/to/mbox', 'delivered' => 1);
```

Read bounce object
-------------------------------------------------------------------------------
**THIS FEATURE WILL BE REMOVED AT SISIMAI 4.25.5**

The way to read a bounce object retrived from Cloud Email Services as JSON using
their API is the following code. This feature is available at between v4.20.0
and **v4.25.5**.

```perl
#! /usr/bin/env perl
use JSON;
use Sisimai;

my $j = JSON->new;
my $q = '{"json":"string",...}'
my $v = Sisimai->make($j->decode($q), 'input' => 'json');

if( defined $v ) {
    for my $e ( @$v ) { ... }
}
```
As of present, Only Amazon SES and SendGrid are supported.

Callback feature
-------------------------------------------------------------------------------
Beginning with Sisimai 4.19.0, `make()` and `dump()` methods of Sisimai accept
a sub routine reference in `hook` argument for setting a callback method and
getting the results generated by the method via `Sisimai::Data->catch` method.

```perl
#! /usr/bin/env perl
use Sisimai;
my $callbackto = sub {
    my $emdata = shift;
    my $caught = { 'x-mailer' => '', 'queue-id' => '' };

    if( $emdata->{'message'} =~ m/^X-Postfix-Queue-ID:\s*(.+)$/m ) {
        $caught->{'queue-id'} = $1;
    }

    $caught->{'x-mailer'} = $emdata->{'headers'}->{'x-mailer'} || '';
    return $caught;
};
my $list = ['X-Mailer'];
my $data = Sisimai->make('/path/to/mbox', 'hook' => $callbackto, 'field' => $list);
my $json = Sisimai->dump('/path/to/mbox', 'hook' => $callbackto, 'field' => $list);

print $data->[0]->catch->{'x-mailer'};    # Apple Mail (2.1283)
```

More information about the callback feature is available at
[Sisimai | How To Parse - Callback](https://libsisimai.org/en/usage/#callback)
Page.

One-Liner
-------------------------------------------------------------------------------
Beginning with Sisimai 4.1.27, `dump()` method is available and you can get parsed
data as JSON using the method.

```shell
$ perl -MSisimai -lE 'print Sisimai->dump(shift)' /path/to/mbox
```

Output example
-------------------------------------------------------------------------------
![](https://libsisimai.org/static/images/demo/sisimai-dump-02.gif)

```json
[{"action": "failed", "subject": "Nyaan", "catch": null, "token": "08acf78323edc7923a783c04749dd547ab45c433", "alias": "", "messageid": "201806090556.w595u8GZ093276@neko.example.jp", "listid": "", "smtpcommand": "MAIL", "smtpagent": "Email::Sendmail", "lhost": "localhost", "timezoneoffset": "+0900", "feedbacktype": "", "senderdomain": "neko.example.jp", "diagnostictype": "SMTP", "softbounce": 1, "deliverystatus": "5.0.0", "addresser": "kijitora@neko.example.jp", "diagnosticcode": "550 Unauthenticated senders not allowed", "timestamp": 1528523769, "destination": "example.com", "recipient": "sironeko@example.com", "reason": "securityerror", "replycode": "550", "rhost": "neko.example.jp"}]
```

Sisimai Specification
===============================================================================

Differences between bounceHammer and Sisimai
-------------------------------------------------------------------------------
The following table show the differences between ver.2 (bounceHammer 2.7.13p3)
and Sisimai. More information about differences are available at
[Sisimai | Differences](https://libsisimai.org/en/diff/) page.

| Features                                       | bounceHammer  | Sisimai     |
|------------------------------------------------|---------------|-------------|
| System requirements(Perl)                      | 5.10 - 5.14   | 5.10 - 5.30 |
| Command line tools                             | Available     | N/A         |
| Modules for Commercial MTAs and MPSs           | N/A           | Included    |
| WebUI/API                                      | Included      | N/A         |
| Database schema for storing parsed bounce data | Available     | N/A[1]      |
| Analytical precision ratio(2000 emails)[2]     | 0.61          | 1.00        |
| The speed of parsing email(1000 emails)        | 4.24s         | 1.50s[3]    |
| The number of detectable bounce reasons        | 19            | 29          |
| Parse 2 or more bounces in a single email      | Only 1st rcpt | ALL         |
| Parse FeedBack Loop Message/ARF format mail    | Unable        | OK          |
| Classification based on recipient domain       | Available     | N/A         |
| Output format of parsed data                   | YAML,JSON,CSV | JSON only   |
| Easy to install                                | No            | Yes         |
| Install using cpan, cpanm, or cpm command      | N/A           | OK          |
| Dependencies (Except core modules of Perl)     | 24 modules    | 2 modules   |
| LOC:Source lines of code                       | 18200 lines   | 8300 lines  |
| The number of tests in t/, xt/ directory       | 27365 tests   | 250000 tests|
| License                                        | GPLv2 or Perl | 2 clause BSD|
| Support Contract provided by Developer         | End Of Sales  | Available   |

1. Implement yourself with using DBI or any O/R Mapper you like
2. See [./ANALYTICAL-PRECISION](https://github.com/sisimai/p5-Sisimai/blob/master/ANALYTICAL-PRECISION)
3. Xeon E5-2640 2.5GHz x 2 cores | 5000 bogomips | 1GB RAM | Perl 5.24.1

Other specification of Sisimai
-------------------------------------------------------------------------------
- [**Parser Engines**](https://libsisimai.org/en/engine/)
- [**Bounce Reason List**](https://libsisimai.org/en/reason/)
- [**Data Structure of Sisimai::Data**](https://libsisimai.org/en/data/)


Contributing
===============================================================================

Bug report
-------------------------------------------------------------------------------
Please use the [issue tracker](https://github.com/sisimai/p5-Sisimai/issues)
to report any bugs.

Emails could not be parsed
-------------------------------------------------------------------------------
Bounce mails which could not be parsed by Sisimai are saved in the repository
[set-of-emails/to-be-debugged-because/sisimai-cannot-parse-yet](https://github.com/sisimai/set-of-emails/tree/master/to-be-debugged-because/sisimai-cannot-parse-yet). 
If you have found any bounce email cannot be parsed using Sisimai, please add
the email into the directory and send Pull-Request to this repository.


Other Information
===============================================================================
Related sites
-------------------------------------------------------------------------------
* __@libsisimai__ | [Sisimai on Twitter (@libsisimai)](https://twitter.com/libsisimai)
* __libSISIMAI.ORG__ | [Sisimai | The Successor To bounceHammer, Library to parse bounce mails](https://libsisimai.org/)
* __Sisimai Blog__ | [blog.libsisimai.org](http://blog.libsisimai.org/)
* __Facebook Page__ | [facebook.com/libsisimai](https://www.facebook.com/libsisimai/)
* __GitHub__ | [github.com/sisimai/p5-Sisimai](https://github.com/sisimai/p5-Sisimai)
* __CPAN__ | [Sisimai - Mail Analyzing Interface for bounce mails. - metacpan.org](https://metacpan.org/pod/Sisimai)
* __CPAN Testers Reports__ | [CPAN Testers Reports: Reports for Sisimai](http://cpantesters.org/distro/S/Sisimai.html)
* __Ruby verson__ | [Ruby version of Sisimai](https://github.com/sisimai/rb-Sisimai)
* __Fixtures__ | [set-of-emails - Sample emails for "make test"](https://github.com/sisimai/set-of-emails)
* __bounceHammer.JP__ | [bounceHammer will be EOL on February 29, 2016](http://bouncehammer.jp/)

See also
-------------------------------------------------------------------------------
* [README-JA.md - README.md in Japanese(日本語)](https://github.com/sisimai/p5-Sisimai/blob/master/README-JA.md)
* [RFC3463 - Enhanced Mail System Status Codes](https://tools.ietf.org/html/rfc3463)
* [RFC3464 - An Extensible Message Format for Delivery Status Notifications](https://tools.ietf.org/html/rfc3464)
* [RFC3834 - Recommendations for Automatic Responses to Electronic Mail](https://tools.ietf.org/html/rfc3834)
* [RFC5321 - Simple Mail Transfer Protocol](https://tools.ietf.org/html/rfc5321)
* [RFC5322 - Internet Message Format](https://tools.ietf.org/html/rfc5322)

Author
===============================================================================
[@azumakuniyuki](https://twitter.com/azumakuniyuki)

Copyright
===============================================================================
Copyright (C) 2014-2019 azumakuniyuki, All Rights Reserved.

License
===============================================================================
This software is distributed under The BSD 2-Clause License.

