package QP::Log;

use strict;
use warnings;

use Dancer2 appname => 'QP';

use Email::Valid;
use Try::Tiny;
use DateTime;
use Const::Fast;
use Data::Dumper;

use version; our $VERSION = qv( "v0.1.0" );

use QP::Schema;

const my $SCHEMA => QP::Schema->db_connect();
#$SCHEMA->storage->debug(1);   # UNCOMMENT IN ORDER TO DUMP SQL DEBUG MESSAGES TO LOGS


=head1 NAME

QP::Log


=head1 DESCRIPTION AND SYNOPSIS

This module handles critical logging functionality for Admin and non-Admin logs.

=cut


=head1 METHODS


=head2 admin_log()

=over 4

=item Input: hashref containing log data [C<admin_ip>, C<ip_address>, C<log_level>, C<log_message>].

=item Output: Boolean indicating success.

=back

    my $logged = QP::Log->admin_log( \%log_data );

=cut

sub admin_log
{
    my ( $self, %params ) = @_;

    my $admin       = delete $params{'admin'}       // undef;
    my $ip_address  = delete $params{'ip_address'}  // 'Unknown';
    my $log_level   = delete $params{'log_level'}   // 'Info';
    my $log_message = delete $params{'log_message'} // undef;

    if (
        not defined $admin
        or
        not defined $log_message
    )
    {
        error "Missing mandatory admin log info: admin >$admin< / log_message >$log_message<";
        return 0;
    }

    my $log = $SCHEMA->resultset( 'AdminLog' )->new(
                                                    {
                                                        admin       => $admin,
                                                        ip_address  => $ip_address,
                                                        log_level   => $log_level,
                                                        log_message => $log_message,
                                                        created_on  => DateTime->now( time_zone => 'UTC' )->datetime,
                                                    }
                                                   );
    $SCHEMA->txn_do( sub
                        {
                            $log->insert
                        }
    );

    return 1;
}


=head2 user_log()

=over 4

=item Input: hashref containing log data [C<admin_ip>, C<ip_address>, C<log_level>, C<log_message>].

=item Output: Boolean indicating success.

=back

    my $logged = QP::Log->user_log( \%log_data );

=cut

sub user_log
{
    my ( $self, %params ) = @_;

    my $user        = delete $params{'user'}        // undef;
    my $ip_address  = delete $params{'ip_address'}  // 'Unknown';
    my $log_level   = delete $params{'log_level'}   // 'Info';
    my $log_message = delete $params{'log_message'} // undef;

    if (
        not defined $user
        or
        not defined $log_message
    )
    {
        error "Missing mandatory user log info: user >$user< / log_message >$log_message<";
        return 0;
    }

    my $log = $SCHEMA->resultset( 'UserLog' )->new(
                                                    {
                                                        user        => $user,
                                                        ip_address  => $ip_address,
                                                        log_level   => $log_level,
                                                        log_message => $log_message,
                                                        created_on  => DateTime->now( time_zone => 'UTC' )->datetime,
                                                    }
                                                   );
    $SCHEMA->txn_do( sub
                        {
                            $log->insert
                        }
    );

    return 1;
}


=head2 find_changes_in_data()

=over 4

=item Input: hash of two data sets to compare [C<old_data>, C<new_data>].

=item Output: arrayref containing the data fields that have been changed, or undef if nothing.

=back

    my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

=cut

sub find_changes_in_data
{
    my ( $self, %params ) = @_;

    my $old_data = delete $params{'old_data'} // {};
    my $new_data = delete $params{'new_data'} // {};

    my @changes = ();

    foreach my $key ( sort keys %{ $old_data } )
    {
        if ( defined $new_data->{$key} )
        {
            if ( $old_data->{$key} ne $new_data->{$key} )
            {
                push( @changes, "$key: '$old_data->{$key}' -> '$new_data->{$key}'" );
            }
        }
        else
        {
            push( @changes, "$key: '$old_data->{$key}' -> undef" );
        }
    }

    return \@changes;
}


=head2 get_admin_logs()

=over 4

=item Input: hash of two items [C<page>, C<per_page>].

=item Output: An hashref containing a count of all records, and an array of all records to return.

=back

    my $logs = QP::Log->get_admin_logs( page => 1, per_page => 50 );

=cut

sub get_admin_logs
{
    my ( $self, %params ) = @_;

    my $page     = delete $params{'page'}     // 1;
    my $per_page = delete $params{'per_page'} // 50;
    my $order_by = delete $params{'order_by'} // 'created_on'; # field_name(s)

    my $log_count = $SCHEMA->resultset( 'AdminLog' )->search( undef )->count;

    my @logs = $SCHEMA->resultset( 'AdminLog' )->search(
                                                            undef,
                                                            {
                                                                order_by => { -desc => $order_by },
                                                                page     => $page,
                                                                rows     => $per_page,
                                                            },
                                                       );

    my %log_records = ( row_count => $log_count, logs => \@logs );

    return \%log_records;
}


=head2 get_user_logs()

=over 4

=item Input: hash of two items [C<page>, C<per_page>].

=item Output: An hashref containing a count of all records, and an array of all records to return.

=back

    my $logs = QP::Log->get_user_logs( page => 1, per_page => 50 );

=cut

sub get_user_logs
{
    my ( $self, %params ) = @_;

    my $page     = delete $params{'page'}     // 1;
    my $per_page = delete $params{'per_page'} // 50;
    my $order_by = delete $params{'order_by'} // 'created_on'; # field_name(s)

    my $log_count = $SCHEMA->resultset( 'UserLog' )->search( undef )->count;

    my @logs = $SCHEMA->resultset( 'UserLog' )->search(
                                                            undef,
                                                            {
                                                                order_by => { -desc => $order_by },
                                                                page     => $page,
                                                                rows     => $per_page,
                                                            },
                                                       );

    my %log_records = ( row_count => $log_count, logs => \@logs );

    return \%log_records;
}


1;
