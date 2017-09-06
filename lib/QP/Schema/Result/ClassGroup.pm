package QP::Schema::Result::ClassGroup;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'class_groups' );

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
                            datatype          => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          description =>
                          {
                            data_type         => 'text',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          footer_text =>
                          {
                            data_type         => 'text',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->has_many( subgroups => 'QP::Schema::Result::ClassSubgroup', 'class_group_id' );
__PACKAGE__->has_many( classes   => 'QP::Schema::Result::ClassInfo',     'class_group_id' );

1;
