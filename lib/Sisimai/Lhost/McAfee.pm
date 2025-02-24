package Sisimai::Lhost::McAfee;
use parent 'Sisimai::Lhost';
use feature ':5.10';
use strict;
use warnings;

my $Indicators = __PACKAGE__->INDICATORS;
my $StartingOf = {
    'message' => ['--- The following addresses had delivery problems ---'],
    'rfc822'  => ['Content-Type: message/rfc822'],
};
my $ReFailures = {
    'userunknown' => qr{(?:
         [ ]User[ ][(].+[@].+[)][ ]unknown[.][ ]
        |550[ ]Unknown[ ]user[ ][^ ]+[@][^ ]+
        |550[ ][<].+?[@].+?[>][.]+[ ]User[ ]not[ ]exist
        |No[ ]such[ ]user
        )
    }x,
};

# X-NAI-Header: Modified by McAfee Email and Web Security Virtual Appliance
sub headerlist  { return ['x-nai-header'] }
sub description { 'McAfee Email Appliance' }
sub make {
    # Detect an error from McAfee
    # @param         [Hash] mhead       Message headers of a bounce email
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

    return undef unless defined $mhead->{'x-nai-header'};
    return undef unless index($mhead->{'x-nai-header'}, 'Modified by McAfee') > -1;
    return undef unless $mhead->{'subject'} eq 'Delivery Status';

    require Sisimai::RFC1894;
    my $fieldtable = Sisimai::RFC1894->FIELDTABLE;
    my $dscontents = [__PACKAGE__->DELIVERYSTATUS];
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822list = [];    # (Array) Each line in message/rfc822 part string
    my $blanklines = 0;     # (Integer) The number of blank lines
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $diagnostic = '';    # (String) Alternative diagnostic message
    my $v = undef;
    my $p = '';

    for my $e ( split("\n", $$mbody) ) {
        # Read each line between the start of the message and the start of rfc822 part.
        unless( $readcursor ) {
            # Beginning of the bounce message or delivery status part
            if( index($e, $StartingOf->{'message'}->[0]) > -1 ) {
                $readcursor |= $Indicators->{'deliverystatus'};
                next;
            }
        }

        unless( $readcursor & $Indicators->{'message-rfc822'} ) {
            # Beginning of the original message part
            if( $e eq $StartingOf->{'rfc822'}->[0] ) {
                $readcursor |= $Indicators->{'message-rfc822'};
                next;
            }
        }

        if( $readcursor & $Indicators->{'message-rfc822'} ) {
            # Inside of the original message part
            unless( length $e ) {
                last if ++$blanklines > 1;
                next;
            }
            push @$rfc822list, $e;

        } else {
            # Error message part
            next unless $readcursor & $Indicators->{'deliverystatus'};
            next unless length $e;

            # Content-Type: text/plain; name="deliveryproblems.txt"
            #
            #    --- The following addresses had delivery problems ---
            #
            # <user@example.com>   (User unknown user@example.com)
            #
            # --------------Boundary-00=_00000000000000000000
            # Content-Type: message/delivery-status; name="deliverystatus.txt"
            #
            $v = $dscontents->[-1];

            if( $e =~ /\A[<]([^ ]+[@][^ ]+)[>][ \t]+[(](.+)[)]\z/ ) {
                # <kijitora@example.co.jp>   (Unknown user kijitora@example.co.jp)
                if( $v->{'recipient'} ) {
                    # There are multiple recipient addresses in the message body.
                    push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                    $v = $dscontents->[-1];
                }
                $v->{'recipient'} = $1;
                $diagnostic = $2;
                $recipients++;

            } elsif( my $f = Sisimai::RFC1894->match($e) ) {
                # $e matched with any field defined in RFC3464
                my $o = Sisimai::RFC1894->field($e);
                unless( $o ) {
                    # Fallback code for empty value or invalid formatted value
                    # - Original-Recipient: <kijitora@example.co.jp>
                    $v->{'alias'} = Sisimai::Address->s3s4($1) if $e =~ /\AOriginal-Recipient:[ ]*([^ ]+)\z/;
                    next;
                }
                next unless exists $fieldtable->{ $o->[0] };
                $v->{ $fieldtable->{ $o->[0] } } = $o->[2];

            } else {
                # Continued line of the value of Diagnostic-Code field
                next unless index($p, 'Diagnostic-Code:') == 0;
                next unless $e =~ /\A[ \t]+(.+)\z/;
                $v->{'diagnosis'} .= ' '.$1;
            }
        } # End of error message part
    } continue {
        # Save the current line for the next loop
        $p = $e;
    }
    return undef unless $recipients;

    for my $e ( @$dscontents ) {
        $e->{'agent'}     = __PACKAGE__->smtpagent;
        $e->{'diagnosis'} = Sisimai::String->sweep($e->{'diagnosis'} || $diagnostic);

        SESSION: for my $r ( keys %$ReFailures ) {
            # Verify each regular expression of session errors
            next unless $e->{'diagnosis'} =~ $ReFailures->{ $r };
            $e->{'reason'} = $r;
            last;
        }
    }

    $rfc822part = Sisimai::RFC5322->weedout($rfc822list);
    return { 'ds' => $dscontents, 'rfc822' => $$rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Lhost::McAfee - bounce mail parser class for C<McAfee Email Appliance>.

=head1 SYNOPSIS

    use Sisimai::Lhost::McAfee;

=head1 DESCRIPTION

Sisimai::Lhost::McAfee parses a bounce email which created by
C<McAfee Email Appliance>.
Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::Lhost::McAfee->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::Lhost::McAfee->smtpagent;

=head2 C<B<make(I<header data>, I<reference to body string>)>>

C<make()> method parses a bounced email and return results as a array reference.
See Sisimai::Message for more details.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2019 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut

