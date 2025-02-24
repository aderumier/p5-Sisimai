package Sisimai::Message;
use feature ':5.10';
use strict;
use warnings;
use Class::Accessor::Lite;
use Sisimai::RFC5322;
use Sisimai::RFC3834;
use Sisimai::Address;
use Sisimai::String;
use Sisimai::Order;
use Sisimai::MIME;
use Sisimai::ARF;
use Sisimai::SMTP::Error;

my $rwaccessors = [
    'from',     # [String] UNIX From line
    'header',   # [Hash]   Header part of an email
    'ds',       # [Array]  Parsed data by Sisimai::Lhost
    'rfc822',   # [Hash]   Header part of the original message
    'catch'     # [Any]    The results returned by hook method
];
Class::Accessor::Lite->mk_accessors(@$rwaccessors);

my $ToBeLoaded = [];
my $TryOnFirst = [];
my $DefaultSet = Sisimai::Order->another;
my $ExtHeaders = Sisimai::Order->headers;
my $SubjectTab = Sisimai::Order->by('subject');
my $RFC822Head = Sisimai::RFC5322->HEADERFIELDS;
my @RFC3834Set = @{ Sisimai::RFC3834->headerlist };
my @HeaderList = (qw|from to date subject content-type reply-to message-id
                     received content-transfer-encoding return-path x-mailer|);
my $IsMultiple = { 'received' => 1 };
my $EndOfEmail = Sisimai::String->EOM;

sub new {
    # Constructor of Sisimai::Message
    # @param         [Hash] argvs       Email text data
    # @options argvs [String] data      Entire email message
    # @options argvs [Array]  load      User defined MTA module list
    # @options argvs [Array]  order     The order of MTA modules
    # @options argvs [Array]  field     Email header names to be captured
    # @options argvs [Code]   hook      Reference to callback method
    # @return        [Sisimai::Message] Structured email data or Undef if each
    #                                   value of the arguments are missing
    my $class = shift;
    my $argvs = { @_ };
    my $email = $argvs->{'data'}  || return undef;
    my $field = $argvs->{'field'} || [];
    my $input = ref $email eq 'HASH' ? 'json' : 'email';

    if( ref $field ne 'ARRAY' ) {
        # Unsupported value in "field"
        warn ' ***warning: "field" accepts an array reference only';
        return undef;
    }

    my $methodargv = {
        'data'  => $email,
        'hook'  => $argvs->{'hook'}  // undef,
        'field' => $field,
        'input' => $input,
    };

    for my $e ('load', 'order') {
        # Order of MTA modules
        next unless exists $argvs->{ $e };
        next unless ref $argvs->{ $e } eq 'ARRAY';
        next unless scalar @{ $argvs->{ $e } };
        $methodargv->{ $e } = $argvs->{ $e };
    }

    my $datasource = __PACKAGE__->make(%$methodargv);
    return undef unless $datasource->{'ds'};

    my $mesgobject = {
        'from'   => $datasource->{'from'},
        'header' => $datasource->{'header'},
        'ds'     => $datasource->{'ds'},
        'rfc822' => $datasource->{'rfc822'},
        'catch'  => $datasource->{'catch'} || undef,
    };
    return bless($mesgobject, $class);
}

sub make {
    # Make data structure from the email (a body part and headers or JSON)
    # @param         [Hash] argvs   Email data
    # @options argvs [String] data  Entire email message
    # @options argvs [Array]  load  User defined MTA module list
    # @options argvs [Array]  order The order of MTA modules
    # @options argvs [Array]  field Email header names to be captured
    # @options argvs [Code]   hook  Reference to callback method
    # @return        [Hash]         Resolved data structure
    my $class = shift;
    my $argvs = { @_ };
    my $email = $argvs->{'data'};

    my $bouncedata = undef;
    my $hookmethod = $argvs->{'hook'}  || undef;
    my $headerlist = $argvs->{'field'} || [];
    my $aftersplit = {};
    my $processing = {
        'from'   => '',     # From_ line
        'header' => {},     # Email header
        'rfc822' => '',     # Original message part
        'ds'     => [],     # Parsed data, Delivery Status
        'catch'  => undef,  # Data parsed by callback method
    };
    my $methodargv = {
        'load'  => $argvs->{'load'}  || [],
        'order' => $argvs->{'order'} || [],
        'input' => $argvs->{'input'},
    };
    $ToBeLoaded = __PACKAGE__->load(%$methodargv);

    if( $argvs->{'input'} eq 'email' ) {
        # Email message
        # 1. Split email data to headers and a body part.
        return undef unless $aftersplit = __PACKAGE__->divideup(\$email);

        # 2. Convert email headers from text to hash reference
        $TryOnFirst = [];
        $processing->{'from'}   = $aftersplit->{'from'};
        $processing->{'header'} = __PACKAGE__->headers(\$aftersplit->{'header'}, $headerlist);

        # 3. Check headers for detecting MTA module
        unless( scalar @$TryOnFirst ) {
            push @$TryOnFirst, @{ Sisimai::Order->make($processing->{'header'}, 'email') };
        }

        # 4. Rewrite message body for detecting the bounce reason
        $methodargv = {
            'hook' => $hookmethod,
            'mail' => $processing,
            'body' => \$aftersplit->{'body'},
        };
        return undef unless $bouncedata = __PACKAGE__->parse(%$methodargv);

    } else {
        # JSON structure
        $DefaultSet = Sisimai::Order->forjson;
        $methodargv = { 'hook' => $hookmethod, 'json' => $email };
        return undef unless $bouncedata = __PACKAGE__->adapt(%$methodargv);
    }
    return undef unless keys %$bouncedata;

    map { $processing->{ $_ } = $bouncedata->{ $_ } } ('ds', 'catch', 'rfc822');
    if( $argvs->{'input'} eq 'email' ) {
        # 5. Rewrite headers of the original message in the body part
        my $p = $bouncedata->{'rfc822'} || $aftersplit->{'body'};
        $processing->{'rfc822'} = ref $p ? $p : __PACKAGE__->takeapart(\$p);
    }
    return $processing;
}

sub load {
    # Load MTA modules which specified at 'order' and 'load' in the argument
    # @param         [Hash] argvs       Module information to be loaded
    # @options argvs [Array]  load      User defined MTA module list
    # @options argvs [Array]  order     The order of MTA modules
    # @return        [Array]            Module list
    # @since v4.20.0
    my $class = shift;
    my $argvs = { @_ };

    my @modulelist;
    my $tobeloaded = [];

    for my $e ('load', 'order') {
        # The order of MTA modules specified by user
        next unless exists $argvs->{ $e };
        next unless ref $argvs->{ $e } eq 'ARRAY';
        next unless scalar @{ $argvs->{ $e } };

        push @modulelist, @{ $argvs->{'order'} } if $e eq 'order';
        next unless $e eq 'load';

        # Load user defined MTA module
        for my $v ( @{ $argvs->{'load'} } ) {
            # Load user defined MTA module
            eval {
                (my $modulepath = $v) =~ s|::|/|g;
                require $modulepath.'.pm';
            };
            next if $@;
            next unless $argvs->{'input'} eq 'email';

            for my $w ( @{ $v->headerlist } ) {
                # Get header name which required user defined MTA module
                $ExtHeaders->{ $w }->{ $v } = 1;
            }
            push @$tobeloaded, $v;
        }
    }

    for my $e ( @modulelist ) {
        # Append the custom order of MTA modules
        next if grep { $e eq $_ } @$tobeloaded;
        push @$tobeloaded, $e;
    }
    return $tobeloaded;
}

sub makeorder {
    # Check headers for detecting MTA module and returns the order of modules
    # @param         [Hash] heads   Email header data
    # @return        [Array]        Order of MTA modules
    my $class = shift;
    my $heads = shift || return [];
    my $order = [];

    return [] unless exists $heads->{'subject'};
    return [] unless $heads->{'subject'};

    # Try to match the value of "Subject" with patterns generated by
    # Sisimai::Order->by('subject') method
    my $title = lc $heads->{'subject'};
    for my $e ( keys %$SubjectTab ) {
        # Get MTA list from the subject header
        next if index($title, $e) == -1;
        push @$order, @{ $SubjectTab->{ $e } }; # Matched and push MTA list
        last;
    }
    return $order;
}

sub headers {
    # Convert email headers from text to hash reference
    # @param         [String] heads  Email header data
    # @return        [Hash]          Structured email header data
    my $class = shift;
    my $heads = shift || return undef;
    my $field = shift || [];

    my $currheader = '';
    my $allheaders = {};
    my $structured = {};
    my @hasdivided = split("\n", $$heads);

    map { $allheaders->{ $_ } = 1 } (@HeaderList, @RFC3834Set, keys %$ExtHeaders);
    map { $allheaders->{ lc $_ } = 1 } @$field if scalar @$field;
    map { $structured->{ $_ } = undef } @HeaderList;
    map { $structured->{ $_ } = [] } keys %$IsMultiple;

    SPLIT_HEADERS: while( my $e = shift @hasdivided ) {
        # Convert email headers to hash
        if( $e =~ /\A[ \t]+(.+)\z/ ) {
            # Continued (foled) header value from the previous line
            next unless exists $allheaders->{ $currheader };

            # Header line continued from the previous line
            if( ref $structured->{ $currheader } eq 'ARRAY' ) {
                # Concatenate a header which have multi-lines such as 'Received'
                $structured->{ $currheader }->[-1] .= ' '.$1;
            } else {
                $structured->{ $currheader } .= ' '.$1;
            }
        } else {
            # split the line into a header name and a header content
            my($lhs, $rhs) = split(/:[ ]*/, $e, 2);
            $currheader = lc $lhs;
            next unless exists $allheaders->{ $currheader };

            if( exists $IsMultiple->{ $currheader } ) {
                # Such as 'Received' header, there are multiple headers in a single
                # email message.
                $rhs =~ y/\t/ /;
                push @{ $structured->{ $currheader } }, $rhs;
            } else {
                # Other headers except "Received" and so on
                if( $ExtHeaders->{ $currheader } ) {
                    # MTA specific header
                    for my $p ( @{ $ExtHeaders->{ $currheader } } ) {
                        next if grep { $p eq $_ } @$TryOnFirst;
                        push @$TryOnFirst, $p;
                    }
                }
                $structured->{ $currheader } = $rhs;
            }
        }
    }
    return $structured;
}

sub divideup {
    # Divide email data up headers and a body part.
    # @param         [String] email  Email data
    # @return        [Hash]          Email data after split
    # @since v4.14.0
    my $class = shift;
    my $email = shift // return undef;
    my $block = { 'from' => '', 'header' => '', 'body' => '' };

    $$email =~ s/\r\n/\n/gm  if rindex($$email, "\r\n") > -1;
    $$email =~ s/[ \t]+$//gm if $$email =~ /[ \t]+$/;

    ($block->{'header'}, $block->{'body'}) = split(/\n\n/, $$email, 2);
    return undef unless $block->{'header'};
    return undef unless $block->{'body'};

    if( substr($block->{'header'}, 0, 5) eq 'From ' ) {
        # From MAILER-DAEMON Tue Feb 11 00:00:00 2014
        $block->{'from'} =  [split(/\n/, $block->{'header'}, 2)]->[0];
        $block->{'from'} =~ y/\r\n//d;
    } else {
        # Set pseudo UNIX From line
        $block->{'from'} =  'MAILER-DAEMON Tue Feb 11 00:00:00 2014';
    }

    $block->{'body'} .= "\n";
    return $block;
}

sub takeapart {
    # Take each email header in the original message apart
    # @param         [String] heads The original message header
    # @return        [Hash]         Structured message headers
    my $class = shift;
    my $heads = shift || return {};

    state $borderline = '__MIME_ENCODED_BOUNDARY__';
    $$heads =~ s/^[>]+[ ]//mg;    # Remove '>' indent symbol of forwarded message
    $$heads =~ s/=[ ]+=/=\n =/mg; # Replace ' ' with "\n" at unfolded values

    my $previousfn = '';
    my $asciiarmor = {};    # Header names which has MIME encoded value
    my $headerpart = {};    # Required headers in the original message part

    for my $e ( split("\n", $$heads) ) {
        # Header name as a key, The value of header as a value
        if( $e =~ /\A[ \t]+/ ) {
            # Continued (foled) header value from the previous line
            next unless $previousfn;

            # Concatenate the line if it is the value of required header
            if( Sisimai::MIME->is_mimeencoded(\$e) ) {
                # The line is MIME-Encoded test
                if( $previousfn eq 'subject' ) {
                    # Subject: header
                    $headerpart->{ $previousfn } .= $borderline.$e;
                } else {
                    # Is not Subject header
                    $headerpart->{ $previousfn } .= $e;
                }
                $asciiarmor->{ $previousfn } = 1;

            } else {
                # ASCII Characters only: Not MIME-Encoded
                $e =~ s/\A[ \t]+//; # unfolding
                $headerpart->{ $previousfn }  .= $e;
                $asciiarmor->{ $previousfn } //= 0;
            }
        } else {
            # Header name as a key, The value of header as a value
            my($lhs, $rhs) = split(/:[ ]*/, $e, 2);
            next unless $lhs = lc($lhs || '');
            $previousfn = '';

            next unless exists $RFC822Head->{ $lhs };
            $previousfn = $lhs;
            $headerpart->{ $previousfn } //= $rhs;
        }
    }
    return $headerpart unless $headerpart->{'subject'};

    # Convert MIME-Encoded subject
    if( Sisimai::String->is_8bit(\$headerpart->{'subject'}) ) {
        # The value of ``Subject'' header is including multibyte character,
        # is not MIME-Encoded text.
        eval {
            # Remove invalid byte sequence
            Encode::decode_utf8($headerpart->{'subject'});
            Encode::encode_utf8($headerpart->{'subject'});
        };
        $headerpart->{'subject'} = 'MULTIBYTE CHARACTERS HAVE BEEN REMOVED' if $@;

    } else {
        # MIME-Encoded subject field or ASCII characters only
        my $r = [];
        if( $asciiarmor->{'subject'} ) {
            # split the value of Subject by $borderline
            for my $v ( split($borderline, $headerpart->{'subject'}) ) {
                # Insert value to the array if the string is MIME encoded text
                push @$r, $v if Sisimai::MIME->is_mimeencoded(\$v);
            }
        } else {
            # Subject line is not MIME encoded
            $r = [$headerpart->{'subject'}];
        }
        $headerpart->{'subject'} = Sisimai::MIME->mimedecode($r);
    }
    return $headerpart;
}

sub parse {
    # Parse bounce mail with each MTA module
    # @param               [Hash] argvs    Processing message entity.
    # @param options argvs [Hash] mail     Email message entity
    # @param options mail  [String] from   From line of mbox
    # @param options mail  [Hash]   header Email header data
    # @param options mail  [String] rfc822 Original message part
    # @param options mail  [Array]  ds     Delivery status list(parsed data)
    # @param options argvs [String] body   Email message body
    # @param options argvs [Code]   hook   Hook method to be called
    # @return              [Hash]          Parsed and structured bounce mails
    my $class = shift;
    my $argvs = { @_ };

    my $mailheader = $argvs->{'mail'}->{'header'} || return '';
    my $bodystring = $argvs->{'body'} || return '';
    my $hookmethod = $argvs->{'hook'} || undef;
    my $havecaught = undef;

    # PRECHECK_EACH_HEADER:
    # Set empty string if the value is undefined
    $mailheader->{'from'}         //= '';
    $mailheader->{'subject'}      //= '';
    $mailheader->{'content-type'} //= '';

    # Decode BASE64 Encoded message body
    my $mesgformat = lc($mailheader->{'content-type'} || '');
    my $ctencoding = lc($mailheader->{'content-transfer-encoding'} || '');

    if( index($mesgformat, 'text/plain') == 0 || index($mesgformat, 'text/html') == 0 ) {
        # Content-Type: text/plain; charset=UTF-8
        if( $ctencoding eq 'base64' ) {
            # Content-Transfer-Encoding: base64
            $bodystring = Sisimai::MIME->base64d($bodystring);

        } elsif( $ctencoding eq 'quoted-printable' ) {
            # Content-Transfer-Encoding: quoted-printable
            $bodystring = Sisimai::MIME->qprintd($bodystring);
        }

        # Content-Type: text/html;...
        $bodystring = Sisimai::String->to_plain($bodystring, 1) if $mesgformat =~ m|text/html;?|;
    } else {
        # NOT text/plain
        if( index($mesgformat, 'multipart/') == 0 ) {
            # In case of Content-Type: multipart/*
            my $p = Sisimai::MIME->makeflat($mailheader->{'content-type'}, $bodystring);
            $bodystring = $p if length $$p;
        }
    }

    # EXPAND_FORWARDED_MESSAGE:
    # Check whether or not the message is a bounce mail.
    # Pre-Process email body if it is a forwarded bounce message.
    # Get the original text when the subject begins from 'fwd:' or 'fw:'
    if( lc($mailheader->{'subject'}) =~ /\A[ \t]*fwd?:/ ) {
        # Delete quoted strings, quote symbols(>)
        $$bodystring =~ s/^[>]+[ ]//gm;
        $$bodystring =~ s/^[>]$//gm;

    } elsif( Sisimai::MIME->is_mimeencoded(\$mailheader->{'subject'}) ) {
        # Decode MIME-Encoded "Subject:" header
        $mailheader->{'subject'} = Sisimai::MIME->mimedecode([split(/[ ]/, $mailheader->{'subject'})]);
    }
    $$bodystring =~ tr/\r//d;

    if( ref $hookmethod eq 'CODE' ) {
        # Call hook method
        my $p = {
            'datasrc' => 'email',
            'headers' => $mailheader,
            'message' => $$bodystring,
            'bounces' => undef,
        };
        eval { $havecaught = $hookmethod->($p) };
        warn sprintf(" ***warning: Something is wrong in hook method:%s", $@) if $@;
    }
    $$bodystring .= $EndOfEmail;

    my $haveloaded = {};
    my $parseddata = undef;
    my $modulepath = '';

    PARSER: while(1) {
        # 1. Sisimai::ARF
        # 2. User-Defined Module
        # 3. MTA Module Candidates to be tried on first
        # 4. Sisimai::Lhost::*
        # 5. Sisimai::RFC3464
        # 6. Sisimai::RFC3834
        if( Sisimai::ARF->is_arf($mailheader) ) {
            # Feedback Loop message
            $parseddata = Sisimai::ARF->make($mailheader, $bodystring);
            last(PARSER) if $parseddata;
        }

        USER_DEFINED: for my $r ( @$ToBeLoaded ) {
            # Call user defined MTA modules
            next if exists $haveloaded->{ $r };
            $parseddata = $r->make($mailheader, $bodystring);
            $haveloaded->{ $r } = 1;
            last(PARSER) if $parseddata;
        }

        TRY_ON_FIRST_AND_DEFAULTS: for my $r ( @$TryOnFirst, @$DefaultSet ) {
            # Try MTA module candidates
            next if exists $haveloaded->{ $r };
            ($modulepath = $r) =~ s|::|/|g;
            require $modulepath.'.pm';
            $parseddata = $r->make($mailheader, $bodystring);
            $haveloaded->{ $r } = 1;
            last(PARSER) if $parseddata;
        }

        # When the all of Sisimai::Lhost::* modules did not return bounce data,
        # call Sisimai::RFC3464;
        require Sisimai::RFC3464;
        $parseddata = Sisimai::RFC3464->make($mailheader, $bodystring);
        last(PARSER) if $parseddata;

        # Try to parse the message as auto reply message defined in RFC3834
        $parseddata = Sisimai::RFC3834->make($mailheader, $bodystring);
        last(PARSER) if $parseddata;

        # as of now, we have no sample email for coding this block
        last;
    } # End of while(PARSER)

    $parseddata->{'catch'} = $havecaught if $parseddata;
    return $parseddata;
}

sub adapt {
    # Adapt bounce object as JSON with each MTA module
    # @param               [Hash] argvs    Processing message entity.
    # @param options argvs [Hash] json     Decoded bounce object
    # @param options argvs [Code] hook     Hook method to be called
    # @return              [Hash]          Parsed and structured bounce mails
    # @until v4.25.5
    __PACKAGE__->warn('gone');
    my $class = shift;
    my $argvs = { @_ };

    my $bouncedata = $argvs->{'json'} || {};
    my $hookmethod = $argvs->{'hook'} || undef;
    my $havecaught = undef;
    my $haveloaded = {};
    my $parseddata = undef;
    my $modulepath = undef;

    if( ref $hookmethod eq 'CODE' ) {
        # Call hook method
        my $p = {
            'datasrc' => 'json',
            'headers' => undef,
            'message' => undef,
            'bounces' => $argvs->{'json'},
        };
        eval { $havecaught = $hookmethod->($p) };
        warn sprintf(" ***warning: Something is wrong in hook method:%s", $@) if $@;
    }

    ADAPTOR: while(1) {
        # 1. User-Defined Module
        # 2. MTA Module Candidates to be tried on first
        # 3. Sisimai::Lhost::*
        USER_DEFINED: for my $r ( @$ToBeLoaded ) {
            # Call user defined MTA modules
            next if exists $haveloaded->{ $r };
            eval {
                ($modulepath = $r) =~ s|::|/|g;
                require $modulepath.'.pm';
            };
            if( $@ ) {
                warn sprintf(" ***warning: Failed to load %s: %s", $r, $@);
                next;
            }
            $parseddata = $r->json($bouncedata);
            $haveloaded->{ $r } = 1;
            last(ADAPTOR) if $parseddata;
        }

        DEFAULT_LIST: for my $r ( @$DefaultSet ) {
            # Default order of MTA modules
            next if exists $haveloaded->{ $r };
            ($modulepath = $r) =~ s|::|/|g;
            require $modulepath.'.pm';

            $parseddata = $r->json($bouncedata);
            $haveloaded->{ $r } = 1;
            last(ADAPTOR) if $parseddata;
        }
        last;   # as of now, we have no sample json data for coding this block
    } # End of while(ADAPTOR)

    $parseddata->{'catch'} = $havecaught if $parseddata;
    map { $_->{'agent'} =~ s/\AEmail::/JSON::/g } @{ $parseddata->{'ds'} };
    return $parseddata;
}

sub warn {
    # Print warnings about an obsoleted method
    # This method will be removed at the future release of Sisimai
    my $class = shift;
    my $useit = shift || '';
    my $label = ' ***warning:';

    my $calledfrom = [caller(1)];
    my $modulename = $calledfrom->[3]; $modulename =~ s/::[a-z]+\z//;
    my $methodname = $calledfrom->[3]; $methodname =~ s/\A.+:://;
    my $messageset = sprintf("%s %s->%s is marked as obsoleted", $label, $modulename, $methodname);

    $useit ||= $methodname;
    $messageset .= sprintf(" and will be removed at %s.", Sisimai::Lhost->removedat);
    $messageset .= sprintf(" Use %s->%s instead.\n", __PACKAGE__, $useit) if $useit ne 'gone';

    warn $messageset;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Message - Convert bounce email text to data structure.

=head1 SYNOPSIS

    use Sisimai::Mail;
    use Sisimai::Message;

    my $mailbox = Sisimai::Mail->new('/var/mail/root');
    while( my $r = $mailbox->read ) {
        my $p = Sisimai::Message->new('data' => $r);
    }

    my $notmail = '/home/neko/Maildir/cur/22222';   # is not a bounce email
    my $mailobj = Sisimai::Mail->new($notmail);
    while( my $r = $mailobj->read ) {
        my $p = Sisimai::Message->new('data' => $r);  # $p is "undef"
    }

=head1 DESCRIPTION

Sisimai::Message convert bounce email text to data structure. It resolve email
text into an UNIX From line, the header part of the mail, delivery status, and
RFC822 header part. When the email given as a argument of "new" method is not a
bounce email, the method returns "undef".

=head1 CLASS METHODS

=head2 C<B<new(I<Hash reference>)>>

C<new()> is a constructor of Sisimai::Message

    my $mailtxt = 'Entire email text';
    my $message = Sisimai::Message->new('data' => $mailtxt);

If you have implemented a custom MTA module and use it, set the value of "load"
in the argument of this method as an array reference like following code:

    my $message = Sisimai::Message->new(
                        'data' => $mailtxt,
                        'load' => ['Your::Custom::MTA::Module']
                  );

Beginning from v4.19.0, `hook` argument is available to callback user defined
method like the following codes:

    my $cmethod = sub {
        my $argv = shift;
        my $data = {
            'queue-id' => '',
            'x-mailer' => '',
            'precedence' => '',
        };

        # Header part of the bounced mail
        for my $e ( 'x-mailer', 'precedence' ) {
            next unless exists $argv->{'headers'}->{ $e };
            $data->{ $e } = $argv->{'headers'}->{ $e };
        }

        # Message body of the bounced email
        if( $argv->{'message'} =~ /^X-Postfix-Queue-ID:\s*(.+)$/m ) {
            $data->{'queue-id'} = $1;
        }

        return $data;
    };

    my $message = Sisimai::Message->new(
        'data' => $mailtxt,
        'hook' => $cmethod,
        'field' => ['X-Mailer', 'Precedence']
    );
    print $message->catch->{'x-mailer'};    # Apple Mail (2.1283)
    print $message->catch->{'queue-id'};    # 2DAEB222022E
    print $message->catch->{'precedence'};  # bulk

=head1 INSTANCE METHODS

=head2 C<B<(from)>>

C<from()> returns the UNIX From line of the email.

    print $message->from;

=head2 C<B<header()>>

C<header()> returns the header part of the email.

    print $message->header->{'subject'};    # Returned mail: see transcript for details

=head2 C<B<ds()>>

C<ds()> returns an array reference which include contents of delivery status.

    for my $e ( @{ $message->ds } ) {
        print $e->{'status'};   # 5.1.1
        print $e->{'recipient'};# neko@example.jp
    }

=head2 C<B<rfc822()>>

C<rfc822()> returns a hash reference which include the header part of the original
message.

    print $message->rfc822->{'from'};   # cat@example.com
    print $message->rfc822->{'to'};     # neko@example.jp

=head2 C<B<catch()>>

C<catch()> returns any data generated by user-defined method passed at the `hook`
argument of new() constructor.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2019 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut
