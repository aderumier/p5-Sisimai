package Sisimai::Lhost::SurfControl;
use parent 'Sisimai::Lhost';
use feature ':5.10';
use strict;
use warnings;

my $Indicators = __PACKAGE__->INDICATORS;
my $StartingOf = {
    'message' => ['Your message could not be sent.'],
    'rfc822'  => ['Content-Type: message/rfc822'],
};

# X-SEF-ZeroHour-RefID: fgs=000000000
# X-SEF-Processed: 0_0_0_000__2010_04_29_23_34_45
# X-Mailer: SurfControl E-mail Filter
sub headerlist  { return ['x-sef-processed', 'x-mailer'] }
sub description { 'WebSense SurfControl' }
sub make {
    # Detect an error from SurfControl
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
    # @since v4.1.2
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;

    # 'from'     => qr/ [(]Mail Delivery System[)]\z/,
    return undef unless $mhead->{'x-sef-processed'};
    return undef unless $mhead->{'x-mailer'};
    return undef unless $mhead->{'x-mailer'} eq 'SurfControl E-mail Filter';

    require Sisimai::RFC1894;
    my $fieldtable = Sisimai::RFC1894->FIELDTABLE;
    my $dscontents = [__PACKAGE__->DELIVERYSTATUS];
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822list = [];    # (Array) Each line in message/rfc822 part string
    my $blanklines = 0;     # (Integer) The number of blank lines
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $v = undef;
    my $p = '';

    for my $e ( split("\n", $$mbody) ) {
        # Read each line between the start of the message and the start of rfc822 part.
        unless( $readcursor ) {
            # Beginning of the bounce message or delivery status part
            if( $e eq $StartingOf->{'message'}->[0] ) {
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

            # Your message could not be sent.
            # A transcript of the attempts to send the message follows.
            # The number of attempts made: 1
            # Addressed To: kijitora@example.com
            #
            # Thu 29 Apr 2010 23:34:45 +0900
            # Failed to send to identified host,
            # kijitora@example.com: [192.0.2.5], 550 kijitora@example.com... No such user
            # --- Message non-deliverable.
            $v = $dscontents->[-1];

            if( $e =~ /\AAddressed To:[ \t]*([^ ]+?[@][^ ]+?)\z/ ) {
                # Addressed To: kijitora@example.com
                if( $v->{'recipient'} ) {
                    # There are multiple recipient addresses in the message body.
                    push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                    $v = $dscontents->[-1];
                }
                $v->{'recipient'} = $1;
                $recipients++;

            } elsif( $e =~ /\A(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat)[ \t,]/ ) {
                # Thu 29 Apr 2010 23:34:45 +0900
                $v->{'date'} = $e;

            } elsif( $e =~ /\A[^ ]+[@][^ ]+:[ \t]*\[(\d+[.]\d+[.]\d+[.]\d)\],[ \t]*(.+)\z/ ) {
                # kijitora@example.com: [192.0.2.5], 550 kijitora@example.com... No such user
                $v->{'rhost'} = $1;
                $v->{'diagnosis'} = $2;

            } else {
                # Fallback, parse RFC3464 headers.
                if( my $f = Sisimai::RFC1894->match($e) ) {
                    # $e matched with any field defined in RFC3464
                    next unless my $o = Sisimai::RFC1894->field($e);
                    next if $o->[0] eq 'final-recipient';
                    next unless exists $fieldtable->{ $o->[0] };
                    $v->{ $fieldtable->{ $o->[0] } } = $o->[2];

                } else {
                    # Continued line of the value of Diagnostic-Code field
                    next unless index($p, 'Diagnostic-Code:') == 0;
                    next unless $e =~ /\A[ \t]+(.+)\z/;
                    $v->{'diagnosis'} .= ' '.$1;
                }
            }
        } # End of error message part
    } continue {
        # Save the current line for the next loop
        $p = $e;
    }
    return undef unless $recipients;

    for my $e ( @$dscontents ) {
        $e->{'diagnosis'} = Sisimai::String->sweep($e->{'diagnosis'});
        $e->{'agent'}     = __PACKAGE__->smtpagent;
    }

    $rfc822part = Sisimai::RFC5322->weedout($rfc822list);
    return { 'ds' => $dscontents, 'rfc822' => $$rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Lhost::SurfControl - bounce mail parser class for C<SurfControl>.

=head1 SYNOPSIS

    use Sisimai::Lhost::SurfControl;

=head1 DESCRIPTION

Sisimai::Lhost::SurfControl parses a bounce email which created by
C<WebSense SurfControl>. Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::Lhost::SurfControl->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::Lhost::SurfControl->smtpagent;

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

