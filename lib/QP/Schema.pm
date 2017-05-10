package QP::Schema;
use base qw/DBIx::Class::Schema/;

use strict;
use warnings;

use Const::Fast;
our $VERSION = "1.0";


=head1 NAME

QP::Schema


=head1 AUTHOR

Jason Lamey L<email:jasonlamey@gmail.com>


=head1 SYNOPSIS AND USAGE

Database schema for the QP app, using DBIx::Class.

=cut

const my $DB_NAME => 'dbi:mysql:quiltpatch';
const my $DB_USER => 'quiltpatch';
const my $DB_PASS => 'st1tchT1me';

__PACKAGE__->load_namespaces();


=head1 METHODS


=head2 db_connect()

Returns a DBIx::Class::Schema object for the QP DB.

=over 4

=item Input: None

=item Output: DBIx::Class::Schema object.

=back

    my $schema = QP::Schema->db_connect();

=cut

sub db_connect
{
  my ( $self ) = @_;

  return __PACKAGE__->connect(
                              $DB_NAME,
                              $DB_USER,
                              $DB_PASS,
                              {
                                  PrintError => 1,
                                  RaiseError => 1,
                                  ChopBlanks => 1,
                                  ShowErrorStatement => 1,
                                  AutoCommit => 1,
                              },
                          );
}


=head1 COPYRIGHT & LICENSE

Copyright 2017, Perl Poet
All rights reserved.

=cut

1;
