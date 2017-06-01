package QP::Schema::Result::ContactUs;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'contact_us' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          username =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          full_name =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                            default_value     => undef,
                          },
                          email =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                            default_value     => undef,
                          },
                          comments =>
                          {
                            data_type         => 'text',
                            is_nullable       => 0,
                            default_value     => undef,
                          },
                          created_at =>
                          {
                            data_type         => 'datetime',
                            is_nullable       => 0,
                            default_value     => 'CURRENT_DATETIME()',
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

1;
