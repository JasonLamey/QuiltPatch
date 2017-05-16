package QP::Schema::Result::Teacher;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'teachers' );

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
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->has_many( classes => 'QP::Schema::Result::Class', 'teacher_id' );
__PACKAGE__->has_many( classes => 'QP::Schema::Result::Class', 'secondary_teacher_id' );
__PACKAGE__->has_many( classes => 'QP::Schema::Result::Class', 'tertiary_teacher_id' );

1;
