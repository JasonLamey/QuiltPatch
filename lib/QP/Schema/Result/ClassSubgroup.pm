package QP::Schema::Result::ClassSubgroup;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'class_subgroups' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          class_group_id =>
                          {
                            datatype          => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                          },
                          subgroup =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          order_by =>
                          {
                            data_type         => 'integer',
                            size              => 2,
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->belongs_to( group   => 'QP::Schema::Result::ClassGroup', 'class_group_id' );
__PACKAGE__->has_many(   classes => 'QP::Schema::Result::Class',      'class_subgroup_id' );

1;
