package QP::Schema::Result::Event;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'calendar_events' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          user_account_id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                          },
                          title =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          description =>
                          {
                            data_type         => 'text',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          start_datetime =>
                          {
                            data_type         => 'datetime',
                            is_nullable       => 0,
                            default_value     => '0000-00-00 00:00:00',
                          },
                          end_datetime =>
                          {
                            data_type         => 'datetime',
                            is_nullable       => 0,
                            default_value     => '0000-00-00 00:00:00',
                          },
                          is_private =>
                          {
                            data_type         => 'enum',
                            is_nullable       => 1,
                            default_value     => 'true',
                            is_enum           => 1,
                            extra =>
                            {
                              list => [ qw/true false/ ]
                            },
                          },
                          event_type =>
                          {
                            data_type         => 'enum',
                            is_nullable       => 0,
                            default_value     => 'Store Event',
                            is_enum           => 1,
                            extra =>
                            {
                              list => [ 'Store Event', 'Closing', 'Class', 'Book Club' ]
                            },
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );
