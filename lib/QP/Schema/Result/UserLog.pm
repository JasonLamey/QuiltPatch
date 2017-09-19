package QP::Schema::Result::UserLog;

use base 'DBIx::Class::Core';

use strict;
use warnings;

use DateTime;
use version; our $VERSION = qv( "v0.1.0" );


=head1 NAME

QP::Schema::Result::UserLog


=head1 DESCRIPTION AND USAGE

Database object representing UserLog entries within the web app.

=cut

__PACKAGE__->table( 'user_logs' );
__PACKAGE__->add_columns(
                            id =>
                                {
                                    accessor          => 'user_log',
                                    data_type         => 'integer',
                                    size              => 20,
                                    is_nullable       => 0,
                                    is_auto_increment => 1,
                                },
                            user =>
                                {
                                    data_type         => 'varchar',
                                    size              => 20,
                                    is_nullable       => 0,
                                },
                            ip_address =>
                                {
                                    data_type         => 'varchar',
                                    size              => 255,
                                    is_nullable       => 0,
                                },
                            log_level =>
                                {
                                    data_type         => 'enum',
                                    default_value     => 'Info',
                                    is_nullable       => 0,
                                    is_enum           => 1,
                                    extra =>
                                    {
                                      list => [ 'Info', 'Warning', 'Error', 'Debug' ]
                                    },
                                },
                            log_message =>
                                {
                                    data_type         => 'text',
                                    is_nullable       => 0,
                                },
                            created_on =>
                                {
                                    data_type         => 'DateTime',
                                    is_nullable       => 0,
                                    default_value     => DateTime->now( time_zone => 'UTC' )->datetime,
                                },
                        );

__PACKAGE__->set_primary_key( 'id' );

# QP::Admin->has_many( somethings => 'Object::Package' );


=head1 AUTHOR

Jason Lamey E<lt>jasonlamey@gmail.comE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright 2017 by Jason Lamey

This library is for use by QP. It is not intended for redistribution
or use by other parties without express written permission.

=cut

1;
