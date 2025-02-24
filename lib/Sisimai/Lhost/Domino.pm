package Sisimai::Lhost::Domino;
use parent 'Sisimai::Lhost';
use feature ':5.10';
use strict;
use warnings;

my $Indicators = __PACKAGE__->INDICATORS;
my $StartingOf = {
    'message' => ['Your message'],
    'rfc822'  => ['Content-Type: message/delivery-status'],
};
my $MessagesOf = {
    'userunknown' => [
        'not listed in Domino Directory',
        'not listed in public Name & Address Book',
        'Domino ディレクトリには見つかりません',
    ],
    'filtered'    => ['Cannot route mail to user'],
    'systemerror' => ['Several matches found in Domino Directory'],
};

sub description { 'IBM Domino Server' }
sub make {
    # Detect an error from IBM Domino
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
    # @since v4.0.2
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;
    return undef unless index($mhead->{'subject'}, 'DELIVERY FAILURE:') == 0;

    my $dscontents = [__PACKAGE__->DELIVERYSTATUS];
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822list = [];    # (Array) Each line in message/rfc822 part string
    my $blanklines = 0;     # (Integer) The number of blank lines
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $subjecttxt = '';    # (String) The value of Subject:
    my $v = undef;
    my $p = '';

    for my $e ( split("\n", $$mbody) ) {
        # Read each line between the start of the message and the start of rfc822 part.
        next unless length $e;

        unless( $readcursor ) {
            # Beginning of the bounce message or delivery status part
            if( index($e, $StartingOf->{'message'}->[0]) == 0 ) {
                $readcursor |= $Indicators->{'deliverystatus'};
                next;
            }
        }

        unless( $readcursor & $Indicators->{'message-rfc822'} ) {
            # Beginning of the original message part
            if( index($e, $StartingOf->{'rfc822'}->[0]) == 0 ) {
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

            # Your message
            #
            #   Subject: Test Bounce
            #
            # was not delivered to:
            #
            #   kijitora@example.net
            #
            # because:
            #
            #   User some.name (kijitora@example.net) not listed in Domino Directory
            #
            $v = $dscontents->[-1];
            if( $e eq 'was not delivered to:' ) {
                # was not delivered to:
                if( $v->{'recipient'} ) {
                    # There are multiple recipient addresses in the message body.
                    push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                    $v = $dscontents->[-1];
                }
                $v->{'recipient'} ||= $e;
                $recipients++;

            } elsif( $e =~ /\A[ ][ ]([^ ]+[@][^ ]+)\z/ ) {
                # Continued from the line "was not delivered to:"
                #   kijitora@example.net
                $v->{'recipient'} = Sisimai::Address->s3s4($1);

            } elsif( $e eq 'because:' ) {
                # because:
                $v->{'diagnosis'} = $e;

            } else {
                if( exists $v->{'diagnosis'} && $v->{'diagnosis'} eq 'because:' ) {
                    # Error message, continued from the line "because:"
                    $v->{'diagnosis'} = $e;

                } elsif( $e =~ /\A[ ][ ]Subject: (.+)\z/ ) {
                    #   Subject: Nyaa
                    $subjecttxt = $1;
                }
            }
        } # End of if: rfc822
    }
    return undef unless $recipients;

    for my $e ( @$dscontents ) {
        $e->{'agent'}     = __PACKAGE__->smtpagent;
        $e->{'diagnosis'} = Sisimai::String->sweep($e->{'diagnosis'});
        $e->{'recipient'} = Sisimai::Address->s3s4($e->{'recipient'});

        for my $r ( keys %$MessagesOf ) {
            # Check each regular expression of Domino error messages
            next unless grep { index($e->{'diagnosis'}, $_) > -1 } @{ $MessagesOf->{ $r } };
            $e->{'reason'} = $r;
            $e->{'status'} = Sisimai::SMTP::Status->code($r, 0) || '';
            last;
        }
    }

    unless( grep { index($_, 'Subject:') == 0 } @$rfc822list ) {
        # Set the value of $subjecttxt as a Subject if there is no original
        # message in the bounce mail.
        push @$rfc822list, 'Subject: '.$subjecttxt;
    }

    $rfc822part = Sisimai::RFC5322->weedout($rfc822list);
    return { 'ds' => $dscontents, 'rfc822' => $$rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Lhost::Domino - bounce mail parser class for IBM Domino Server.

=head1 SYNOPSIS

    use Sisimai::Lhost::Domino;

=head1 DESCRIPTION

Sisimai::Lhost::Domino parses a bounce email which created by IBM Domino Server.
Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::Lhost::Domino->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::Lhost::Domino->smtpagent;

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
