package QP::Schema::Result::ClassInfo;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'classes' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 8,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          class_group_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 0,
                          },
                          class_subgroup_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
                          },
                          teacher_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
                          },
                          secondary_teacher_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
                          },
                          tertiary_teacher_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
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
                            is_nullable       => 0,
                            default_value     => undef,
                          },
                          num_sessions =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          fee =>
                          {
                            data_type         => 'varchar',
                            size              => 100,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          skill_level =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          is_also_embroidery =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 1,
                            default_value     => 0,
                          },
                          is_also_club =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 1,
                            default_value     => 0,
                          },
                          show_club =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          image_filename =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          supply_list_filename =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          no_supply_list =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          always_show =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          anchor =>
                          {
                            data_type         => 'varchar',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          is_new =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->belongs_to( teacher     => 'QP::Schema::Result::Teacher',       'teacher_id' );
__PACKAGE__->belongs_to( teacher2    => 'QP::Schema::Result::Teacher',       'secondary_teacher_id' );
__PACKAGE__->belongs_to( teacher3    => 'QP::Schema::Result::Teacher',       'tertiary_teacher_id' );
__PACKAGE__->belongs_to( class_group => 'QP::Schema::Result::ClassGroup',    'class_group_id' );
__PACKAGE__->belongs_to( subgroup    => 'QP::Schema::Result::ClassSubgroup', 'class_subgroup_id' );

__PACKAGE__->has_many( dates => 'QP::Schema::Result::ClassDate', 'class_id' );

1;
