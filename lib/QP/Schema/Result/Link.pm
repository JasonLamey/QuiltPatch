package QP::Schema::Result::Link;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'links' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          link_group_id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                          },
                          name =>
                          {
                            datatype          => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          url =>
                          {
                            datatype          => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          show_url =>
                          {
                            datatype          => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->belongs_to( link_group => 'QP::Schema::Result::LinkGroup', 'link_group_id' );

1;
