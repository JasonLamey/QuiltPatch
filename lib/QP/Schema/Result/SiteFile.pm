package QP::Schema::Result::SiteFile;

use base qw/DBIx::Class::Core/;

use DateTime;

__PACKAGE__->table( 'site_files' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
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
                            default_value     => 'newsletter',
                            is_enum           => 1,
                            extra             =>
                            {
                              list => [ 'newsletter', 'image' ],
                            },
                          },
                          created_on =>
                          {
                            datatype          => 'datetime',
                            is_nullable       => 0,
                            default_value     => DateTime->now( time_zone => 'UTC' )->datetime,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

1;
