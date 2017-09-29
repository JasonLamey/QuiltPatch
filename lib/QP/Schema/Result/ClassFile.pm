package QP::Schema::Result::ClassFile;

use base qw/DBIx::Class::Core/;

use DateTime;

__PACKAGE__->table( 'class_files' );

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
                          filename =>
                          {
                            datatype          => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          filetype =>
                          {
                            datatype          => 'enum',
                            is_nullable       => 0,
                            default_value     => 'image',
                            is_enum           => 1,
                            extra             =>
                            {
                              list => [ 'supply list', 'image' ],
                            },
                          },
                          created_on =>
                          {
                            datatype          => 'datetime',
                            is_nullable       => 0,
                            default_value     => DateTime->now( time_zone => 'America/New_York' )->datetime,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->belongs_to( class => 'QP::Schema::Result::ClassInfo', 'class_id' );

1;
