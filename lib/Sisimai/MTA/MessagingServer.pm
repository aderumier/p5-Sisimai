package Sisimai::MTA::MessagingServer;
use parent 'Sisimai::MTA';
use feature ':5.10';
use strict;
use warnings;

my $Re0 = {
    'subject'  => qr/\ADelivery Notification: /,
    'received' => qr/[ ][(]MessagingServer[)][ ]with[ ]/,
    'boundary' => qr/Boundary_[(]ID_.+[)]/,
};
my $Re1 = {
    'begin'    => qr/\AThis report relates to a message you sent with the following header fields:/,
    'endof'    => qr/\A__END_OF_EMAIL_MESSAGE__\z/,
    'rfc822'   => qr!\A(?:Content-type:[ \t]*message/rfc822|Return-path:[ \t]*)!x,
};

my $ReFailure = {
    'hostunknown' => qr{Illegal[ ]host/domain[ ]name[ ]found}x,
};

my $Indicators = __PACKAGE__->INDICATORS;
my $LongFields = Sisimai::RFC5322->LONGFIELDS;
my $RFC822Head = Sisimai::RFC5322->HEADERFIELDS;

sub description { 'Oracle Communications Messaging Server' }
sub smtpagent   { 'MessagingServer' }
sub pattern     { return $Re0 }

sub scan {
    # Detect an error from Oracle Communications Messaging Server
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
    # @since v4.1.3
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;
    my $match = 0;

    $match ||= 1 if $mhead->{'content-type'} =~ $Re0->{'boundary'};
    $match ||= 1 if $mhead->{'subject'}      =~ $Re0->{'subject'};
    return undef unless $match;

    require Sisimai::Address;
    my $dscontents = []; push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
    my @hasdivided = split( "\n", $$mbody );
    my $rfc822next = { 'from' => 0, 'to' => 0, 'subject' => 0 };
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $previousfn = '';    # (String) Previous field name
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
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
            if( $e =~ m/\A([-0-9A-Za-z]+?)[:][ ]*.+\z/ ) {
                # Get required headers only
                my $lhs = lc $1;
                $previousfn = '';
                next unless exists $RFC822Head->{ $lhs };

                $previousfn  = $lhs;
                $rfc822part .= $e."\n";

            } elsif( $e =~ m/\A[ \t]+/ ) {
                # Continued line from the previous line
                next if $rfc822next->{ $previousfn };
                $rfc822part .= $e."\n" if exists $LongFields->{ $previousfn };

            } else {
                # Check the end of headers in rfc822 part
                next unless exists $LongFields->{ $previousfn };
                next if length $e;
                $rfc822next->{ $previousfn } = 1;
            }

        } else {
            # Before "message/rfc822"
            next unless $readcursor & $Indicators->{'deliverystatus'};
            next unless length $e;

            # --Boundary_(ID_0000000000000000000000)
            # Content-type: text/plain; charset=us-ascii
            # Content-language: en-US
            # 
            # This report relates to a message you sent with the following header fields:
            # 
            #   Message-id: <CD8C6134-C312-41D5-B083-366F7FA1D752@me.example.com>
            #   Date: Fri, 21 Nov 2014 23:34:45 +0900
            #   From: Shironeko <shironeko@me.example.com>
            #   To: kijitora@example.jp
            #   Subject: Nyaaaaaaaaaaaaaaaaaaaaaan
            # 
            # Your message cannot be delivered to the following recipients:
            # 
            #   Recipient address: kijitora@example.jp
            #   Reason: Remote SMTP server has rejected address
            #   Diagnostic code: smtp;550 5.1.1 <kijitora@example.jp>... User Unknown
            #   Remote system: dns;mx.example.jp (TCP|17.111.174.67|47323|192.0.2.225|25) (6jo.example.jp ESMTP SENDMAIL-VM)
            $v = $dscontents->[ -1 ];

            if( $e =~ m/\A[ \t]+Recipient address:[ \t]*([^ ]+[@][^ ]+)\z/ ) {
                #   Recipient address: kijitora@example.jp
                if( length $v->{'recipient'} ) {
                    # There are multiple recipient addresses in the message body.
                    push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                    $v = $dscontents->[ -1 ];
                }
                $v->{'recipient'} = Sisimai::Address->s3s4( $1 );
                $recipients++;

            } elsif( $e =~ m/\A[ \t]+Original address:[ \t]*([^ ]+[@][^ ]+)\z/ ) {
                #   Original address: kijitora@example.jp
                $v->{'recipient'} = Sisimai::Address->s3s4( $1 );

            } elsif( $e =~ m/\A[ \t]+Date:[ \t]*(.+)\z/ ) {
                #   Date: Fri, 21 Nov 2014 23:34:45 +0900
                $v->{'date'} = $1;

            } elsif( $e =~ m/\A[ \t]+Reason:[ \t]*(.+)\z/ ) {
                #   Reason: Remote SMTP server has rejected address
                $v->{'diagnosis'} = $1;

            } elsif( $e =~ m/\A[ \t]+Diagnostic code:[ \t]*([^ ]+);(.+)\z/ ) {
                #   Diagnostic code: smtp;550 5.1.1 <kijitora@example.jp>... User Unknown
                $v->{'spec'} = uc $1;
                $v->{'diagnosis'} = $2;

            } elsif( $e =~ m/\A[ \t]+Remote system:[ \t]*dns;([^ ]+)[ \t]*([^ ]+)[ \t]*.+\z/ ) {
                #   Remote system: dns;mx.example.jp (TCP|17.111.174.67|47323|192.0.2.225|25)
                #     (6jo.example.jp ESMTP SENDMAIL-VM)
                my $remotehost = $1; # remote host
                my $sessionlog = $2; # smtp session
                $v->{'rhost'} = $remotehost;

                if( $sessionlog =~ m/\A[(]TCP|(.+)|\d+|(.+)|\d+[)]/ ) {
                    # The value does not include ".", use IP address instead.
                    # (TCP|17.111.174.67|47323|192.0.2.225|25)
                    $v->{'lhost'} = $1;
                    $v->{'rhost'} = $2 unless $remotehost =~ m/[^.]+[.][^.]+/;
                }

            } else {
                # Original-envelope-id: 0NFC009FLKOUVMA0@mr21p30im-asmtp004.me.com
                # Reporting-MTA: dns;mr21p30im-asmtp004.me.com (tcp-daemon)
                # Arrival-date: Thu, 29 Apr 2014 23:34:45 +0000 (GMT)
                # 
                # Original-recipient: rfc822;kijitora@example.jp
                # Final-recipient: rfc822;kijitora@example.jp
                # Action: failed
                # Status: 5.1.1 (Remote SMTP server has rejected address)
                # Remote-MTA: dns;mx.example.jp (TCP|17.111.174.67|47323|192.0.2.225|25)
                #  (6jo.example.jp ESMTP SENDMAIL-VM)
                # Diagnostic-code: smtp;550 5.1.1 <kijitora@example.jp>... User Unknown
                #
                if( $e =~ m/\A[Ss]tatus:[ \t]*(\d[.]\d[.]\d)[ \t]*[(](.+)[)]\z/ ) {
                    # Status: 5.1.1 (Remote SMTP server has rejected address)
                    $v->{'status'} = $1;
                    $v->{'diagnosis'} ||= $2;

                } elsif( $e =~ m/\A[Aa]rrival-[Dd]ate:[ ]*(.+)\z/ ) {
                    # Arrival-date: Thu, 29 Apr 2014 23:34:45 +0000 (GMT)
                    $v->{'date'} ||= $1;

                } elsif( $e =~ m/\A[Rr]eporting-MTA:[ ]*(?:DNS|dns);[ ]*(.+)\z/ ) {
                    # Reporting-MTA: dns;mr21p30im-asmtp004.me.com (tcp-daemon)
                    my $localhost = $1;
                    $v->{'lhost'} ||= $localhost;
                    $v->{'lhost'}   = $localhost unless $v->{'lhost'} =~ m/[^.]+[.][^ ]+/;
                }
            }
        } # End of if: rfc822
    }

    return undef unless $recipients;
    require Sisimai::String;
    require Sisimai::SMTP::Status;

    for my $e ( @$dscontents ) {
        $e->{'agent'} = __PACKAGE__->smtpagent;

        if( scalar @{ $mhead->{'received'} } ) {
            # Get localhost and remote host name from Received header.
            my $r = $mhead->{'received'};
            $e->{'lhost'} ||= shift @{ Sisimai::RFC5322->received( $r->[0] ) };
            $e->{'rhost'} ||= pop @{ Sisimai::RFC5322->received( $r->[-1] ) };
        }
        $e->{'diagnosis'} = Sisimai::String->sweep( $e->{'diagnosis'} );

        SESSION: for my $r ( keys %$ReFailure ) {
            # Verify each regular expression of session errors
            next unless $e->{'diagnosis'} =~ $ReFailure->{ $r };
            $e->{'reason'} = $r;
            last;
        }

        if( length( $e->{'status'} ) == 0 || $e->{'status'} =~ m/\A\d[.]0[.]0\z/ ) {
            # There is no value of Status header or the value is 5.0.0, 4.0.0
            my $pseudostatus = Sisimai::SMTP::Status->find( $e->{'diagnosis'} );
            $e->{'status'} = $pseudostatus if length $pseudostatus;
        }

        $e->{'action'} = 'failed' if $e->{'status'} =~ m/\A[45]/;
    }

    return { 'ds' => $dscontents, 'rfc822' => $rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::MTA::MessagingServer - bounce mail parser class for C<Sun Java System 
Messaging Server> and C<Oracle Communications Messaging Server>.

=head1 SYNOPSIS

    use Sisimai::MTA::MessagingServer;

=head1 DESCRIPTION

Sisimai::MTA::MessagingServer parses a bounce email which created by C<Oracle 
Communications Messaging Server> and C<Sun Java System Messaging Server>.
Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::MTA::MessagingServer->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::MTA::MessagingServer->smtpagent;

=head2 C<B<scan( I<header data>, I<reference to body string>)>>

C<scan()> method parses a bounced email and return results as a array reference.
See Sisimai::Message for more details.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2015 azumakuniyuki E<lt>perl.org@azumakuniyuki.orgE<gt>,
All Rights Reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut

