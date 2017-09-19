package QP::Schema::Result::UserRole;

use strict;
use warnings;

# Third Party modules
use base 'DBIx::Class::Core';
our $VERSION = '1.0';


=head1 NAME

QP::Schema::Result::UserRole


=head1 AUTHOR

Jason Lamey L<email:jasonlamey@gmail.com>


=head1 SYNOPSIS AND USAGE

This library represents the User/Role relationships.

=cut

__PACKAGE__->table( 'user_roles' );
__PACKAGE__->add_columns(
                          user_id =>
                            {
                              data_type         => 'integer',
                              size              => 20,
                              is_nullable       => 0,
                            },
                          role_id =>
                            {
                              data_type         => 'integer',
                              size              => 20,
                              is_nullable       => 0,
                            },
                        );

__PACKAGE__->set_primary_key( 'user_id', 'role_id' );

__PACKAGE__->belongs_to( 'user' => 'QP::Schema::Result::User', 'user_id' );
__PACKAGE__->belongs_to( 'role' => 'QP::Schema::Result::Role', 'role_id' );


=head1 METHODS


=head2 method_name()

This is a description of the method and what it does.

=over 4

=item Input: A description of what the method expects.

=item Output: A description of what the method returns.

=back

  $var = QP::PackageName->method_name();

=cut

sub method_name
{
}


=head1 COPYRIGHT & LICENSE

Copyright 2017, Jason Lamey
All rights reserved.

=cut

1;
