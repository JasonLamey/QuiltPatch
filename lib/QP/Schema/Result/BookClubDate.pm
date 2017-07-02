package QP::Schema::Result::BookClubDate;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table( 'book_club_dates' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 20,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          book =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          author =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          date =>
                          {
                            datatype          => 'date',
                            is_nullable       => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

1;
