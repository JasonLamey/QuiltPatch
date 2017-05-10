package QP::Schema::Result::News;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'news' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          timestamp =>
                          {
                            data_type         => 'datetime',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          expires =>
                          {
                            data_type         => 'date',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          title =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          blurb =>
                          {
                            data_type         => 'text',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          article =>
                          {
                            data_type         => 'text',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          external_link =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          static =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          priority =>
                          {
                            data_type         => 'integer',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          news_type =>
                          {
                            data_type         => 'enum',
                            is_nullable       => 0,
                            default_value     => 'QP',
                            is_enum           => 1,
                            extra =>
                            {
                              list => [ qw/QP Bernina/ ]
                            },
                          },
                          user_account_id =>
                          {
                            datatype          => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );
