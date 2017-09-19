package QP::Schema::Result::ClassTeacher;

use strict;
use warnings;

# Third Party modules
use base 'DBIx::Class::Core';
our $VERSION = '1.0';


=head1 NAME

QP::Schema::Result::ClassTeacher


=head1 AUTHOR

Jason Lamey L<email:jasonlamey@gmail.com>


=head1 SYNOPSIS AND USAGE

This library represents the Class/Teacher relationship mapping. Many-to-many.

=cut

__PACKAGE__->table( 'class_teachers' );
__PACKAGE__->add_columns(
                          class_id =>
                            {
                              data_type         => 'integer',
                              size              => 20,
                              is_nullable       => 0,
                            },
                          teacher_id =>
                            {
                              data_type         => 'integer',
                              size              => 20,
                              is_nullable       => 0,
                            },
                          sort_order =>
                            {
                              data_type         => 'integer',
                              size              => '1',
                              is_nullable       => 0,
                              default_value     => 1,
                            }
                        );

__PACKAGE__->set_primary_key( 'class_id', 'teacher_id' );

__PACKAGE__->belongs_to( 'class'   => 'QP::Schema::Result::ClassInfo', 'class_id' );
__PACKAGE__->belongs_to( 'teacher' => 'QP::Schema::Result::Teacher',   'teacher_id' );


=head1 COPYRIGHT & LICENSE

Copyright 2017, Jason Lamey
All rights reserved.

=cut

1;
