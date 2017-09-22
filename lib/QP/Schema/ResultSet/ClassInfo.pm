package QP::Schema::ResultSet::ClassInfo;

use strict;
use warnings;

use QP::Schema;

use parent 'DBIx::Class::ResultSet';

use DateTime;

sub has_upcoming_classes
{
  my $self = shift;
  my $today = DateTime->today;

  return 1 if $self->always_show == 1;

  my $count = $self->search_related( 'dates',
    {
      'date' => { '>=' => $today->ymd },
    }
  )->count;

  #debug sprintf( 'HAS_CURRENT_CLASSES COUNT = >%s<', $count );

  return ( $count // 0 );
}

sub next_upcoming_date
{
  my $self = shift;
  my $today = DateTime->today;

  my $upcoming = $self->search_related( 'dates',
    {
      'date' => { '>=' => $today->ymd }
    },
    {
      order_by => { -asc => [ 'date', 'start_time1' ] },
      rows     => 1,
    }
  )->single();

  warn sprintf( 'NEXT-UPCOMING-DATE: %s', $upcoming->date );

  return $upcoming;
}

1;
