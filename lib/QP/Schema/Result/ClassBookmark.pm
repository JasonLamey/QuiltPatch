package QP::Schema::Result::ClassBookmark;

use strict;
use warnings;

# Third Party modules
use base 'DBIx::Class::Core';
our $VERSION = '1.0';


=head1 NAME

QP::Schema::Result::ClassBookmark


=head1 AUTHOR

Jason Lamey L<email:jasonlamey@gmail.com>


=head1 SYNOPSIS AND USAGE

This library represents the Class/User relationship mapping. Many-to-many.

=cut

__PACKAGE__->table( 'class_bookmarks' );
__PACKAGE__->add_columns(
                          class_id =>
                            {
                              data_type         => 'integer',
                              size              => 20,
                              is_nullable       => 0,
                            },
                          user_id =>
                            {
                              data_type         => 'integer',
                              size              => 20,
                              is_nullable       => 0,
                            },
                          created_at =>
                            {
                              data_type         => 'datetime',
                              is_nullable       => 0,
                              default_value     => DateTime->now( time_zone => 'UTC' )->datetime,
                            }
                        );

__PACKAGE__->set_primary_key( 'class_id', 'user_id' );

__PACKAGE__->belongs_to( 'class' => 'QP::Schema::Result::ClassInfo', 'class_id' );
__PACKAGE__->belongs_to( 'user'  => 'QP::Schema::Result::User',      'user_id' );


=head1 COPYRIGHT & LICENSE

Copyright 2017, Jason Lamey
All rights reserved.

=cut

1;
