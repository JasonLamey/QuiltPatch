package QP::Schema::Result::ClassDate;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'class_dates' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          class_id =>
                          {
                            datatype          => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                          },
                          date =>
                          {
                            datatype          => 'date',
                            size              => 20,
                            is_nullable       => 0,
                            default_value     => '0000-00-00',
                          },
                          start_time1 =>
                          {
                            datatype          => 'time',
                            size              => 20,
                            is_nullable       => 0,
                            default_value     => '00:00:00',
                          },
                          end_time1 =>
                          {
                            datatype          => 'time',
                            size              => 20,
                            is_nullable       => 0,
                            default_value     => '00:00:00',
                          },
                          start_time2 =>
                          {
                            datatype          => 'time',
                            size              => 20,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          end_time2 =>
                          {
                            datatype          => 'time',
                            size              => 20,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          session =>
                          {
                            datatype          => 'varchar',
                            size              => 50,
                            is_nullable       => 0,
                          },
                          date_group =>
                          {
                            datatype          => 'varchar',
                            size              => 50,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          date_group_order =>
                          {
                            data_type         => 'integer',
                            size              => 2,
                            is_nullable       => 0,
                            default_value     => undef,
                          },
                          is_holiday =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->belongs_to( class => 'QP::Schema::Result::ClassInfo', 'class_id' );

1;
