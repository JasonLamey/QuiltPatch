package QP::Schema::Result::Newsletter;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'newsletters' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          title =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          body =>
                          {
                            data_type         => 'text',
                            is_nullable       => 0,
                          },
                          postscript =>
                          {
                            data_type         => 'text',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          created_at =>
                          {
                            data_type         => 'datetime',
                            is_nullable       => 0,
                            default_value     => '0000-00-00 00:00:00',
                          },
                          updated_at =>
                          {
                            data_type         => 'timestamp',
                            is_nullable       => 0,
                            default_value     => 'current_timestamp()',
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

1;
