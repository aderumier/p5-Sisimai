package Sisimai::Lhost::MailFoundry;
use parent 'Sisimai::Lhost';
use feature ':5.10';
use strict;
use warnings;

my $Indicators = __PACKAGE__->INDICATORS;
my $StartingOf = {
    'message' => ['This is a MIME encoded message'],
    'rfc822'  => ['Content-Type: message/rfc822'],
    'error'   => ['Delivery failed for the following reason:'],
};

sub description { 'MailFoundry' }
sub make {
    # Detect an error from MailFoundry
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

    return undef unless $mhead->{'subject'} eq 'Message delivery has failed';
    return undef unless grep { rindex($_, '(MAILFOUNDRY) id') > -1 } @{ $mhead->{'received'} };

    my $dscontents = [__PACKAGE__->DELIVERYSTATUS];
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822list = [];    # (Array) Each line in message/rfc822 part string
    my $blanklines = 0;     # (Integer) The number of blank lines
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $v = undef;

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

            # Unable to deliver message to: <kijitora@example.org>
            # Delivery failed for the following reason:
            # Server mx22.example.org[192.0.2.222] failed with: 550 <kijitora@example.org> No such user here
            #
            # This has been a permanent failure.  No further delivery attempts will be made.
            $v = $dscontents->[-1];

            if( $e =~ /\AUnable to deliver message to: [<]([^ ]+[@][^ ]+)[>]\z/ ) {
                # Unable to deliver message to: <kijitora@example.org>
                if( $v->{'recipient'} ) {
                    # There are multiple recipient addresses in the message body.
                    push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                    $v = $dscontents->[-1];
                }
                $v->{'recipient'} = $1;
                $recipients++;

            } else {
                # Error message
                if( $e eq $StartingOf->{'error'}->[0] ) {
                    # Delivery failed for the following reason:
                    $v->{'diagnosis'} = $e;

                } else {
                    # Detect error message
                    next unless length $e;
                    next unless $v->{'diagnosis'};
                    next if index($e, '-') == 0;

                    # Server mx22.example.org[192.0.2.222] failed with: 550 <kijitora@example.org> No such user here
                    $v->{'diagnosis'} .= ' '.$e;
                }
            }
        } # End of error message part
    }
    return undef unless $recipients;

    for my $e ( @$dscontents ) {
        # Set default values if each value is empty.
        $e->{'diagnosis'} = Sisimai::String->sweep($e->{'diagnosis'});
        $e->{'agent'}  = __PACKAGE__->smtpagent;
    }

    $rfc822part = Sisimai::RFC5322->weedout($rfc822list);
    return { 'ds' => $dscontents, 'rfc822' => $$rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Lhost::MailFoundry - bounce mail parser class for C<MailFoundry>.

=head1 SYNOPSIS

    use Sisimai::Lhost::MailFoundry;

=head1 DESCRIPTION

Sisimai::Lhost::MailFoundry parses a bounce email which created by C<MailFoundry>.
Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::Lhost::MailFoundry->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::Lhost::MailFoundry->smtpagent;

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

