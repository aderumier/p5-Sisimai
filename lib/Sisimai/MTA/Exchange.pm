package Sisimai::MTA::Exchange;
use parent 'Sisimai::MTA';
use feature ':5.10';
use strict;
use warnings;

my $Re0 = {
    # X-Mailer: Internet Mail Service (5.0.1461.28)
    # X-Mailer: Microsoft Exchange Server Internet Mail Connector Version ...
    'x-mailer'  => qr{\A(?:
         Internet[ ]Mail[ ]Service[ ][(][\d.]+[)]\z
        |Microsoft[ ]Exchange[ ]Server[ ]Internet[ ]Mail[ ]Connector
        )
    }x,
    'x-mimeole' => qr/\AProduced By Microsoft Exchange/,
    # Received: by ***.**.** with Internet Mail Service (5.5.2657.72)
    'received'  => qr/\Aby .+ with Internet Mail Service [(][\d.]+[)]/,
};
my $Re1 = {
    'begin'  => qr/\AYour message/,
    'error'  => qr/\Adid not reach the following recipient[(]s[)]:/,
    'rfc822' => qr|\AContent-Type: message/rfc822|,
    'endof'  => qr/\A__END_OF_EMAIL_MESSAGE__\z/,
};
my $CodeTable = {
    'onhold' => [
        '000B099C', # Host Unknown, Message exceeds size limit, ...
        '000B09AA', # Unable to relay for, Message exceeds size limit,...
        '000B09B6', # Error messages by remote MTA
    ],
    'userunknown' => [
        '000C05A6', # Unknown Recipient,
    ],
    'systemerror' => [
        '00010256', # Too many recipients. 
        '000D06B5', # No proxy for recipient (non-smtp mail?)
    ],
    'networkerror' => [
        '00120270', # Too Many Hops
    ],
    'contenterr' => [
        '00050311', # Conversion to Internet format failed
        '000502CC', # Conversion to Internet format failed
    ],
    'securityerr' => [
        '000B0981', # 502 Server does not support AUTH
    ],
    'filtered' => [
        '000C0595', # Ambiguous Recipient
    ],
};
my $Indicators = __PACKAGE__->INDICATORS;

sub description { 'Microsoft Exchange Server' }
sub smtpagent   { 'Exchange' }

# X-MS-TNEF-Correlator: <00000000000000000000000000000000000000@example.com>
# X-Mailer: Internet Mail Service (5.5.1960.3)
# X-MS-Embedded-Report: 
sub headerlist  { return [ 'X-MS-Embedded-Report', 'X-MimeOLE' ] };
sub pattern     { return $Re0 }

sub scan {
    # Detect an error from Microsoft Exchange Server
    # @param         [Hash] mhead       Message header of a bounce email
    # @options mhead [String] from      From header
    # @options mhead [String] date      Date header
    # @options mhead [String] subject   Subject header
    # @options mhead [Array]  received  Received headers
    # @options mhead [String] others    Other required headers
    # @param         [String] mbody     Message body of a bounce email
    # @return        [Hash, Undef]      Bounce data list and message/rfc822 part
    #                                   or Undef if it failed to parse or the
    #                                   arguments are missing
    # @since v4.1.1
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;
    my $match = 0;

    $match ||= 1 if defined $mhead->{'x-ms-embedded-report'};
    EXCHANGE_OR_NOT: while( 1 ) {
        # Check the value of X-Mailer header
        last if $match;

        if( defined $mhead->{'x-mailer'} ) {
            # X-Mailer:  Microsoft Exchange Server Internet Mail Connector Version 4.0.994.63
            # X-Mailer: Internet Mail Service (5.5.2232.9)
            $match ||= 1 if $mhead->{'x-mailer'} =~ $Re0->{'x-mailer'};
            last if $match;
        }

        if( defined $mhead->{'x-mimeole'} ) {
            # X-MimeOLE: Produced By Microsoft Exchange V6.5
            $match ||= 1 if $mhead->{'x-mimeole'} =~ $Re0->{'x-mimeole'};
            last if $match;
        }

        last unless scalar @{ $mhead->{'received'} };
        for my $e ( @{ $mhead->{'received'} } ) {
            # Received: by ***.**.** with Internet Mail Service (5.5.2657.72)
            next unless $e =~ $Re0->{'received'};
            $match = 1;
            last(EXCHANGE_OR_NOT);
        }
        last;
    }
    return undef unless $match;

    my $dscontents = [ __PACKAGE__->DELIVERYSTATUS ];
    my @hasdivided = split( "\n", $$mbody );
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822list = [];    # (Array) Each line in message/rfc822 part string
    my $blanklines = 0;     # (Integer) The number of blank lines
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $statuspart = 0;     # (Integer) Flag, 1 = have got delivery status part.
    my $connvalues = 0;     # (Integer) Flag, 1 if all the value of $connheader have been set
    my $connheader = {
        'to'      => '',    # The value of "To"
        'date'    => '',    # The value of "Date"
        'subject' => '',    # The value of "Subject"
    };

    my $v = undef;

    for my $e ( @hasdivided ) {
        # Read each line between $Re1->{'begin'} and $Re1->{'rfc822'}.
        unless( $readcursor ) {
            # Beginning of the bounce message or delivery status part
            if( $e =~ $Re1->{'begin'} ) {
                $readcursor |= $Indicators->{'deliverystatus'};
                next;
            }
        }

        unless( $readcursor & $Indicators->{'message-rfc822'} ) {
            # Beginning of the original message part
            if( $e =~ $Re1->{'rfc822'} ) {
                $readcursor |= $Indicators->{'message-rfc822'};
                next;
            }
        }

        if( $readcursor & $Indicators->{'message-rfc822'} ) {
            # After "message/rfc822"
            unless( length $e ) {
                $blanklines++;
                last if $blanklines > 1;
                next;
            }
            push @$rfc822list, $e;

        } else {
            # Before "message/rfc822"
            next unless $readcursor & $Indicators->{'deliverystatus'};
            next if $statuspart;

            if( $connvalues == scalar( keys %$connheader ) ) {
                # did not reach the following recipient(s):
                # 
                # kijitora@example.co.jp on Thu, 29 Apr 2007 16:51:51 -0500
                #     The recipient name is not recognized
                #     The MTS-ID of the original message is: c=jp;a= ;p=neko
                # ;l=EXCHANGE000000000000000000
                #     MSEXCH:IMS:KIJITORA CAT:EXAMPLE:EXCHANGE 0 (000C05A6) Unknown Recipient
                # mikeneko@example.co.jp on Thu, 29 Apr 2007 16:51:51 -0500
                #     The recipient name is not recognized
                #     The MTS-ID of the original message is: c=jp;a= ;p=neko
                # ;l=EXCHANGE000000000000000000
                #     MSEXCH:IMS:KIJITORA CAT:EXAMPLE:EXCHANGE 0 (000C05A6) Unknown Recipient
                $v = $dscontents->[ -1 ];

                if( $e =~ m/\A[ \t]*([^ ]+[@][^ ]+) on[ \t]*.*\z/ ||
                    $e =~ m/\A[ \t]*.+(?:SMTP|smtp)=([^ ]+[@][^ ]+) on[ \t]*.*\z/ ) {
                    # kijitora@example.co.jp on Thu, 29 Apr 2007 16:51:51 -0500
                    #   kijitora@example.com on 4/29/99 9:19:59 AM
                    if( length $v->{'recipient'} ) {
                        # There are multiple recipient addresses in the message body.
                        push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                        $v = $dscontents->[ -1 ];
                    }
                    $v->{'recipient'} = $1;
                    $v->{'msexch'} = 0;
                    $recipients++;

                } elsif( $e =~ m/\A[ \t]+(MSEXCH:.+)\z/ ) {
                    #     MSEXCH:IMS:KIJITORA CAT:EXAMPLE:EXCHANGE 0 (000C05A6) Unknown Recipient
                    $v->{'diagnosis'} .= $1;

                } else {

                    next if $v->{'msexch'};
                    if( $v->{'diagnosis'} =~ m/\AMSEXCH:.+/ ) {
                        # Continued from MEEXCH in the previous line
                        $v->{'msexch'} = 1;
                        $v->{'diagnosis'} .= ' '.$e;
                        $statuspart = 1;

                    } else {
                        # Error message in the body part
                        $v->{'alterrors'} .= ' '.$e;
                    }
                }
            } else {
                # Your message
                #
                #  To:      shironeko@example.jp
                #  Subject: ...
                #  Sent:    Thu, 29 Apr 2010 18:14:35 +0000
                #
                if( $e =~ m/\A[ \t]+To:[ \t]+(.+)\z/ ) {
                    #  To:      shironeko@example.jp
                    next if length $connheader->{'to'};
                    $connheader->{'to'} = $1;
                    $connvalues++;

                } elsif( $e =~ m/\A[ \t]+Subject:[ \t]+(.+)\z/ ) {
                    #  Subject: ...
                    next if length $connheader->{'subject'};
                    $connheader->{'subject'} = $1;
                    $connvalues++;

                } elsif( $e =~ m/\A[ \t]+Sent:[ \t]+([A-Z][a-z]{2},.+[-+]\d{4})\z/ ||
                         $e =~ m|\A[ \t]+Sent:[ \t]+(\d+[/]\d+[/]\d+[ \t]+\d+:\d+:\d+[ \t].+)|) {
                    #  Sent:    Thu, 29 Apr 2010 18:14:35 +0000
                    #  Sent:    4/29/99 9:19:59 AM
                    next if length $connheader->{'date'};
                    $connheader->{'date'} = $1;
                    $connvalues++;
                }
            }
        } # End of if: rfc822
    }

    return undef unless $recipients;
    require Sisimai::String;
    require Sisimai::SMTP::Status;

    for my $e ( @$dscontents ) {
        $e->{'diagnosis'} = Sisimai::String->sweep( $e->{'diagnosis'} );

        if( $e->{'diagnosis'} =~ m{\AMSEXCH:.+[ \t]*[(]([0-9A-F]{8})[)][ \t]*(.*)\z} ) {
            #     MSEXCH:IMS:KIJITORA CAT:EXAMPLE:EXCHANGE 0 (000C05A6) Unknown Recipient
            my $capturedcode = $1;
            my $errormessage = $2;
            my $pseudostatus = '';

            for my $r ( keys %$CodeTable ) {
                # Find captured code from the error code table
                next unless grep { $capturedcode eq $_ } @{ $CodeTable->{ $r } };
                $e->{'reason'} = $r;
                $pseudostatus = Sisimai::SMTP::Status->code( $r );
                $e->{'status'} = $pseudostatus if length $pseudostatus;
                last;
            }
            $e->{'diagnosis'} = $errormessage;
        }

        unless( $e->{'reason'} ) {
            # Could not detect the reason from the value of "diagnosis".
            if( exists $e->{'alterrors'} && length $e->{'alterrors'} ) {
                # Copy alternative error message
                $e->{'diagnosis'} = $e->{'alterrors'}.' '.$e->{'diagnosis'};
                $e->{'diagnosis'} = Sisimai::String->sweep( $e->{'diagnosis'} );
                delete $e->{'alterrors'};
            }
        }
        $e->{'agent'}  = __PACKAGE__->smtpagent;
        delete $e->{'msexch'};
    }

    if( scalar(@$rfc822list) == 0 ) {
        # When original message does not included in the bounce message
        push @$rfc822list, sprintf( "From: %s", $connheader->{'to'} );
        push @$rfc822list, sprintf( "Date: %s", $connheader->{'date'} );
        push @$rfc822list, sprintf( "Subject: %s", $connheader->{'subject'} );
    }
    $rfc822part = Sisimai::RFC5322->weedout( $rfc822list );
    return { 'ds' => $dscontents, 'rfc822' => $$rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::MTA::Exchange - bounce mail parser class for C<Microsft Exchange
Server>.

=head1 SYNOPSIS

    use Sisimai::MTA::Exchange;

=head1 DESCRIPTION

Sisimai::MTA::Exchange parses a bounce email which created by C<Microsoft
Exchange Server>. Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::MTA::Exchange->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::MTA::Exchange->smtpagent;

=head2 C<B<scan( I<header data>, I<reference to body string>)>>

C<scan()> method parses a bounced email and return results as a array reference.
See Sisimai::Message for more details.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2016 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut
