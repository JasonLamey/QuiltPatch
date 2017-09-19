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

__PACKAGE__->has_many( 'classteachers' => 'QP::Schema::Result::ClassTeacher', 'teacher_id' );

__PACKAGE__->many_to_many( 'classes'   => 'classteachers', 'class', { order_by => { -asc => 'title' } } );

1;
