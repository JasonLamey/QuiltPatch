package QP;
use Dancer2;

use strict;
use warnings;

use Data::Dumper;
use Const::Fast;
use DateTime;
use URI::Escape::JavaScript;

use QP::Schema;

our $VERSION = '2.0';

const my $SCHEMA    => QP::Schema->db_connect();
const my $DT_PARSER => $SCHEMA->storage->datetime_parser;
const my $TODAY     => DateTime->today( time_zone => 'America/New_York' );
const my $NOW       => DateTime->now( time_zone => 'America/New_York' );

$SCHEMA->storage->debug(1); # Turns on DB debuging. Turn off for production.

get '/' => sub {
  my @news = $SCHEMA->resultset( 'News' )->search(
                                                  {
                                                    news_type => 'QP',
                                                    -or =>
                                                    [
                                                      expires => undef,
                                                      expires =>
                                                      {
                                                        '>=' => $DT_PARSER->format_datetime($TODAY)
                                                      },
                                                    ],
                                                  },
                                                  {
                                                    order_by => { -desc => 'timestamp' },
                                                    rows     => 5,
                                                  },
  );

  my @events = $SCHEMA->resultset( 'Event' )->search(
                                                  {
                                                    event_type   => 'Store Event',
                                                    end_datetime =>
                                                    {
                                                      '>=' => $DT_PARSER->format_datetime($TODAY)
                                                    },
                                                    is_private   => 'false',
                                                  },
                                                  {
                                                    order_by => { -asc => 'start_datetime' },
                                                  },
  );

  my @closings = $SCHEMA->resultset( 'Event' )->search(
                                                  {
                                                    event_type   => 'Closing',
                                                    end_datetime =>
                                                    {
                                                      '>=' => $DT_PARSER->format_datetime($TODAY)
                                                    },
                                                    is_private   => 'false',
                                                  },
                                                  {
                                                    order_by => { -asc => 'start_datetime' },
                                                  },
  );

  my $newsletter_rs = $SCHEMA->resultset( 'Newsletter' )->search(
                                                  undef,
                                                  {
                                                    order_by => { -desc => 'created_at' },
                                                  }
  );

  template 'index',
            {
              data =>
              {
                news       => \@news,
                events     => \@events,
                closings   => \@closings,
                newsletter => $newsletter_rs->first,
              },
            };
};

get '/calendar' => sub
{
  template 'calendar',
    { title => 'Events Calendar' };
};

any '/get_events/?:event_type?' => sub
{
  my $event_type = route_parameters->get( 'event_type' ) // undef;
  my $start      = body_parameters->get( 'start' )
                  // $TODAY->year() . '-' . $TODAY->month() . '-01';
  my $end        = body_parameters->get( 'end' )
                  // DateTime->last_day_of_month( year => $TODAY->year(), month => $TODAY->month() );
  if ( defined $event_type )
  {
    if (
        uc($event_type) ne 'STORE EVENT'
        and
        uc($event_type) ne 'CLOSING'
        and
        uc($event_type) ne 'BOOK CLUB'
        and
        uc($event_type) ne 'CLASS'
    )
    {
      $event_type = undef;
    }
  }

  my @events = ();

  if ( defined $event_type )
  {
    @events = $SCHEMA->resultset( 'Event' )->search(
                                                    {
                                                      start_datetime => { '>=' => $start },
                                                      end_datetime => { '<=' => $end },
                                                      event_type     => $event_type,
                                                    },
                                                    {
                                                      order_by => [ 'start_datetime' ],
                                                    }
    );
  }
  else
  {
    @events = $SCHEMA->resultset( 'Event' )->search(
                                                    {
                                                      start_datetime => { '>=' => $start },
                                                      end_datetime => { '<=' => $end },
                                                    },
                                                    {
                                                      order_by => [ 'start_datetime' ],
                                                    }
    );
  }

  my @json_events = ();
  foreach my $event ( @events )
  {
    my $start_dt = $event->start_datetime;
    my $end_dt   = $event->end_datetime;
    $start_dt =~ s/\s/T/;
    $end_dt   =~ s/\s/T/;
    push @json_events,
    {
      id          => $event->id,
      title       => $event->title,
      start       => $start_dt,
      end         => $end_dt,
      description => $event->description,
      event_type  => $event->event_type,
    };
  }

  return to_json( \@json_events );
};

get '/news/:news_type/:news_id' => sub
{
  my $news_type = route_parameters->get( 'news_type' ) // 'QP'; # QP or Bernina
  my $news_id   = route_parameters->get( 'news_id' )   // undef;

  if ( ! defined $news_id && $news_id < 1 )
  {
    redirect '/news/' . $news_type;
  }

  my $news_article = $SCHEMA->resultset( 'News')->find(
                                                        {
                                                          id => $news_id,
                                                        }
  );

  template 'news_article',
  {
    title => ( ( uc($news_type) eq 'BERNINA' ) ? 'Bernina' : 'Quilt Patch' )
              . ' News | ' . $news_article->title,
    data =>
    {
      news_article => $news_article,
    },
  };
};

get '/news/?:news_type?' => sub
{
  my $news_type = route_parameters->get( 'news_type' ) // 'QP'; # QP or Bernina

  my @news_articles = $SCHEMA->resultset( 'News' )->search(
                                                            {
                                                              news_type => $news_type,
                                                            },
                                                            {
                                                              order_by => { -desc => 'timestamp' },
                                                            }
  );

  template 'news',
  {
    title => ( ( uc($news_type) eq 'BERNINA' ) ? 'Bernina' : 'Quilt Patch' ) . ' News',
    data  =>
    {
      news_type => $news_type,
      news => \@news_articles,
    }
  };
};

get '/classes/:group_id' => sub
{
  my $group_id = route_parameters->get( 'group_id' ) // undef;

  if
  (
    ! defined $group_id
    or
    $group_id =~ /\D/
  )
  {
    redirect '/classes';
  }

  my $class_group     = $SCHEMA->resultset( 'ClassGroup' )->find( $group_id );

  if ( ! defined $class_group )
  {
    redirect '/classes';
  }

  my @class_subgroups = $class_group->search_related(
                                                      'subgroups',
                                                      undef,
                                                      {
                                                        order_by => { -asc => 'order_by' },
                                                      },
  );

  my @classes = $SCHEMA->resultset( 'Class' )->search(
                                                      {
                                                        'me.class_group_id' => $group_id,
                                                        'dates.date' => { '>=' => $TODAY->ymd },
                                                      },
                                                      {
                                                        prefetch =>
                                                        [
                                                          'dates',
                                                        ],
                                                        order_by =>
                                                        {
                                                          -asc => [ 'title' ],
                                                        }
                                                      },
  );

  if ( scalar( @class_subgroups ) > 0 )
  {
    @classes =
      sort
      {
        $a->subgroup->order_by <=> $b->subgroup->order_by
        ||
        $a->title cmp $b->title
      } @classes;
  }

  template 'classes_list',
  {
    title => sprintf( 'Classes | %s', $class_group->name ),
    data =>
    {
      class_group     => $class_group,
      class_subgroups => \@class_subgroups,
      classes         => \@classes,
    }
  };
};

get '/classes' => sub
{
  template 'classes',
  {
    title => 'Classes',
  };
};

true;
