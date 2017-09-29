package QP::Schema::Result::NewsletterSession;

use base qw/DBIx::Class::Core/;

use DateTime;

__PACKAGE__->table( 'newsletter_sessions' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          session_name =>
                          {
                            datatype          => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          created_on =>
                          {
                            datatype          => 'datetime',
                            is_nullable       => 0,
                            default_value     => DateTime->now( time_zone => 'UTC' )->datetime,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

1;
