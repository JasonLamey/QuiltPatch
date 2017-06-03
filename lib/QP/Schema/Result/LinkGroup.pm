package QP::Schema::Result::LinkGroup;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'link_groups' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          name =>
                          {
                            datatype          => 'varhcar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          order_by =>
                          {
                            datatype          => 'integer',
                            size              => 2,
                            is_nullable       => 0,
                            default_value     => 1,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->has_many( links => 'QP::Schema::Result::Link', 'link_group_id' );

1;
