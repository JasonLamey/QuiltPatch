package QP::Schema::ResultSet::Class;

use Dancer2 appname => 'QP';

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

  warning sprintf( 'HAS_CURRENT_CLASSES COUNT = >%s<', $count );

  return ( $count // 0 );
}

1;
