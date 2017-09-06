package QP;
use Dancer2;
use Dancer2::Session::Cookie;
use Dancer2::Plugin::Flash;
use Dancer2::Plugin::DBIC;
use Dancer2::Plugin::Auth::Extensible;
use Dancer2::Plugin::Ajax;

use strict;
use warnings;

use Data::Dumper;
use Const::Fast;
use DateTime;
use URI::Escape::JavaScript;
use DBICx::Sugar;
use Clone;

use QP::Log;
use QP::Mail;
use QP::Schema;
use QP::Util;

our $VERSION = '2.0';

const my $DOMAIN_ROOT               => 'http://www.quiltpatchva.com';
const my $SCHEMA    => QP::Schema->db_connect();
const my $DT_PARSER => $SCHEMA->storage->datetime_parser;
const my $USER_SESSION_EXPIRE_TIME  => 172800; # 48 hours in seconds.
const my $ADMIN_SESSION_EXPIRE_TIME => 600;    # 10 minutes in seconds.
const my $DPAE_REALM                => 'site'; # Dancer2::Plugin::Auth::Extensible realm
const my $DATA_FORM_VALIDATOR => ''; # TEMPORARY TO KILL ERROR WHILE IMPORTING ADMIN CODE

$SCHEMA->storage->debug(1); # Turns on DB debuging. Turn off for production.

hook before_template_render => sub
{
  my $tokens = shift;
  $tokens->{domain_root}           = $DOMAIN_ROOT;
  $tokens->{datetime_format_short} = config->{datetime_format_short};
  $tokens->{datetime_format_long}  = config->{datetime_format_long};
  $tokens->{date_format_short}     = config->{date_format_short};
  $tokens->{date_format_long}      = config->{date_format_long};
};


=head2 GET C</>

Route to get to the default page.

=cut

get '/' => sub {
  my $today = DateTime->today( time_zone => 'America/New_York' );
  my @news = $SCHEMA->resultset( 'News' )->search(
                                                  {
                                                    news_type => 'QP',
                                                    -or =>
                                                    [
                                                      expires => undef,
                                                      expires =>
                                                      {
                                                        '>=' => $DT_PARSER->format_datetime($today)
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
                                                      '>=' => $DT_PARSER->format_datetime($today)
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
                                                      '>=' => $DT_PARSER->format_datetime($today)
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


=head2 GET C</calendar>

Route to get the default calendar page.

=cut

get '/calendar' => sub
{
  template 'calendar',
    { title => 'Events Calendar' };
};


=head2 ANY C</get_events/:event_type>

Route to fetch events for the calendar. AJAX transaction.

=cut

any '/get_events/?:event_type?' => sub
{
  my $today      = DateTime->today( time_zone => 'America/New_York' );
  my $event_type = route_parameters->get( 'event_type' ) // undef;
  my $start      = body_parameters->get( 'start' )
                  // $today->year() . '-' . $today->month() . '-01';
  my $end        = body_parameters->get( 'end' )
                  // DateTime->last_day_of_month( year => $today->year(), month => $today->month() );
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


=head2 GET C</news/:news_type/:news_id>

Route to fetch a single news article.

=cut

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

  $news_article->views( $news_article->views + 1 );
  $news_article->update;

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


=head2 GET C</news/:news_type>

Route to fetch a news feed for a particular news type.

=cut

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


=head2 GET C</classes/by_teacher>

Route to list all classes sorted by teacher.

=cut

get '/classes/by_teacher' => sub
{
  my @teachers = $SCHEMA->resultset( 'Teacher' )->search( {},
                                                          {
                                                            select   =>
                                                            [
                                                              'id',
                                                              'name',
                                                              { SUBSTRING_INDEX => [ 'me.name', "' '", -1 ], -as => 'last_name' },
                                                              { SUBSTRING_INDEX => [ 'me.name', "' '", 1 ], -as => 'first_name' },
                                                            ],
                                                            prefetch => [ 'classes', 'classes2', 'classes3' ],
                                                            order_by =>
                                                            {
                                                              -asc => [ 'last_name, first_name' ],
                                                            },
                                                          }
  );

  template 'classes_by_teacher',
  {
    title => 'Classes | Listed By Teacher',
    data  =>
    {
      teachers => \@teachers,
    }
  };
};


=head2 GET C</classes/:group_id>

Route to fetch classes for a particular class group.

=cut

get '/classes/:group_id' => sub
{
  my $today    = DateTime->today( time_zone => 'America/New_York' );
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

  my @classes = $SCHEMA->resultset( 'ClassInfo' )->search(
                                                      {
                                                        'me.class_group_id' => $group_id,
                                                        -or =>
                                                        [
                                                          'dates.date' => { '>=' => $today->ymd },
                                                          always_show => 1,
                                                        ],
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


=head2 GET C</classes>

Route to fetch default classes landing page.

=cut

get '/classes' => sub
{
  template 'classes',
  {
    title => 'Classes',
  };
};


=head2 GET C</clubs>

Route to fetch clubs landing page.

=cut

get '/clubs' => sub
{
  my $today   = DateTime->today( time_zone => 'America/New_York' );

  my @book_club_dates = $SCHEMA->resultset( 'BookClubDate' )->search(
                                                      {
                                                        date => { '>=' => $today->ymd },
                                                      },
                                                      {
                                                        order_by =>
                                                        {
                                                          -asc => [ 'date', 'book' ],
                                                        }
                                                      },
  );

  my @classes = $SCHEMA->resultset( 'ClassInfo' )->search(
                                                      {
                                                        is_also_club => 1,
                                                        'dates.date' => { '>=' => $today->ymd },
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

  template 'clubs',
  {
    title => 'Clubs',
    data =>
    {
      classes         => \@classes,
      book_club_dates => \@book_club_dates,
    },
  };
};


=head2 GET C</embroidery>

Route to fetch the embroidery landing page.

=cut

get '/embroidery' => sub
{
  my $today   = DateTime->today( time_zone => 'America/New_York' );
  my @classes = $SCHEMA->resultset( 'ClassInfo' )->search(
                                                      {
                                                        is_also_embroidery => 1,
                                                        'dates.date' => { '>=' => $today->ymd },
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

  template 'embroidery',
  {
    title => 'Embroidery',
    data =>
    {
      classes => \@classes,
    },
  };
};


=head2 POST C</search>

Route to submit a search query, and return a result.

=cut

post '/search' => sub
{
  my $search = body_parameters->get( 'search' ) // undef;

  if ( ! defined $search or $search =~ /^[\s\W]*$/ )
  {
    flash( error => 'Invalid search term.' );
    redirect '/classes';
  }

  my @classes = $SCHEMA->resultset( 'ClassInfo' )->search(
                                                      {
                                                        -or =>
                                                        [
                                                          'me.title' => { 'like' => '%'.$search.'%' },
                                                          'me.description' => { 'like' => '%'.$search.'%' },
                                                        ],
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

  template 'search_results',
  {
    title => sprintf( 'Search Results For: &quot;%s&quot;', $search ),
    data =>
    {
      search  => $search,
      classes => \@classes,
    },
  };
};


=head2 GET C</services>

Route to display the services page.

=cut

get '/services' => sub
{
  template 'services',
  {
    title => 'Services',
  };
};


=head2 GET C</contact_us>

Route to reach the contact us form page.

=cut

get '/contact_us' => sub
{
  my $username  = body_parameters->get( 'username' )  // undef;
  my $full_name = body_parameters->get( 'full_name' ) // undef;
  my $email     = body_parameters->get( 'email' )     // undef;
  my $comments  = body_parameters->get( 'comments' )  // undef;

  template 'contact_us',
  {
    title => 'Contact Us',
    data  =>
    {
      form =>
      {
        username  => $username,
        full_name => $full_name,
        email     => $email,
        comments  => $comments,
      }
    },
  };
};


=head2 POST C</contact_us>

Route to submit contact us info for mailing.

=cut

post '/contact_us' => sub
{
  my $username  = body_parameters->get( 'username' )  // undef;
  my $full_name = body_parameters->get( 'full_name' ) // undef;
  my $email     = body_parameters->get( 'email' )     // undef;
  my $comments  = body_parameters->get( 'comments' )  // undef;

  my @errors = ();
  if ( ! defined $full_name || $full_name =~ /^\s*$/ )
  {
    push @errors, '<strong>Full Name</strong> must be filled out.';
  }
  if ( ! defined $email || $email =~ /^\s*$/ )
  {
    push @errors, '<strong>E-mail Address</strong> must be filled out.';
  }
  if ( ! defined $comments || $comments =~ /^\s*$/ )
  {
    push @errors, '<strong>Message</strong> must be filled out.';
  }

  if ( scalar( @errors ) > 0 )
  {
    flash( error => sprintf( 'One or more errors occurred. Please correct the following:<br>%s', join( '<br>', @errors ) ) );
    forward '/contact_us',
      {
        username  => $username,
        full_name => $full_name,
        email     => $email,
        comments  => $comments,
      },
      { method => 'GET' };
  }

  my $now = DateTime->now( time_zone => 'America/New_York' );

  my $new_contact = $SCHEMA->resultset( 'ContactUs' )->new(
    {
      username   => $username,
      full_name  => $full_name,
      email      => $email,
      comments   => $comments,
      created_at => $now,
    }
  );
  $new_contact->insert();

  my $email_sent = QP::Mail::send_contact_us_notification(
    name       => ( $username && $full_name ? sprintf( '%s (%s)', $full_name, $username) : $full_name ),
    email      => $email,
    message    => $comments,
    created_on => $now,
  );

  if ( ! $email_sent->{'success'} )
  {
    warn sprintf( 'Could not send Contact Us message created at %s: %s',
      $now, $email_sent->{'error'} );
  }

  flash( success => sprintf( 'Thank you, %s! You message has been sent!', $full_name ) );
  redirect '/contact_us';
};


=head2 GET C</links>

Route to fetch links.

=cut

get '/links' => sub
{
  my @links = $SCHEMA->resultset( 'LinkGroup' )->search( {}, { order_by => [ 'order_by' ] } );

  template 'links',
  {
    title => 'Links',
    data =>
    {
      link_groups => \@links,
    },
  };
};


=head2 GET C</directions>

Route to display directions and map to the store.

=cut

get '/directions' => sub
{
  template 'directions',
  {
    title => 'Directions',
  };
};


#########################################################################
# ROUTES THAT INVOLVE LOGIN
#########################################################################

=head2 GET C</reset_password>

Route to reset a user's password.

=cut

get '/reset_password' => sub
{
  template 'reset_password_form';
};


=head2 POST C</reset_password>

Route for posting a username to the system to reset the password, and send out a reset code to the user.

=cut

post '/reset_password' => sub
{
  my $username = body_parameters->get( 'username' );

  my $sent = password_reset_send( username => $username, realm => $DPAE_REALM );

  if ( not defined $sent )
  {
    warning sprintf( 'Username >%s< found, but password reset email was not sent for some reason during resest_password.', $username );
  }
  elsif ( $sent == 0 )
  {
    warning sprintf( 'No record found for user >%s< during reset_password.', $username );
  }
  else
  {
    info sprintf( 'Successfully sent password_reset email to account >%s<.', $username );
  }

  flash( notify => 'A password reset email was sent to the email address associated with that account, if it exists.' );
  my $logged = QP::Log->user_log
  (
    user        => 'Unknown',
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Password Reset request for &quot;%s&quot;', $username ),
  );

  redirect '/login';
};


=head2 GET C</reset_my_password/:code>

Route to submit password reset request code and confirm the request.

=cut

get '/reset_my_password/?:code?' => sub
{
  my $code = route_parameters->get( 'code' ) // undef;

  if ( not defined $code )
  {
    return template '/reset_my_password_form',
      {
      };
  }

  my $username = user_password( code => $code );

  if ( not defined $username )
  {
    warning sprintf( 'Password Reset Code >%s< resulted in no user found.', $code );
    flash( error => 'Could not find your reset code. Password reset request was not fulfilled.' );
    redirect '/reset_my_password';
  }

  my $new_temp_pw = QP::Util->generate_random_string( string_length => 8 );

  user_password( code => $code, new_password => $new_temp_pw );

  forward '/login',
    {
      username   => $username,
      password   => $new_temp_pw,
      return_url => '/user/change_password/' . $new_temp_pw,
    },
    { method => 'POST' };
};


=head2 POST C</signup>

Process sign-up information, and error-check.

=cut

post '/signup' => sub
{
  my $user_check = $SCHEMA->resultset( 'User' )->find( { username => body_parameters->get( 'username' ) } );

  if (
      defined $user_check
      &&
      ref( $user_check ) eq 'QP::Schema::Result::User'
      &&
      $user_check->username eq body_parameters->get( 'username' )
     )
  {
    flash( error => sprintf( 'Username <strong>%s</strong> is already in use.', body_parameters->get( 'username' ) ) );
    redirect '/';
  }

  my $email_check = $SCHEMA->resultset( 'User' )->find( { email => body_parameters->get( 'email' ) } );

  if (
      defined $email_check
      &&
      ref( $email_check ) eq 'QP::Schema::Result::User'
      &&
      $email_check->email eq body_parameters->get( 'email' )
     )
  {
    flash( error => sprintf( 'There is already an account associated to the email address <strong>%s</strong>.', body_parameters->get( 'email' ) ) );
    redirect '/';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  # Create the user, and send the welcome e-mail.
  my $new_user = create_user(
                              username      => body_parameters->get( 'username' ),
                              realm         => $DPAE_REALM,
                              password      => body_parameters->get( 'password' ),
                              email         => body_parameters->get( 'email' ),
                              confirmed     => 0,
                              confirm_code  => QP::Util->generate_random_string(),
                              created_on    => $now,
                              email_welcome => 1,
                            );

  # Set the passord, encrypted.
  my $set_password = user_password( username => body_parameters->get( 'username' ), new_password => body_parameters->get( 'password' ) );

  # Set the initial user_role
  my $unconfirmed_role = $SCHEMA->resultset( 'Role' )->find( { role => 'Unconfirmed' } );

  my $user_role = $SCHEMA->resultset( 'UserRole' )->new(
                                                        {
                                                          user_id => $new_user->id,
                                                          role_id => $unconfirmed_role->id,
                                                        }
                                                       );
  $SCHEMA->txn_do(
                  sub
                  {
                    $user_role->insert;
                  }
  );

  info sprintf( 'Created new user >%s<, ID: >%s<, on %s', body_parameters->get( 'username' ), $new_user->id, $now );

  # Email confirmation message to the user.

  flash( success => sprintf("Thanks for signing up, %s! You have been logged in.", body_parameters->get( 'username' ) ) );
  my $logged = QP::Log->user_log
  (
    user        => sprintf( '%s (ID:%s)', $new_user->username, $new_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => 'New User Sign Up',
  );

  # change session ID if we have a new enough D2 version with support
  # (security best practice on privilege level change)
  app->change_session_id if app->can('change_session_id');

  session 'logged_in_user' => body_parameters->get( 'username' );
  session 'logged_in_user_realm' => $DPAE_REALM;
  session->expires( $USER_SESSION_EXPIRE_TIME );

  redirect '/signed_up';
};


=head2 GET C</signed_up>

Successful sign-up page, with next-step instructions for account confirmation.

=cut

get '/signed_up' => require_login sub
{
  if ( ! session( 'logged_in_user' ) )
  {
    info 'An anonymous (not logged in) user attempted to access /signed_up.';
    flash( error => 'You need to be logged in to access that page.' );
    redirect '/login';
  }

  my $user = $SCHEMA->resultset( 'User' )->find( { username => logged_in_user->username } );

  if ( ref( $user ) ne 'QP::Schema::Result::User' )
  {
    warning sprintf( 'A user (%s) attempted to reach /signed_up, but the account could not be confirmed to exist.', session( 'user' ) );
    flash( error => 'You need to be logged in to access that page.' );
    redirect '/login';
  }

  template 'signed_up_success',
    {
      data =>
      {
        user         => $user,
        from_address => config->{mailer_address},
      },
      subtitle => 'Thanks for Signing Up!',
    };
};


=head2 GET C</resend_confirmation>

Route for a User to request that their confirmation e-mail be resent to them.

=cut

get '/resend_confirmation' => sub
{
  # If the user is logged in, use that information and redirect.
  if ( defined logged_in_user )
  {
    my $sent = QP::Mail::send_welcome_email
    (
      undef,
      user  => { username => logged_in_user->username }, # Expects a hashref for the user. Only needs username
      email => logged_in_user->email,
    );
    if ( $sent->{'success'} )
    {
      flash( success => sprintf( 'We have resent the confirmation email to your account at &quot;<strong>%s</strong>&quot;.', logged_in_user->email ) );
      info sprintf( "Resent confirmation email at user's request to >%s<.", logged_in_user->email );
      my $logged = QP::Log->user_log
      (
        user        => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
        ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
        log_level   => 'Info',
        log_message => 'Resent confirmation email.',
      );
      redirect '/user';
    }
    else
    {
      flash( error => 'An error has occurred and we could not resend the confirmation email. Please try again in a few minutes.' );
      error sprintf( "Error occurred when trying to resend the confirmation code to >%s<: %s", logged_in_user->email, $sent->{'error'} );
      my $logged = QP::Log->user_log
      (
        user        => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
        ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
        log_level   => 'Error',
        log_message => sprintf( 'Confirmation Email Resend failed to &gt;%s&lt;: %s', logged_in_user->email, $sent->{'error'} ),
      );
      redirect '/user';
    }
  }

  # If the user is not logged in, request an e-mail address and username.
  template 'resend_confirmation',
    {
      breadcrumbs =>
      [
        { name => 'Sign Up', link => '/login' },
        { name => 'Resend Confirmation Email', current => 1 },
      ],
    };
};


=head2 POST C</resend_confirmation>

Route to submit credentials for resending confirmation e-mails.

=cut

post '/resend_confirmation' => sub
{
  my $username = body_parameters->get( 'username ' ) // undef;
  my $email    = body_parameters->get( 'email ' )    // undef;

  if
  (
    not defined $username
    or
    not defined $email
  )
  {
    flash( error => 'Both your username and your email address are required.' );
    redirect '/resend_confirmation';
  }

  my $user = $SCHEMA->resultset( 'User' )->find
  (
    {
      username => $username,
      email    => $email,
    }
  );

  if
  (
    not defined $user
    or
    ref( $user ) ne 'QP::Schema::Result::User'
  )
  {
    error sprintf( 'Invalid user credentials on resend confirmation: user - >%s< / email - >%s<', $username, $email );
    flash( error => 'An error occurred in trying to locate your account.<br>Some or all of the information you have provided is incorrect.' );
    my $logged = QP::Log->user_log
    (
      user        => 'Unknown',
      ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
      log_level   => 'Error',
      log_message => sprintf( 'Resend Confirmation Failed: Invalid credentials - &gt;%s&lt; &gt;%s&lt;', $username, $email ),
    );
    redirect '/resend_confirmation';
  }

  my $sent = QP::Mail::send_welcome_email
  (
    user  => $user->username,
    email => $user->email,
  );
  if ( $sent->{'success'} )
  {
    flash( success => sprintf( 'We have resent the confirmation email to your account at &quot;<strong>%s</strong>%quot;.', $user->email ) );
    info sprintf( "Resent confirmation email at user's request to >%s<.", $user->email );
    my $logged = QP::Log->user_log
    (
      user        => 'Unknown',
      ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
      log_level   => 'Info',
      log_message => sprintf( 'Confirmation Email Resent: &gt;%s&lt;', $user->email ),
    );
    redirect '/';
  }
  else
  {
    flash( error => 'An error has occurred and we could not resend the confirmation email. Please try again in a few minutes.' );
    error sprintf( "Error occurred when trying to resend the confirmation code to >%s<: %s", $user->email, $sent->{'error'} );
    my $logged = QP::Log->user_log
    (
      user        => 'Unknown',
      ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
      log_level   => 'Error',
      log_message => sprintf( 'Resend Confirmation Failed: Email send failed - &gt;%s&lt;: &gt;%s&lt;', $user->email, $sent->{'error'} ),
    );
    redirect '/resend_confirmation';
  }
};


=head2 GET C</login>

Login page for redirection, login errors, reattempt, etc.

=cut

get '/login' => sub
{
  my $return_url = query_parameters->get( 'return_url' );

  if ( defined logged_in_user )
  {
    redirect '/user';
  }

  template 'login',
    {
      data =>
      {
        return_url => $return_url
      },
    };
};

=head2 POST C</login>

Authenticates user, and logs them in.  Otherwise, redirects them to the login page.

=cut

post '/login' => sub
{
  authenticate_user
  (
    body_parameters->get( 'username' ),
    body_parameters->get( 'password' ),
  );

  flash( success => sprintf( 'Welcome back, %s!', body_parameters->get( 'username' ) ) );
  redirect ( body_parameters->get( 'return_url' ) ) ? body_parameters->get( 'return_url' ) : '/user';
};


=head2 ANY C</logout>

Logout route, for killing user sessions, and redirecting to the index page.

=cut

any '/logout' => sub
{
  app->destroy_session;
  flash( notify => 'You are logged out. Come back soon!' );
};


=head2 ANY C</login/denied>

User denied access route for authentication failures.

=cut

any '/login/denied' => sub
{
  template 'login_denied';
};


=head2 GET C</account_confirmation>

GET route for confirmation code submission from welcome e-mails.

=cut

get '/account_confirmation/:ccode' => sub
{
  my $ccode = route_parameters->get( 'ccode' );

  my $user = $SCHEMA->resultset( 'User' )->find( { confirm_code => $ccode } );

  if ( ! defined $user || ref( $user ) ne 'QP::Schema::Result::User' )
  {
    info sprintf( 'Confirmation Code submitted >%s< matched no user.', $ccode );
    return template 'account_confirmation', {
                                              data =>
                                              {
                                                ccode => $ccode,
                                              },
                                            };
  }

  update_user( $user->username, realm => $DPAE_REALM, confirm_code => undef, confirmed => 1 );

  # Set the user_role to Confirmed
  my $unconfirmed_role = $SCHEMA->resultset( 'Role' )->find( { role => 'Unconfirmed' } );
  my $role_to_delete   = $SCHEMA->resultset( 'UserRole' )->find( { user_id => $user->id, role_id => $unconfirmed_role->id } );
  $role_to_delete->delete();

  my $confirmed_role = $SCHEMA->resultset( 'Role' )->find( { role => 'Confirmed' } );

  my $user_role = $SCHEMA->resultset( 'UserRole' )->new(
                                                        {
                                                          user_id => $user->id,
                                                          role_id => $confirmed_role->id,
                                                        }
                                                       );
  $SCHEMA->txn_do(
                  sub
                  {
                    $user_role->insert;
                  }
  );
  info sprintf( 'User >%s< successfully confirmed.', $user->username );
  my $logged = QP::Log->user_log
  (
    user        => sprintf( '%s (ID:%s)', $user->username, $user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => 'Successful account confirmation.',
  );

  template 'account_confirmation',
    {
      data =>
      {
        success => 1,
        user    => $user,
      },
      subtitle => 'Account Confirmation',
    };
};


=head2 POST C</account_confirmation>

POST route for confirmation code resubmission.

=cut

post '/account_confirmation' => sub
{
  my $ccode = body_parameters->get( 'ccode' );

  redirect "/account_confirmation/$ccode";
};


###########################################################################
# ROUTES THAT REQUIRE THE USER BE LOGGED IN
###########################################################################


=head2 GET C</user>

GET route for the default user home page.

=cut

get '/user' => require_login sub
{
  my $user = $SCHEMA->resultset( 'User' )->find( { username => session( 'logged_in_user' ) } );
  if ( ! defined $user or ! defined $user->id )
  {
    warning 'Invalid username supplied to find User account in user dashboard.';
  }

  template 'user_dashboard',
  {
    data =>
    {
      user => $user,
    }
  };
};


=head2 GET C</user/account>

GET route for User Account management.

=cut

get '/user/account' => require_login sub
{
  my $user = $SCHEMA->resultset( 'User' )->find( { username => session( 'logged_in_user' ) } );
  if ( ! defined $user or ! defined $user->id )
  {
    warning 'Invalid username supplied to find User account in user account mgmt dashboard.';
  }

  template 'user_account_mgmt',
  {
    data =>
    {
      user => $user,
    }
  }
};


=head2 POST C</user/account>

POST route for updating and saving User account data.

=cut

post '/user/account' => require_login sub
{
  my $user = $SCHEMA->resultset( 'User' )->find( { username => session( 'logged_in_user' ) } );
  if ( ! defined $user or ! defined $user->id )
  {
    warning 'Invalid username supplied to find User account in user account mgmt submit.';
    flash( error => 'An error occurred. Your information was not saved. Please try again.' );
    redirect '/user/account';
  }

  $user->username(
    ( body_parameters->get('username') ) ? body_parameters->get( 'username' ) : $user->username
  );
  $user->first_name(
    ( body_parameters->get('first_name') ) ? body_parameters->get( 'first_name' ) : undef
  );
  $user->last_name(
    ( body_parameters->get('last_name') ) ? body_parameters->get( 'last_name' ) : undef
  );
  $user->birthdate(
    ( body_parameters->get('birthdate') ) ? body_parameters->get( 'birthdate' ) : undef
  );
  $user->email(
    ( body_parameters->get('email') ) ? body_parameters->get( 'email' ) : $user->email
  );

  $user->update();

  flash( success => 'Your changes have been saved!' );
  redirect '/user/account';
};


#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# ADMIN ROUTES BELOW HERE
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-


=head1 ADMIN ROUTES


=head2 GET C</admin>

Route to admin dashboard. Requires being logged in and of admin role.

=cut

get '/admin' => require_role Admin => sub
{
  template 'admin_dashboard',
    {
      data =>
      {
      },
      breadcrumbs =>
      [
        { name => 'Admin', current => 1 },
      ],
      title => 'Admin Dashboard',
    };
};


=head2 GET C</admin/manage_classes/groups>

Route to Class Group management dashboard. Requires being logged in and of admin role.

=cut

get '/admin/manage_classes/groups' => require_role Admin => sub
{
  my @class_groups = $SCHEMA->resultset( 'ClassGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_class_groups',
  {
    data =>
    {
      class_groups => \@class_groups,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Class Groups', current => 1 },
    ],
    title => 'Manage Class Groups',
  };
};


=head2 GET C</admin/manage_classes/groups/add>

Route to add new class group form. Requires being logged in and of Admin role.

=cut

get '/admin/manage_classes/groups/add' => require_role Admin => sub
{
  template 'admin_manage_class_groups_add_form',
      {
        data =>
        {
        },
        breadcrumbs =>
        [
          { name => 'Admin', link => '/admin' },
          { name => 'Manage Class Groups', link => '/admin/manage_classes/groups' },
          { name => 'Add New Class Group', current => 1 },
        ],
        title => 'Add Class Group',
      };
};


=head2 POST C</admin/manage_classes/groups/create>

Route to save new class group data to the database.  Requires being logged in and of Admin role.

=cut

post '/admin/manage_classes/groups/create' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $new_group = $SCHEMA->resultset( 'ClassGroup' )->create(
    {
      name        => body_parameters->get( 'name' ),
      description => ( body_parameters->get( 'description' ) ? body_parameters->get( 'description' ) : undef ),
      footer_text => ( body_parameters->get( 'footer_text' ) ? body_parameters->get( 'footer_text' ) : undef ),
    }
  );

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new class group >%s<, ID: >%s<, on %s', body_parameters->get( 'name' ), $new_group->id, $now );

  flash success => sprintf( 'Successfully created Class Group &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'name' ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new class group<br>%s', join( '<br>', @fields ) ),
  );

  redirect '/admin/manage_classes/groups';
};


=head2 GET C</admin/manage_classes/groups/:group_id/edit>

Route for presenting the edit product form. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/groups/:group_id/edit' => require_role Admin => sub
{
  my $group_id = route_parameters->get( 'group_id' );

  my $group = $SCHEMA->resultset( 'ClassGroup' )->find( $group_id );

  template 'admin_manage_class_groups_edit_form',
      {
        data =>
        {
          group => $group,
        },
        breadcrumbs =>
        [
          { name => 'Admin', link => '/admin' },
          { name => 'Manage Class Groups', link => '/admin/manage_classes/groups' },
          { name => 'Edit Class Group', current => 1 },
        ],
        title => 'Edit Class Group',
      };
};


=head2 POST C</admin/manage_classes/groups/:group_id/update>

Route to send form data to for updating a class group in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_classes/groups/:group_id/update' => require_role Admin => sub
{
  my $group_id = route_parameters->get( 'group_id' );

  my $group = $SCHEMA->resultset( 'ClassGroup' )->find( $group_id );
  my $orig_group = Clone::clone( $group );

  if
  (
    not defined $group
    or
    ref( $group ) ne 'QP::Schema::Result::ClassGroup'
  )
  {
    flash( error => 'Error: Cannot update class group - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/groups';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $group->name( body_parameters->get( 'name' ) );
  $group->description( body_parameters->get( 'description' ) ? body_parameters->get( 'description' ) : undef );
  $group->footer_text( body_parameters->get( 'footer_text' ) ? body_parameters->get( 'footer_text' ) : undef );

  $group->update();

  info sprintf( 'Class group >%s< updated by %s on %s.', $group->name, logged_in_user->username, $now );

  my $old =
  {
    name        => $orig_group->name,
    description => $orig_group->description,
    footer_text => $orig_group->footer_text,
  };
  my $new =
  {
    name        => body_parameters->get( 'name' ),
    description => ( body_parameters->get( 'description' ) ? body_parameters->get( 'description' ) : undef ),
    footer_text => ( body_parameters->get( 'footer_text' ) ? body_parameters->get( 'footer_text' ) : undef ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class group modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated class group &quot;<strong>%s</strong>&quot;.',
                                body_parameters->get( 'name' ) ) );
  redirect '/admin/manage_classes/groups';
};


=head2 GET C</admin/manage_classes/groups/:group_id/delete>

Route to delete a class group. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/groups/:group_id/delete' => require_role Admin => sub
{
  my $group_id = route_parameters->get( 'group_id' );

  my $group = $SCHEMA->resultset( 'ClassGroup' )->find( $group_id );
  my $group_name = $group->name;

  if
  (
    not defined $group
    or
    ref( $group ) ne 'QP::Schema::Result::ClassGroup'
  )
  {
    flash( error => 'Error: Cannot delete class group - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/groups';
  }

  $group->delete;

  flash success => sprintf( 'Successfully deleted Class Group <strong>%s</strong>.', $group_name );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class group &quot;%s&quot; deleted', $group_name ),
  );
  redirect '/admin/manage_classes/groups';
};


=head2 GET C</admin/manage_classes/subgroups>

Route to Class Subgroup management dashboard. Requires being logged in and of admin role.

=cut

get '/admin/manage_classes/subgroups' => require_role Admin => sub
{
  my @class_subgroups = $SCHEMA->resultset( 'ClassSubgroup' )->search( undef,
                                                          {
                                                            order_by =>
                                                            {
                                                              -asc =>
                                                              [
                                                                'class_group_id',
                                                                'order_by',
                                                              ]
                                                            },
                                                          }
  );

  my @class_groups = $SCHEMA->resultset( 'ClassGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_class_subgroups',
  {
    data =>
    {
      class_subgroups => \@class_subgroups,
      class_groups    => \@class_groups,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Class Subgroups', current => 1 },
    ],
    title => 'Manage Class Subgroups',
  };
};


=head2 GET C</admin/manage_classes/subgroups/add>

Route to add new class subgroup form. Requires being logged in and of Admin role.

=cut

get '/admin/manage_classes/subgroups/add' => require_role Admin => sub
{
  my @groups   = $SCHEMA->resultset( 'ClassGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );
  template 'admin_manage_classes_subgroups_add_form',
      {
        data =>
        {
          groups => \@groups,
        },
        title => 'Add Class Subgroup',
      },
      {
        layout => 'ajax-modal'
      };
};


=head2 POST C</admin/manage_classes/subgroups/create>

Route to save new class subgroup data to the database.  Requires being logged in and of Admin role.

=cut

post '/admin/manage_classes/subgroups/create' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $new_subgroup = $SCHEMA->resultset( 'ClassSubgroup' )->create(
    {
      subgroup       => body_parameters->get( 'subgroup' ),
      class_group_id => body_parameters->get( 'class_group_id' ),
      order_by       => body_parameters->get( 'order_by' ),
    }
  );

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new class subgroup >%s<, ID: >%s<, on %s', body_parameters->get( 'subgroup' ), $new_subgroup->id, $now );

  flash success => sprintf( 'Successfully created Class Subgroup &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'subgroup' ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new class subgroup<br>%s', join( '<br>', @fields ) ),
  );

  redirect '/admin/manage_classes/subgroups';
};


=head2 AJAX C</admin/manage_classes/subgroups/:subgroup_id/edit>

Route for presenting the edit class subgroup form. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/subgroups/:subgroup_id/edit' => require_role Admin => sub
{
  my $subgroup_id = route_parameters->get( 'subgroup_id' );

  my $subgroup = $SCHEMA->resultset( 'ClassSubgroup' )->find( $subgroup_id );
  my @groups   = $SCHEMA->resultset( 'ClassGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_classes_subgroups_edit_form',
      {
        data =>
        {
          groups   => \@groups,
          subgroup => $subgroup,
        },
        title => 'Edit Class Subgroup',
      },
      {
        layout => 'ajax-modal'
      };
};


=head2 POST C</admin/manage_classes/subgroups/:subgroup_id/update>

Route to send form data to for updating a class subgroup in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_classes/subgroups/:subgroup_id/update' => require_role Admin => sub
{
  my $subgroup_id = route_parameters->get( 'subgroup_id' );

  my $subgroup      = $SCHEMA->resultset( 'ClassSubgroup' )->find( $subgroup_id );
  my $orig_subgroup = Clone::clone( $subgroup );

  if
  (
    not defined $subgroup
    or
    ref( $subgroup ) ne 'QP::Schema::Result::ClassSubgroup'
  )
  {
    flash( error => 'Error: Cannot update class subgroup - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/subgroups';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $subgroup->class_group_id( body_parameters->get( 'class_group_id' ) );
  $subgroup->subgroup( body_parameters->get( 'subgroup' ) );
  $subgroup->order_by( body_parameters->get( 'order_by' ) ? body_parameters->get( 'order_by' ) : 1 );

  $subgroup->update();

  info sprintf( 'Class subgroup >%s< updated by %s on %s.', $subgroup->subgroup, logged_in_user->username, $now );

  my $old =
  {
    class_group_id => $orig_subgroup->class_group_id,
    subgroup       => $orig_subgroup->subgroup,
    order_by       => $orig_subgroup->order_by,
  };
  my $new =
  {
    class_group_id => body_parameters->get( 'class_group_id' ),
    subgroup       => body_parameters->get( 'subgroup' ),
    order_by       => body_parameters->get( 'order_by' ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class subgroup modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated class subgroup &quot;<strong>%s</strong>&quot;.',
                                body_parameters->get( 'subgroup' ) ) );
  redirect '/admin/manage_classes/subgroups';
};


=head2 GET C</admin/manage_classes/subgroups/:subgroup_id/delete>

Route to delete a class subgroup. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/subgroups/:subgroup_id/delete' => require_role Admin => sub
{
  my $subgroup_id = route_parameters->get( 'subgroup_id' );

  my $subgroup = $SCHEMA->resultset( 'ClassSubgroup' )->find( $subgroup_id );
  my $subgroup_name = $subgroup->subgroup;

  if
  (
    not defined $subgroup
    or
    ref( $subgroup ) ne 'QP::Schema::Result::ClassSubgroup'
  )
  {
    flash( error => 'Error: Cannot delete class subgroup - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/subgroups';
  }

  $subgroup->delete;

  flash success => sprintf( 'Successfully deleted Class Subgroup <strong>%s</strong>.', $subgroup_name );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class subgroup &quot;%s&quot; deleted', $subgroup_name ),
  );
  redirect '/admin/manage_classes/subgroups';
};


=head2 GET C</admin/manage_classes/teachers>

Route to Class Teachers  management dashboard. Requires being logged in and of admin role.

=cut

get '/admin/manage_classes/teachers' => require_role Admin => sub
{
  my @teachers = $SCHEMA->resultset( 'Teacher' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_class_teachers',
  {
    data =>
    {
      teachers => \@teachers,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Teachers', current => 1 },
    ],
    title => 'Manage Teachers',
  };
};


=head2 GET C</admin/manage_classes/teachers/add>

Route to add new class teacher form. Requires being logged in and of Admin role.

=cut

get '/admin/manage_classes/teachers/add' => require_role Admin => sub
{
  template 'admin_manage_classes_teachers_add_form',
      {
        data =>
        {
        },
        title => 'Add Teacher',
      },
      {
        layout => 'ajax-modal'
      };
};


=head2 POST C</admin/manage_classes/teachers/create>

Route to save new class teacher data to the database.  Requires being logged in and of Admin role.

=cut

post '/admin/manage_classes/teachers/create' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $new_teacher = $SCHEMA->resultset( 'Teacher' )->create(
    {
      name => body_parameters->get( 'name' ),
    }
  );

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new class teacher >%s<, ID: >%s<, on %s', body_parameters->get( 'name' ), $new_teacher->id, $now );

  flash success => sprintf( 'Successfully created Teacher &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'name' ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new class teacher<br>%s', join( '<br>', @fields ) ),
  );

  redirect '/admin/manage_classes/teachers';
};


=head2 AJAX C</admin/manage_classes/teachers/:teacher_id/edit>

Route for presenting the edit class subgroup form. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/teachers/:teacher_id/edit' => require_role Admin => sub
{
  my $teacher_id = route_parameters->get( 'teacher_id' );

  my $teacher = $SCHEMA->resultset( 'Teacher' )->find( $teacher_id );


  template 'admin_manage_classes_teachers_edit_form',
      {
        data =>
        {
          teacher => $teacher,
        },
        title => 'Edit Teacher',
      },
      {
        layout => 'ajax-modal'
      };
};


=head2 POST C</admin/manage_classes/teachers/:teacher_id/update>

Route to send form data to for updating a class teacher in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_classes/teachers/:teacher_id/update' => require_role Admin => sub
{
  my $teacher_id = route_parameters->get( 'teacher_id' );

  my $teacher      = $SCHEMA->resultset( 'Teacher' )->find( $teacher_id );
  my $orig_teacher = Clone::clone( $teacher );

  if
  (
    not defined $teacher
    or
    ref( $teacher ) ne 'QP::Schema::Result::Teacher'
  )
  {
    flash( error => 'Error: Cannot update teacher - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/teachers';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $teacher->name( body_parameters->get( 'name' ) );

  $teacher->update();

  info sprintf( 'Class teacher >%s< updated by %s on %s.', $teacher->name, logged_in_user->username, $now );

  my $old =
  {
    name => $orig_teacher->name,
  };
  my $new =
  {
    name => body_parameters->get( 'name' ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Teacher modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated teacher &quot;<strong>%s</strong>&quot;.',
                                body_parameters->get( 'name' ) ) );
  redirect '/admin/manage_classes/teachers';
};


=head2 GET C</admin/manage_classes/teachers/:teacher_id/delete>

Route to delete a class teacher. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/teachers/:teacher_id/delete' => require_role Admin => sub
{
  my $teacher_id = route_parameters->get( 'teacher_id' );

  my $teacher = $SCHEMA->resultset( 'Teacher' )->find( $teacher_id );
  my $teacher_name = $teacher->name;

  if
  (
    not defined $teacher
    or
    ref( $teacher ) ne 'QP::Schema::Result::Teacher'
  )
  {
    flash( error => 'Error: Cannot delete teacher - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/teachers';
  }

  $teacher->delete;

  flash success => sprintf( 'Successfully deleted Teacher <strong>%s</strong>.', $teacher_name );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class teacher &quot;%s&quot; deleted', $teacher_name ),
  );
  redirect '/admin/manage_classes/teachers';
};


=head2 GET C</admin/manage_classes/classes>

Route to Class management dashboard. Requires being logged in and of admin role.

=cut

get '/admin/manage_classes/classes' => require_role Admin => sub
{
  my @classes = $SCHEMA->resultset( 'ClassInfo' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'title' },
                                                          }
  );

  template 'admin_manage_class_classes',
  {
    data =>
    {
      classes => \@classes,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Classes', current => 1 },
    ],
    title => 'Manage Classes',
  };
};


=head2 GET C</admin/manage_classes/classes/add>

Route to add new class form. Requires being logged in and of Admin role.

=cut

get '/admin/manage_classes/classes/add' => require_role Admin => sub
{
  my @class_groups = $SCHEMA->resultset( 'ClassGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );
  my @class_subgroups = $SCHEMA->resultset( 'ClassSubgroup' )->search( undef,
                                                          {
                                                            order_by =>
                                                            {
                                                              -asc =>
                                                              [
                                                                'class_group_id',
                                                                'order_by',
                                                              ]
                                                            },
                                                          }
  );
  my @teachers = $SCHEMA->resultset( 'Teacher' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_classes_classes_add_form',
  {
    data =>
    {
      groups    => \@class_groups,
      subgroups => \@class_subgroups,
      teachers  => \@teachers,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Classes', link => '/admin/manage_classes/classes' },
      { name => 'Add New Class', current => 1 },
    ],
    title => 'Add New Class',
  };
};


=head2 POST C</admin/manage_classes/classes/create>

Route to save new class data to the database.  Requires being logged in and of Admin role.

=cut

post '/admin/manage_classes/classes/create' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $class_exists = $SCHEMA->resultset( 'ClassInfo' )->search( { title => body_parameters->get( 'title' ) } );

  if ( defined $class_exists and ref( $class_exists ) eq 'QP::Schema::Result::ClassInfo' )
  {
    flash error => sprintf( 'Class <strong>%s</strong> already exists.' );
    redirect '/admin/manage_classes/classes';
  }

  my $new_class = $SCHEMA->resultset( 'ClassInfo' )->create(
    {
      title                => body_parameters->get( 'title' ),
      description          => body_parameters->get( 'description' ),
      class_group_id       => body_parameters->get( 'class_group_id' ),
      class_subgroup_id    => ( body_parameters->get( 'class_subgroup_id' )    ? body_parameters->get( 'class_subgroup_id' )    : undef ),
      teacher_id           => ( body_parameters->get( 'teacher_id' )           ? body_parameters->get( 'teacher_id' )           : undef ),
      secondary_teacher_id => ( body_parameters->get( 'secondary_teacher_id' ) ? body_parameters->get( 'secondary_teacher_id' ) : undef ),
      tertiary_teacher_id  => ( body_parameters->get( 'tertiary_teacher_id' )  ? body_parameters->get( 'tertiary_teacher_id' )  : undef ),
      num_sessions         => ( body_parameters->get( 'num_sessions' )         ? body_parameters->get( 'num_sessions' )         : undef ),
      fee                  => ( body_parameters->get( 'fee' )                  ? body_parameters->get( 'fee' )                  : undef ),
      skill_level          => ( body_parameters->get( 'skill_level' )          ? body_parameters->get( 'skill_level' )          : undef ),
      is_also_embroidery   => ( body_parameters->get( 'is_also_embroidery' )   ? body_parameters->get( 'is_also_embroidery' )   : 0 ),
      is_also_club         => ( body_parameters->get( 'is_also_club' )         ? body_parameters->get( 'is_also_club' )         : 0 ),
      show_club            => ( body_parameters->get( 'show_club' )            ? body_parameters->get( 'show_club' )            : 0 ),
      no_supply_list       => ( body_parameters->get( 'no_supply_list' )       ? body_parameters->get( 'no_supply_list' )       : 0 ),
      always_show          => ( body_parameters->get( 'always_show' )          ? body_parameters->get( 'always_show' )          : 0 ),
      is_new               => ( body_parameters->get( 'is_new' )               ? body_parameters->get( 'is_new' )               : 0 ),
      image_filename       => undef,
      supply_list_filename => undef,
      anchor               => undef,
    }
  );

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new class >%s<, ID: >%s<, on %s', body_parameters->get( 'title' ), $new_class->id, $now );

  flash success => sprintf( 'Successfully created Class &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'title' ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new class <br>%s', join( '<br>', @fields ) ),
  );

  redirect '/admin/manage_classes/classes';
};


=head2 AJAX C</admin/manage_classes/classes/:class_id/edit>

Route for presenting the edit class subgroup form. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/classes/:class_id/edit' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );

  my @class_groups = $SCHEMA->resultset( 'ClassGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );
  my @class_subgroups = $SCHEMA->resultset( 'ClassSubgroup' )->search( undef,
                                                          {
                                                            order_by =>
                                                            {
                                                              -asc =>
                                                              [
                                                                'class_group_id',
                                                                'order_by',
                                                              ]
                                                            },
                                                          }
  );
  my @teachers = $SCHEMA->resultset( 'Teacher' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_classes_classes_edit_form',
  {
    data =>
    {
      class     => $class,
      groups    => \@class_groups,
      subgroups => \@class_subgroups,
      teachers  => \@teachers,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Classes', link => '/admin/manage_classes/classes' },
      { name => 'Edit Class', current => 1 },
    ],
    title => 'Edit Class',
  };
};


=head2 POST C</admin/manage_classes/classes/:class_id/update>

Route to send form data to for updating a class in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_classes/classes/:class_id/update' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );

  my $class      = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );
  my $orig_class = Clone::clone( $class );

  if
  (
    not defined $class
    or
    ref( $class ) ne 'QP::Schema::Result::ClassInfo'
  )
  {
    flash( error => 'Error: Cannot update class - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/classes';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $class->class_group_id( body_parameters->get( 'class_group_id' ) ),
  $class->class_subgroup_id( body_parameters->get( 'class_subgroup_id' ) ? body_parameters->get( 'class_subgroup_id' ) : undef ),
  $class->teacher_id( body_parameters->get( 'teacher_id' ) ? body_parameters->get( 'teacher_id' ) : undef ),
  $class->secondary_teacher_id( body_parameters->get( 'secondary_teacher_id' ) ? body_parameters->get( 'secondary_teacher_id' ) : undef ),
  $class->tertiary_teacher_id( body_parameters->get( 'tertiary_teacher_id' ) ? body_parameters->get( 'tertiary_teacher_id' ) : undef ),
  $class->title( body_parameters->get( 'title' ) ),
  $class->description( body_parameters->get( 'description' ) ),
  $class->num_sessions( body_parameters->get( 'num_sessions' ) ? body_parameters->get( 'num_sessions' ) : undef ),
  $class->fee( body_parameters->get( 'fee' ) ? body_parameters->get( 'fee' ) : undef ),
  $class->skill_level( body_parameters->get( 'skill_level' ) ? body_parameters->get( 'skill_level' ) : undef ),
  $class->is_also_embroidery( body_parameters->get( 'is_also_embroidery' ) ? body_parameters->get( 'is_also_embroidery' ) : 0 ),
  $class->is_also_club( body_parameters->get( 'is_also_club' ) ? body_parameters->get( 'is_also_club' ) : 0 ),
  $class->show_club( body_parameters->get( 'show_club' ) ? body_parameters->get( 'show_club' ) : 0 ),
  $class->no_supply_list( body_parameters->get( 'no_supply_list' ) ? body_parameters->get( 'no_supply_list' ) : 0 ),
  $class->always_show( body_parameters->get( 'always_show' ) ? body_parameters->get( 'always_show' ) : 0 ),
  $class->is_new( body_parameters->get( 'is_new' ) ? body_parameters->get( 'is_new' ) : 0 ),

  $class->update();

  info sprintf( 'Class >%s< updated by %s on %s.', $class->title, logged_in_user->username, $now );

  my $old =
  {
    class_group_id       => $orig_class->class_group_id,
    class_subgroup_id    => $orig_class->class_subgroup_id,
    teacher_id           => $orig_class->teacher_id,
    secondary_teacher_id => $orig_class->secondary_teacher_id,
    tertiary_teacher_id  => $orig_class->tertiary_teacher_id,
    title                => $orig_class->title,
    description          => $orig_class->description,
    num_sessions         => $orig_class->num_sessions,
    fee                  => $orig_class->fee,
    skill_level          => $orig_class->skill_level,
    is_also_embroidery   => $orig_class->is_also_embroidery,
    is_also_club         => $orig_class->is_also_club,
    show_club            => $orig_class->show_club,
    no_supply_list       => $orig_class->no_supply_list,
    always_show          => $orig_class->always_show,
    is_new               => $orig_class->is_new,
  };
  my $new =
  {
    class_group_id       => body_parameters->get( 'class_group_id' ),
    class_subgroup_id    => ( body_parameters->get( 'class_subgroup_id' ) ? body_parameters->get( 'class_subgroup_id' ) : undef ),
    teacher_id           => ( body_parameters->get( 'teacher_id' ) ? body_parameters->get( 'teacher_id' ) : undef ),
    secondary_teacher_id => ( body_parameters->get( 'secondary_teacher_id' ) ? body_parameters->get( 'secondary_teacher_id' ) : undef ),
    tertiary_teacher_id  => ( body_parameters->get( 'tertiary_teacher_id' ) ? body_parameters->get( 'tertiary_teacher_id' ) : undef ),
    title                => body_parameters->get( 'title' ),
    description          => body_parameters->get( 'description' ),
    num_sessions         => ( body_parameters->get( 'num_sessions' ) ? body_parameters->get( 'num_sessions' ) : undef ),
    fee                  => ( body_parameters->get( 'fee' ) ? body_parameters->get( 'fee' ) : undef ),
    skill_level          => ( body_parameters->get( 'skill_level' ) ? body_parameters->get( 'skill_level' ) : undef ),
    is_also_embroidery   => ( body_parameters->get( 'is_also_embroidery' ) ? body_parameters->get( 'is_also_embroidery' ) : 0 ),
    is_also_club         => ( body_parameters->get( 'is_also_club' ) ? body_parameters->get( 'is_also_club' ) : 0 ),
    show_club            => ( body_parameters->get( 'show_club' ) ? body_parameters->get( 'show_club' ) : 0 ),
    no_supply_list       => ( body_parameters->get( 'no_supply_list' ) ? body_parameters->get( 'no_supply_list' ) : 0 ),
    always_show          => ( body_parameters->get( 'always_show' ) ? body_parameters->get( 'always_show' ) : 0 ),
    is_new               => ( body_parameters->get( 'is_new' ) ? body_parameters->get( 'is_new' ) : 0 ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated class &quot;<strong>%s</strong>&quot;.',
                                body_parameters->get( 'title' ) ) );
  redirect '/admin/manage_classes/classes';
};


=head2 GET C</admin/manage_classes/classes/:class_id/delete>

Route to delete a class. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/classes/:class_id/delete' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );
  my $class_title = $class->title;

  if
  (
    not defined $class
    or
    ref( $class ) ne 'QP::Schema::Result::ClassInfo'
  )
  {
    flash( error => 'Error: Cannot delete class - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/classes';
  }

  $class->delete;

  flash success => sprintf( 'Successfully deleted Class <strong>%s</strong>.', $class_title );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class &quot;%s&quot; deleted', $class_title ),
  );

  redirect '/admin/manage_classes/classes';
};



=head2 POST C</admin/manage_products/:product_id/upload>

Route for uploading product images and associating them to the indicated product. Require the user is an Admin.

=cut

post '/admin/manage_products/:product_id/upload' => require_role Admin => sub
{
  my $product_id  = route_parameters->get( 'product_id' );
  my $upload_data = request->upload( 'qqfile' );    # upload object

  # Save file to product image directory.
  my $product_dir = path( config->{ appdir }, sprintf( 'public/images/products/%s/', $product_id ) );
  mkdir $product_dir if not -e $product_dir;

  my $filepath = $product_dir . '/' . $upload_data->basename;
  my $copied = $upload_data->copy_to( $filepath );

  if ( ! $copied )
  {
    return to_json( { success => 0, error => 'Could not save file to the filesystem.', preventRetry => 1 } );
  }

  # Create Thumbnails - Small: max 250px w, Med: max 400px w, Large: max 650px w
  my @thumbs_config = (
    { max => 250, prefix => 's', rules => { square => 'crop' } },
    { max => 400, prefix => 'm', rules => { square => 'crop' } },
    { max => 650, prefix => 'l', rules => { square => 'crop', dimension_constraint => 1 } },
  );

  foreach my $thumb ( @thumbs_config )
  {
    my $thumbnail = GD::Thumbnail->new( %{$thumb->{rules}} );
    my $raw       = $thumbnail->create( $product_dir . '/' . $upload_data->basename, $thumb->{max}, undef );
    my $mime      = $thumbnail->mime;
    open    IMG, sprintf( '>%s/%s-%s', $product_dir, $thumb->{prefix}, $upload_data->basename );
    binmode IMG;
    print   IMG $raw;
    close   IMG;
  }

  # Save new database record of image associated to product.
  my $new_image = $SCHEMA->resultset( 'ProductImage' )->create(
    {
      product_id => $product_id,
      filename   => $upload_data->basename,
      highlight  => 0,
      created_on => DateTime->now( time_zone => 'America/New_York' )->datetime,
    },
  );

  return to_json( { success => 1 } );
};


=head2 POST C</admin/manage_products/:product_id/images/update>

Route for updating the highlighted image on a product. Requires Admin user.

=cut

post '/admin/manage_products/:product_id/images/update' => require_role Admin => sub
{
  my $product_id = route_parameters->get( 'product_id' );
  my $new_highlight_id = body_parameters->get( 'highlight' );

  if ( ! $new_highlight_id )
  {
    flash notify => 'No highlighted image selected.';
    redirect sprintf( '/admin/manage_products/%s/edit', $product_id );
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $highlighted_image = $SCHEMA->resultset( 'ProductImage' )->find( { product_id => $product_id, highlight => 1 } );
  if
  (
    defined $highlighted_image
    and
    ref( $highlighted_image ) eq 'QP::Schema::Result::ProductImage'
  )
  {
    if ( $highlighted_image->id == $new_highlight_id )
    {
      flash notify => 'Highlighted image unchanged.';
      redirect sprintf( '/admin/manage_products/%s/edit', $product_id );
    }
    else
    {
      $highlighted_image->highlight( 0 );
      $highlighted_image->updated_on( $now );
      $highlighted_image->update;
    }
  }

  my $new_highlight = $SCHEMA->resultset( 'ProductImage' )->find( $new_highlight_id );
  $new_highlight->highlight( 1 );
  $new_highlight->updated_on( $now );
  $new_highlight->update;

  flash success => sprintf( 'Highlighted Image set to <strong>%s</strong>.', $new_highlight->filename );
  redirect sprintf( '/admin/manage_products/%s/edit', $product_id );
};


=head2 GET C</admin/manage_product_categories>

Route to manage product categories and subcategories. Requires user to be logged in and an Admin.

=cut

get '/admin/manage_product_categories' => require_role Admin => sub
{
  my @product_categories = $SCHEMA->resultset( 'ProductCategory' )->search( undef,
                                                                            { order_by => { -asc => 'category' } }
                                                                          );
  my @product_subcategories = $SCHEMA->resultset( 'ProductSubcategory' )->search( undef,
                                                                                  { order_by => { -asc => 'subcategory' } }
                                                                                );
  template 'admin_manage_product_categories',
      {
        data =>
        {
          product_categories    => \@product_categories,
          product_subcategories => \@product_subcategories,
        },
        breadcrumbs =>
        [
          { name => 'Admin', link => '/admin' },
          { name => 'Manage Product Categories and Subcategories', current => 1 },
        ],
        title => 'Manage Product Categories and Subcategories',
      };
};


=head2 POST C</admin/manage_product_categories/add>

Route for adding a new product category. Requires user is logged in and an Admin.

=cut

post '/admin/manage_product_categories/add' => require_role Admin => sub
{
  my $form_input = body_parameters->as_hashref;

  my $form_results = $DATA_FORM_VALIDATOR->check( $form_input, 'admin_new_product_category_form' );

  if ( $form_results->has_invalid or $form_results->has_missing )
  {
    my @errors = ();
    for my $invalid ( $form_results->invalid )
    {
      push( @errors, sprintf( "<strong>%s</strong> is invalid: %s<br>", $invalid, $form_results->invalid( $invalid ) ) );
    }

    for my $missing ( $form_results->missing )
    {
      push( @errors, sprintf( "<strong>%s</strong> needs to be filled out.<br>", $missing ) );
    }

    flash( error => sprintf( "Errors have occurred in your product category information.<br>%s", join( '<br>', @errors ) ) );
    redirect '/admin/manage_product_categories';
  }

  my $category_exists  = $SCHEMA->resultset( 'ProductCategory' )->count( { category  => body_parameters->get( 'category' ) } );
  my $shorthand_exists = $SCHEMA->resultset( 'ProductCategory' )->count( { shorthand => body_parameters->get( 'shorthand' ) } );

  if ( $category_exists )
  {
    flash error => sprintf( 'A category called &quot;<strong>%s</strong>&quot; already exists.', body_parameters->get( 'category' ) );
    redirect '/admin/manage_product_categories';
  }

  if ( $shorthand_exists )
  {
    flash error => sprintf( 'A category with shorthand &quot;<strong>%s</strong>&quot; already exists.', body_parameters->get( 'shorthand' ) );
    redirect '/admin/manage_product_categories';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  my $new_product_category = $SCHEMA->resultset( 'ProductCategory' )->create(
    {
      category   => body_parameters->get( 'category' ),
      shorthand  => body_parameters->get( 'shorthand' ),
      created_on => $now,
    }
  );

  if
  (
    not defined $new_product_category
    or
    ref( $new_product_category ) ne 'QP::Schema::Result::ProductCategory'
  )
  {
    flash error => sprintf( 'Something went wrong. Could not save Product Category &quot;<strong>%s</strong>&quot;.', body_parameters->get( 'category' ) );
    redirect '/admin/manage_product_categories';
  }

  info sprintf( 'Created new product category >%s<, ID: >%s<, on %s', body_parameters->get( 'category' ), $new_product_category->id, $now );

  flash success => sprintf( 'Successfully created Product Category &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'category' ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Product Category &quot;%s&quot; created', body_parameters->get( 'category' ) ),
  );

  redirect '/admin/manage_product_categories';
};


=head2 GET C</admin/manage_product_categories/:product_category_id/delete>

Route to delete a product category. Requires the user to be logged in and an Admin.

=cut

get '/admin/manage_product_categories/:product_category_id/delete' => require_role Admin => sub
{
  my $product_category_id = route_parameters->get( 'product_category_id' );

  my $product_category = $SCHEMA->resultset( 'ProductCategory' )->find( $product_category_id );

  if
  (
    not defined $product_category
    or
    ref( $product_category ) ne 'QP::Schema::Result::ProductCategory'
  )
  {
    flash error => sprintf( 'Unknown or invalid product category.' );
    redirect '/admin/manage_product_categories';
  }

  my @subcategories = $product_category->product_subcategories;
  if ( scalar( @subcategories ) > 0 )
  {
    flash error => sprintf( 'Unable to delete product category &quot;<strong>%s</strong>&quot;. It still has associated subcategories.<br>Remove or reassign those subcategories, first.',
                                $product_category->category );
    redirect '/admin/manage_product_categories';
  }

  my $category = $product_category->category;

  my $deleted = $product_category->delete();
  if ( defined $deleted and $deleted < 1 )
  {
    flash error => sprintf( 'Unabled to delete product category &quot;<strong>%s</strong>&quot;.', $product_category->category );
    redirect '/admin/manage_product_categories';
  }

  flash success => sprintf( 'Successfully deleted product category &quot;<strong>%s</strong>&quot;.', $category );

  info sprintf( 'Deleted product category >%s<, ID: >%s<, on %s', $category, $product_category_id, DateTime->now( time_zone => 'America/New_York' )->datetime );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Product Category &quot;%s&quot; deleted', $category ),
  );

  redirect '/admin/manage_product_categories';
};


=head2 GET C</admin/manage_product_categories/:product_category_id/edit>

Route to the product category edit form. Requires a logged in user with Admin role.

=cut

get '/admin/manage_product_categories/:product_category_id/edit' => require_role Admin => sub
{
  my $product_category_id = route_parameters->get( 'product_category_id' );

  my $product_category = $SCHEMA->resultset( 'ProductCategory' )->find( $product_category_id );

  if
  (
    not defined $product_category
    or
    ref( $product_category ) ne 'QP::Schema::Result::ProductCategory'
  )
  {
    flash error => sprintf( 'Unknown or invalid product category.' );
    redirect '/admin/manage_product_categories';
  }

  template 'admin_manage_product_categories_edit.tt',
    {
      data =>
      {
        product_category => $product_category,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage Product Categories and Subcategories', link => '/admin/manage_product_categories' },
        { name => sprintf( 'Edit Product Category (%s)', $product_category->category ), current => 1 },
      ],
      title => 'Edit Product Category',
    };
};


=head2 POST C</admin/manage_product_categories/:product_category_id/update>

Route to save updated product category information. Requires logged in user to be Admin.

=cut

post '/admin/manage_product_categories/:product_category_id/update' => require_role Admin => sub
{
  my $product_category_id = route_parameters->get( 'product_category_id' );

  my $form_input = body_parameters->as_hashref;
  my $form_results = $DATA_FORM_VALIDATOR->check( $form_input, 'admin_edit_product_category_form' );

  if ( $form_results->has_invalid or $form_results->has_missing )
  {
    my @errors = ();
    for my $invalid ( $form_results->invalid )
    {
      push( @errors, sprintf( "<strong>%s</strong> is invalid: %s<br>", $invalid, $form_results->invalid( $invalid ) ) );
    }

    for my $missing ( $form_results->missing )
    {
      push( @errors, sprintf( "<strong>%s</strong> needs to be filled out.<br>", $missing ) );
    }

    flash( error => sprintf( "Errors have occurred in your product category information.<br>%s", join( '<br>', @errors ) ) );
    redirect '/admin/manage_product_categories';
  }

  my $category_exists  = $SCHEMA->resultset( 'ProductCategory' )->count(
    {
      category  => body_parameters->get( 'category' )
    },
    {
      where =>
      {
        id => { '!=' => $product_category_id },
      },
    },
  );
  my $shorthand_exists = $SCHEMA->resultset( 'ProductCategory' )->count(
    {
      shorthand => body_parameters->get( 'shorthand' ),
    },
    {
      where =>
      {
        id => { '!=' => $product_category_id },
      },
    },
  );

  if ( $category_exists )
  {
    flash error => sprintf( 'A category called &quot;<strong>%s</strong>&quot; already exists.', body_parameters->get( 'category' ) );
    redirect '/admin/manage_product_categories';
  }

  if ( $shorthand_exists )
  {
    flash error => sprintf( 'A category with shorthand &quot;<strong>%s</strong>&quot; already exists.', body_parameters->get( 'shorthand' ) );
    redirect '/admin/manage_product_categories';
  }

  my $product_category = $SCHEMA->resultset( 'ProductCategory' )->find( $product_category_id );

  my $orig_product_category = Clone::clone( $product_category );

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $product_category->category( body_parameters->get( 'category' ) );
  $product_category->shorthand( body_parameters->get( 'shorthand' ) );
  $product_category->updated_on( $now );

  $product_category->update;

  flash success => sprintf( 'Successfully updated product category &quot;<strong>%s</strong>&quot;.', $product_category->category );

  info sprintf( 'Updated product category >%s<, ID: >%s<, on %s', $product_category->category, $product_category_id, $now );

  my $new =
  {
    category  => body_parameters->get( 'category' ),
    shorthand => body_parameters->get( 'shorthand' )
  };
  my $old =
  {
    category  => $orig_product_category->category,
    shorthand => $orig_product_category->shorthand
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Product Category updated: %s', join( ', ', @{ $diffs } ) ),
  );

  redirect '/admin/manage_product_categories';
};


=head2 POST C</admin/manage_product_categories/subcategory/add>

Route for adding a new product subcategory. Requires user is logged in and an Admin.

=cut

post '/admin/manage_product_categories/subcategory/add' => require_role Admin => sub
{
  my $form_input = body_parameters->as_hashref;

  my $form_results = $DATA_FORM_VALIDATOR->check( $form_input, 'admin_new_product_subcategory_form' );

  if ( $form_results->has_invalid or $form_results->has_missing )
  {
    my @errors = ();
    for my $invalid ( $form_results->invalid )
    {
      push( @errors, sprintf( "<strong>%s</strong> is invalid: %s<br>", $invalid, $form_results->invalid( $invalid ) ) );
    }

    for my $missing ( $form_results->missing )
    {
      push( @errors, sprintf( "<strong>%s</strong> needs to be filled out.<br>", $missing ) );
    }

    flash( error => sprintf( "Errors have occurred in your product subcategory information.<br>%s", join( '<br>', @errors ) ) );
    redirect '/admin/manage_product_categories';
  }

  my $subcategory_exists  = $SCHEMA->resultset( 'ProductSubcategory' )->count
  (
    {
      subcategory  => body_parameters->get( 'subcategory' ),
      category_id  => body_parameters->get( 'category_id' )
    }
  );

  if ( $subcategory_exists )
  {
    flash error => sprintf( 'A subcategory called &quot;<strong>%s</strong>&quot; already exists.', body_parameters->get( 'subcategory' ) );
    redirect '/admin/manage_product_categories';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  my $new_product_subcategory = $SCHEMA->resultset( 'ProductSubcategory' )->create(
    {
      subcategory => body_parameters->get( 'subcategory' ),
      category_id => body_parameters->get( 'category_id' ),
      created_on  => $now,
    }
  );

  if
  (
    not defined $new_product_subcategory
    or
    ref( $new_product_subcategory ) ne 'QP::Schema::Result::ProductSubcategory'
  )
  {
    flash error => sprintf( 'Something went wrong. Could not save Product Subcategory &quot;<strong>%s</strong>&quot;.', body_parameters->get( 'subcategory' ) );
    redirect '/admin/manage_product_categories';
  }

  info sprintf( 'Created new product subcategory >%s<, ID: >%s<, on %s', body_parameters->get( 'subcategory' ), $new_product_subcategory->id, $now );

  flash success => sprintf( 'Successfully created Product Subcategory &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'subcategory' ) );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Product Subcategory &quot;%s&quot; (%s) created', body_parameters->get( 'subcategory' ), $new_product_subcategory->id ),
  );

  redirect '/admin/manage_product_categories';
};


=head2 GET C</admin/manage_product_categories/subcategory/:product_subcategory_id/delete>

Route to delete a product subcategory. Requires the user to be logged in and an Admin.

=cut

get '/admin/manage_product_categories/subcategory/:product_subcategory_id/delete' => require_role Admin => sub
{
  my $product_subcategory_id = route_parameters->get( 'product_subcategory_id' );

  my $product_subcategory = $SCHEMA->resultset( 'ProductSubcategory' )->find( $product_subcategory_id );

  if
  (
    not defined $product_subcategory
    or
    ref( $product_subcategory ) ne 'QP::Schema::Result::ProductSubcategory'
  )
  {
    flash error => sprintf( 'Unknown or invalid product subcategory.' );
    redirect '/admin/manage_product_categories';
  }

  my @products = $product_subcategory->products;
  if ( scalar( @products ) > 0 )
  {
    flash error => sprintf( 'Unable to delete product subcategory &quot;<strong>%s</strong>&quot;. It still has associated products.<br>Remove or reassign those products, first.',
                                $product_subcategory->subcategory );
    redirect '/admin/manage_product_categories';
  }

  my $subcategory = $product_subcategory->subcategory;

  my $deleted = $product_subcategory->delete();
  if ( defined $deleted and $deleted < 1 )
  {
    flash error => sprintf( 'Unabled to delete product subcategory &quot;<strong>%s</strong>&quot;.', $product_subcategory->subcategory );
    redirect '/admin/manage_product_categories';
  }

  flash success => sprintf( 'Successfully deleted product subcategory &quot;<strong>%s</strong>&quot;.', $subcategory );

  info sprintf( 'Deleted product subcategory >%s<, ID: >%s<, on %s', $subcategory, $product_subcategory_id, DateTime->now( time_zone => 'America/New_York' )->datetime );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Product Subcategory &quot;%s&quot; (%s) deleted.', $subcategory, $product_subcategory_id ),
  );

  redirect '/admin/manage_product_categories';
};


=head2 GET C</admin/manage_product_categories/subcategory/:product_subcategory_id/edit>

Route to the product subcategory edit form. Requires a logged in user with Admin role.

=cut

get '/admin/manage_product_categories/subcategory/:product_subcategory_id/edit' => require_role Admin => sub
{
  my $product_subcategory_id = route_parameters->get( 'product_subcategory_id' );

  my $product_subcategory = $SCHEMA->resultset( 'ProductSubcategory' )->find( $product_subcategory_id );

  if
  (
    not defined $product_subcategory
    or
    ref( $product_subcategory ) ne 'QP::Schema::Result::ProductSubcategory'
  )
  {
    flash error => sprintf( 'Unknown or invalid product subcategory.' );
    redirect '/admin/manage_product_categories';
  }

  my @product_categories = $SCHEMA->resultset( 'ProductCategory' )->search( undef,
                                                                            { order_by => { -asc => 'category' } }
                                                                          );

  template 'admin_manage_product_subcategories_edit.tt',
    {
      data =>
      {
        product_categories  => \@product_categories,
        product_subcategory => $product_subcategory,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage Product Categories and Subcategories', link => '/admin/manage_product_categories' },
        { name => sprintf( 'Edit Product Subcategory (%s)', $product_subcategory->subcategory ), current => 1 },
      ],
      title => 'Manage Product Subcategories',
    };
};


=head2 POST C</admin/manage_product_categories/subcategory/:product_subcategory_id/update>

Route to save updated product subcategory information. Requires logged in user to be Admin.

=cut

post '/admin/manage_product_categories/subcategory/:product_subcategory_id/update' => require_role Admin => sub
{
  my $product_subcategory_id = route_parameters->get( 'product_subcategory_id' );

  my $form_input = body_parameters->as_hashref;
  my $form_results = $DATA_FORM_VALIDATOR->check( $form_input, 'admin_edit_product_subcategory_form' );

  if ( $form_results->has_invalid or $form_results->has_missing )
  {
    my @errors = ();
    for my $invalid ( $form_results->invalid )
    {
      push( @errors, sprintf( "<strong>%s</strong> is invalid: %s<br>", $invalid, $form_results->invalid( $invalid ) ) );
    }

    for my $missing ( $form_results->missing )
    {
      push( @errors, sprintf( "<strong>%s</strong> needs to be filled out.<br>", $missing ) );
    }

    flash( error => sprintf( "Errors have occurred in your product subcategory information.<br>%s", join( '<br>', @errors ) ) );
    redirect '/admin/manage_product_categories';
  }

  my $subcategory_exists  = $SCHEMA->resultset( 'ProductSubcategory' )->count(
    {
      subcategory  => body_parameters->get( 'subcategory' )
    },
    {
      where =>
      {
        id => { '!=' => $product_subcategory_id },
      },
    },
  );

  if ( $subcategory_exists )
  {
    flash error => sprintf( 'A subcategory called &quot;<strong>%s</strong>&quot; already exists.', body_parameters->get( 'subcategory' ) );
    redirect '/admin/manage_product_categories';
  }

  my $product_subcategory = $SCHEMA->resultset( 'ProductSubcategory' )->find( $product_subcategory_id );
  my $orig_product_subcategory = Clone::clone( $product_subcategory );

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $product_subcategory->subcategory( body_parameters->get( 'subcategory' ) );
  $product_subcategory->category_id( body_parameters->get( 'category_id' ) );
  $product_subcategory->updated_on( $now );

  $product_subcategory->update;

  flash success => sprintf( 'Successfully updated product subcategory &quot;<strong>%s</strong>&quot;.', $product_subcategory->subcategory );

  info sprintf( 'Updated product category >%s<, ID: >%s<, on %s', $product_subcategory->subcategory, $product_subcategory_id, $now );

  my $new =
  {
    subcategory => body_parameters->get( 'subcategory' ),
    category_id => body_parameters->get( 'category_id' )
  };
  my $old =
  {
    subcategory => $orig_product_subcategory->subcategory,
    category_id => $orig_product_subcategory->category_id
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Product Subcategory updated: %s', join( ', ', @{ $diffs } ) ),
  );

  redirect '/admin/manage_product_categories';
};


=head2 GET C</admin/manage_featured_products>

Route to manage which Products are featured for each subcategory. Requires Admin.

=cut

get '/admin/manage_featured_products' => require_role Admin => sub
{
  my @products = $SCHEMA->resultset( 'Product' )->search( {},
    {
      order_by => [ 'product_category.category', 'product_subcategory.subcategory', 'me.name' ],
      prefetch =>
      [
        { 'product_subcategory' => 'product_category' },
        'featured_product',
      ],
    },
  );

  template 'admin_manage_featured_products',
  {
    data =>
    {
      products => \@products,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Featured Products', current => 1 },
    ],
    title => 'Manage Featured Products',
  };
};

=head2 POST C</admin/manage_product_categories/update>

Route to update all featured product entries. Requires Admin access.

=cut

post '/admin/manage_featured_products/update' => require_role Admin => sub
{
  my $form_input = body_parameters->as_hashref;

  my @updated = ();
  foreach my $key ( sort keys %{$form_input} )
  {
    if ( $key =~ m/^(featured_)(\d+)_old$/ )
    {
      if
      (
        $form_input->{$1.$2} ne $form_input->{$key}
        or
        $form_input->{'expires_on_' . $2} ne $form_input->{'expires_on_' . $2 . '_old'}
      )
      {
        # If featured_n = 1, update or create it. Otherwise, delete it.
        if ( $form_input->{$1.$2} == 1 )
        {
          my $featured_product = $SCHEMA->resultset( 'FeaturedProduct' )->update_or_create(
            {
              product_id             => $2,
              product_subcategory_id => $form_input->{'product_subcategory_id_' . $2},
              expires_on             => ( $form_input->{'expires_on_' . $2} ) ? $form_input->{'expires_on_' . $2} : undef,
              created_on             => ( $form_input->{'created_on_' . $2} ) ? $form_input->{'created_on_' . $2}
                                                                              : DateTime->today( time_zone => 'America/New_York' )->datetime,
            },
            { key => 'productid_subcategoryid' },
          );

          push( @updated, sprintf( 'Featuring &quot;<strong>%s</strong>&quot;', $featured_product->product->name ) );
        }
        else
        {
          my $featured_product = $SCHEMA->resultset( 'FeaturedProduct' )->find(
            {
              product_id             => $2,
              product_subcategory_id => $form_input->{'product_subcategory_id_' . $2},
            }
          );

          push( @updated, sprintf( 'Unfeatured &quot;<strong>%s</strong>&quot;', $featured_product->product->name ) );

          $featured_product->delete;
        }
      }
    }
  }

  flash success => join( '<br>', @updated );

  redirect '/admin/manage_featured_products';
};


=head2 GET C</admin/manage_news>

Route to managing news items.  Requires Admin user.

=cut

get '/admin/manage_news' => require_role Admin => sub
{
  my @news = $SCHEMA->resultset( 'News' )->search(
    {},
    {
      order_by => [ 'timestamp', 'expires' ],
    },
  );

  template 'admin_manage_news.tt',
    {
      data =>
      {
        news => \@news,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage News', current => 1 },
      ],
      title => 'Manage News',
    }
};


=head2 GET C</admin/manage_news/add>

Route for add new news item form. Requires Admin user.

=cut

get '/admin/manage_news/add' => require_role Admin => sub
{
  template 'admin_manage_news_add_form.tt',
    {
      breadcrumbs =>
      [
        { name => 'Admin',       link => '/admin' },
        { name => 'Manage News', link => '/admin/manage_news' },
        { name => 'Add New News Item', current => 1 },
      ],
      title => 'Add News',
    },
};


=head2 POST C</admin/manage_news/create>

Route to save new news item to the database. Requires Admin.

=cut

post '/admin/manage_news/create' => require_role Admin => sub
{
  my $form_input = body_parameters->as_hashref;

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  my $new_news = $SCHEMA->resultset( 'News' )->create(
    {
      title           => body_parameters->get( 'title' ),
      blurb           => ( body_parameters->get( 'blurb' ) || undef ),
      article         => body_parameters->get( 'article' ),
      expires         => body_parameters->get( 'expires' ),
      static          => 1,
      priority        => 1,
      user_account_id => logged_in_user->id,
      views           => 0,
      timestamp       => $now,
    },
  );

  if
  (
    ! defined $new_news
    or
    ref( $new_news ) ne 'QP::Schema::Result::News'
  )
  {
    flash( error => 'An error occurred and the news item could not be saved.' );
    redirect '/admin/manage_news';
  };

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new news item >%s<, ID: >%s<, on %s', body_parameters->get( 'title' ), $new_news->id, $now );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new news item:<br>%s', join( '<br>', @fields ) ),
  );

  flash( success => sprintf( 'Your new news item &quot;<strong>%s</strong>&quot; was saved.',
                                body_parameters->get( 'title' ) ) );

  redirect '/admin/manage_news';
};


=head2 GET C</admin/manage_news/:item_id/edit>

Route to edit a news item. Requires Admin.

=cut

get '/admin/manage_news/:item_id/edit' => require_role Admin => sub
{
  my $item_id = route_parameters->get( 'item_id' );

  my $item = $SCHEMA->resultset( 'News' )->find( $item_id );

  if
  (
    not defined $item
    or
    ref( $item ) ne 'QP::Schema::Result::News'
  )
  {
    flash( error => 'Invalid or unknown news item to edit.' );
    redirect '/admin/manage_news';
  }

  template 'admin_manage_news_edit_form',
    {
      data =>
      {
        item => $item,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage News', link => '/admin/manage_news' },
        { name => 'Edit News Item', current => 1 },
      ],
      title => 'Edit News',
    };
};


=head2 POST C</admin/manage_news/:item_id/update>

Route to update a news item record. Requires Admin access.

=cut

post '/admin/manage_news/:item_id/update' => require_role Admin => sub
{
  my $item_id = route_parameters->get( 'item_id' );

  my $item = $SCHEMA->resultset( 'News' )->find( $item_id );
  my $orig_item = Clone::clone( $item );

  if
  (
    not defined $item
    or
    ref( $item ) ne 'QP::Schema::Result::News'
  )
  {
    flash( error => 'Error: Cannot update news item - Invalid or unknown ID.' );
    redirect '/admin/manage_news';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $item->title( body_parameters->get( 'title' ) );
  $item->article( body_parameters->get( 'article' ) );
  $item->blurb( ( body_parameters->get( 'blurb' ) || undef ) );
  $item->expires( body_parameters->get( 'expires' ) );

  $item->update();

  info sprintf( 'News article >%s< updated by %s on %s.', $item->title, logged_in_user->username, $now );

  my $old =
  {
    title   => $orig_item->title,
    article => $orig_item->article,
    blurb   => $orig_item->blurb,
    expires => $orig_item->expires,
  };
  my $new =
  {
    title   => body_parameters->get( 'title' ),
    article => body_parameters->get( 'article' ),
    blurb   => body_parameters->get( 'blurb' ),
    expires => body_parameters->get( 'expires' ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'News article modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated news item &quot;<strong>%s</strong>&quot;.',
                                body_parameters->get( 'title' ) ) );
  redirect '/admin/manage_news';
};


=head2 POST C</admin/manage_news/:item_id/delete>

Route to delete a news item record. Requires Admin access.

=cut

get '/admin/manage_news/:item_id/delete' => require_role Admin => sub
{
  my $item_id    = route_parameters->get( 'item_id' );

  my $item = $SCHEMA->resultset( 'News' )->find( $item_id );

  if
  (
    not defined $item
    or
    ref( $item ) ne 'QP::Schema::Result::News'
  )
  {
    flash error => 'Error: Cannot delete news item - Invalid or unknown ID.';
    redirect '/admin/manage_news';
  }

  my $title = $item->title;
  $item->delete;

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'News Article &quot;%s&quot; deleted', $title ),
  );

  flash success => sprintf( 'Successfully deleted news item &quot;<strong>%s</strong>&quot;.', $title );
  redirect '/admin/manage_news';
};


=head2 GET C</admin/manage_events>

Route to manage calendar events. Requires Admin access.

=cut

get '/admin/manage_events' => require_role Admin => sub
{
  my @events = $SCHEMA->resultset( 'Event' )->search(
    {},
    {
      order_by => { -desc => [ 'start_datetime' ] },
    }
  );

  template 'admin_manage_events',
    {
      data =>
      {
        events => \@events,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage Events', current => 1 },
      ],
      title => 'Manage Events',
    };
};


=head2 GET C</admin/manage_events/add>

Route to get the form for creating a new calendar event. Admin access required.

=cut

get '/admin/manage_events/add' => require_role Admin => sub
{
  template 'admin_manage_events_add_form',
    {
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage Events', link => '/admin/manage_events' },
        { name => 'Add New Calendar Event', current => 1 },
      ],
      title => 'Add Event',
    };
};


=head2 POST C</admin/manage_events/create>

Route to save new event. Requires Admin access.

=cut

post '/admin/manage_events/create' => require_role Admin => sub
{
  my $form_input = body_parameters->as_hashref;

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  my $new_event = $SCHEMA->resultset( 'Event' )->create
  (
    {
      title          => body_parameters->get( 'title' ),
      description    => body_parameters->get( 'description' ),
      start_datetime => body_parameters->get( 'start_datetime' ),
      end_datetime   => body_parameters->get( 'end_datetime' ),
      is_private     => ( ( body_parameters->get( 'is_private' ) == 1 ) ? 'true' : 'false' ),
      event_type     => body_parameters->get( 'event_type' ),
    }
  );

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new calendar event >%s<, ID: >%s<, on %s', body_parameters->get( 'title' ), $new_event->id, $now );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new calendar event:<br>%s', join( '<br>', @fields ) ),
  );

  flash success => sprintf( 'Calendar Event &quot;<strong>%s</strong>&quot; was successfully created.', body_parameters->get( 'title' ) );
  redirect '/admin/manage_events';
};


=head2 GET C</admin/manage_events/:event_id/edit>

Route to edit the content of a calendar event. Requires Admin.

=cut

get '/admin/manage_events/:event_id/edit' => require_role Admin => sub
{
  my $event_id = route_parameters->get( 'event_id' );

  my $event = $SCHEMA->resultset( 'Event' )->find( $event_id );

  if
  (
    ! defined $event
    or
    ref( $event ) ne 'QP::Schema::Result::Event'
  )
  {
    flash error => 'Could not find the requested calendar event. Invalid or undefined event ID.';
    redirect '/admin/manage_events';
  }

  template 'admin_manage_events_edit_form',
    {
      data =>
      {
        event => $event,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage Events', link => '/admin/manage_events' },
        { name => 'Edit Calendar Event', current => 1 },
      ],
    };
};


=head2 POST C</admin/manage_events/:event_id/update>

Route to save changes made to a calendar Event. Admin access required.

=cut

post '/admin/manage_events/:event_id/update' => require_role Admin => sub
{
  my $form_input = body_parameters->as_hashref;

  my $event_id = route_parameters->get( 'event_id' );

  my $event = $SCHEMA->resultset( 'Event' )->find( $event_id );
  my $orig_event = Clone::clone( $event );

  if
  (
    ! defined $event
    or
    ref( $event ) ne 'QP::Schema::Result::Event'
  )
  {
    flash error => 'Could not find the requested calendar event. Invalid or undefined event ID.';
    redirect '/admin/manage_events';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $event->title( body_parameters->get( 'title' ) );
  $event->start_datetime( body_parameters->get( 'start_datetime' ) );
  $event->end_datetime( body_parameters->get( 'end_datetime' ) );
  $event->description( ( body_parameters->get( 'description' ) // undef ) );
  $event->is_private( ( body_parameters->get( 'is_private' ) == 1 ? 'true' : 'false' ) );
  $event->event_type( body_parameters->get( 'event_type' ) );
  $event->update;

  info sprintf( 'Calendar event >%s< updated by %s on %s.', $event->title, logged_in_user->username, $now );

  my $old =
  {
    title          => $orig_event->title,
    description    => $orig_event->description,
    start_datetime => $orig_event->start_datetime,
    end_datetime   => $orig_event->end_datetime,
    is_private     => $orig_event->is_private,
    event_type     => $orig_event->event_type,
  };
  my $new =
  {
    title          => body_parameters->get( 'title' ),
    description    => body_parameters->get( 'description' ),
    start_datetime => body_parameters->get( 'start_datetime' ),
    end_datetime   => body_parameters->get( 'end_datetime' ),
    is_private     => body_parameters->get( 'is_private' ),
    event_type     => body_parameters->get( 'event_type' ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Calendar event modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash success => sprintf( 'Calendar Event &quot;<strong>%s</strong>&quot; has been successfully updated.', body_parameters->get( 'title' ) );
  redirect '/admin/manage_events';
};


=head2 GET C</admin/manage_events/:event_id/delete>

Route to delete a calendar event. Admin access required.

=cut

get '/admin/manage_events/:event_id/delete' => require_role Admin => sub
{
  my $event_id = route_parameters->get( 'event_id' );

  my $event = $SCHEMA->resultset( 'Event' )->find( $event_id );

  if
  (
    ! defined $event
    or
    ref( $event ) ne 'QP::Schema::Result::Event'
  )
  {
    flash error => 'Could not find the requested calendar event. Invalid or undefined event ID.';
    redirect '/admin/manage_events';
  }

  my $event_name = $event->title;
  $event->delete;

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Calendar Event &quot;%s&quot; deleted', $event_name ),
  );

  flash success => sprintf( 'Calendar Event &quot;<strong>%s</strong>&quot; has been successfully deleted.', $event_name );

  redirect '/admin/manage_events';
};


=head2 GET C</admin/admin_logs>

Route to view admin logs. Requires Admin Access.

=cut

get '/admin/admin_logs' => require_role Admin => sub
{
  my @logs = $SCHEMA->resultset( 'AdminLog' )->search(
    undef,
    {
      order_by => [ 'created_on' ],
    },
  );

  template 'admin_logs',
    {
      title => 'Admin Logs',
      data =>
      {
        logs => \@logs,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Admin Logs', current => 1 },
      ],
    };
};


=head2 GET C</admin/user_logs>

Route to view user logs. Requires Admin Access.

=cut

get '/admin/user_logs' => require_role Admin => sub
{
  my @logs = $SCHEMA->resultset( 'UserLog' )->search(
    undef,
    {
      order_by => [ 'created_on' ],
    },
  );

  template 'user_logs',
    {
      title => 'User Logs',
      data =>
      {
        logs => \@logs,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'User Logs', current => 1 },
      ],
    };
};


=head2 GET C</admin/manage_users>

Route to manage user account data. Requires Admin access.

=cut

get '/admin/manage_users' => require_role Admin => sub
{
  my @users = $SCHEMA->resultset( 'User' )->search(
    {},
    {
      order_by => [ 'username' ],
      prefetch =>
      {
        userroles => 'role',
      },
    }
  )->all;

  template 'admin_manage_users',
    {
      data =>
      {
        users => \@users,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage User Accounts', current => 1 },
      ],
    };
};


=head2 GET C</admin/manage_users/add>

Route to the add user account form. Requires Admin access.

=cut

get '/admin/manage_users/add' => require_role Admin => sub
{
  my @roles = $SCHEMA->resultset( 'Role' )->search( undef, { order_by => [ 'role' ] } );

  template 'admin_manage_users_add_form',
    {
      data =>
      {
        roles => \@roles,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage User Accounts', link => '/admin/manage_users' },
        { name => 'Create User Account', current => 1 },
      ],
    };
};


=head2 POST C</admin/manage_users/create>

Route to save the new account data to the database. Requires Admin access.

=cut

post '/admin/manage_users/create' => require_role Admin => sub
{
  my $form_input = body_parameters->as_hashref;

  my $form_results = $DATA_FORM_VALIDATOR->check( $form_input, 'admin_add_user_form' );

  if ( $form_results->has_invalid or $form_results->has_missing )
  {
    my @errors = ();
    for my $invalid ( $form_results->invalid )
    {
      push( @errors, sprintf( "<strong>%s</strong> is invalid: %s<br>", $invalid, $form_results->invalid( $invalid ) ) );
    }

    for my $missing ( $form_results->missing )
    {
      push( @errors, sprintf( "<strong>%s</strong> needs to be filled out.<br>", $missing ) );
    }

    flash( error => sprintf( "Errors have occurred in your user account information.<br>%s", join( '<br>', @errors ) ) );
    redirect '/';
  }

  my $send_confirmation = ( body_parameters->get( 'confirmed' ) == 1 ) ? 1 : 0;
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  # Create the user, and send the welcome e-mail.
  my $new_user = create_user(
                              username      => body_parameters->get( 'username' ),
                              realm         => $DPAE_REALM,
                              first_name    => ( defined body_parameters->get( 'first_name' )
                                                  ? body_parameters->get( 'first_name' ) : undef ),
                              last_name     => ( defined body_parameters->get( 'last_name' )
                                                  ? body_parameters->get( 'last_name' ) : undef ),
                              password      => body_parameters->get( 'password' ),
                              email         => body_parameters->get( 'email' ),
                              birthdate     => body_parameters->get( 'birthdate' ),
                              confirmed     => ( defined body_parameters->get( 'confirmed' ) ? 1 : 0 ),
                              confirm_code  => ( defined body_parameters->get( 'confirmed' )
                                                  ? undef : QP::Util->generate_random_string() ),
                              created_on    => $now,
                              email_welcome => $send_confirmation,
                            );

  # Set the passord, encrypted.
  my $set_password = user_password( username => body_parameters->get( 'username' ), new_password => body_parameters->get( 'password' ) );

  # Set the initial user_role
  my $unconfirmed_role = $SCHEMA->resultset( 'Role' )->find( { role => 'Unconfirmed' } );
  my $confirmed_role   = $SCHEMA->resultset( 'Role' )->find( { role => 'Confirmed' } );

  my $user_role = $SCHEMA->resultset( 'UserRole' )->new(
                                                        {
                                                          user_id => $new_user->id,
                                                          role_id => ( defined body_parameters->get( 'confirmed' )
                                                                      ? $confirmed_role->id
                                                                      : $unconfirmed_role->id ),
                                                        }
                                                       );
  $SCHEMA->txn_do(
                  sub
                  {
                    $user_role->insert;
                  }
  );

  flash success => sprintf( 'Successfully created user &quot;<strong>%s</strong>&quot;.', body_parameters->get( 'username' ) );

  my $fields = body_parameters->as_hashref;
  my @field_values;
  foreach my $key ( sort keys %{ $fields } )
  {
    if ( lc( $key ) ne 'password' )
    {
      push @field_values, sprintf( '%s: %s', $key, $fields->{$key} );
    }
  }

  info sprintf( 'Created new user account >%s<, ID: >%s<, on %s', body_parameters->get( 'username' ), $new_user->id, $now );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new user account<br>%s', join( '<br>', @field_values ) ),
  );
  redirect '/admin/manage_users';
};


=head2 GET C</admin/manage_users/:user_id/edit>

Route to load up an edit form for a user. Admin access required.

=cut

get '/admin/manage_users/:user_id/edit' => require_role Admin => sub
{
  my $user = $SCHEMA->resultset( 'User' )->find( route_parameters->get( 'user_id' ) );
  my @roles = $SCHEMA->resultset( 'Role' )->search( undef, { order_by => [ 'role' ] } );

  template 'admin_manage_users_edit_form',
    {
      data =>
      {
        user  => $user,
        roles => \@roles,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage User Accounts', link => '/admin/manage_users' },
        { name => 'Edit User Account', current => 1 },
      ],
    };
};


=head2 POST C</admin/manage_users/:user_id/update>

Route to update a user account with new information. Admin access is required.

=cut

post '/admin/manage_users/:user_id/update' => require_role Admin => sub
{
  my $user_id = route_parameters->get( 'user_id' );

  my $form_input = body_parameters->as_hashref;

  my $form_results = $DATA_FORM_VALIDATOR->check( $form_input, 'admin_edit_user_form' );

  if ( $form_results->has_invalid or $form_results->has_missing )
  {
    my @errors = ();
    for my $invalid ( $form_results->invalid )
    {
      push( @errors, sprintf( "<strong>%s</strong> is invalid: %s<br>", $invalid, $form_results->invalid( $invalid ) ) );
    }

    for my $missing ( $form_results->missing )
    {
      push( @errors, sprintf( "<strong>%s</strong> needs to be filled out.<br>", $missing ) );
    }

    flash( error => sprintf( "Errors have occurred in your user account information.<br>%s", join( '<br>', @errors ) ) );
    redirect '/';
  }

  my $user = $SCHEMA->resultset( 'User' )->find( $user_id );

  if
  (
    not defined $user
    or
    ref( $user ) ne 'QP::Schema::Result::User'
  )
  {
    warn sprintf( 'Invalid or undefined user_id when updating user account: >%s<', $user_id );
    flash error => 'An error occurred: Invalid or undefined user credentials. Nothing was updated.';
    redirect '/admin/manage_users';
  }

  my $orig_user = Clone::clone( $user );

  my %old =
  (
    username   => $orig_user->username,
    first_name => $orig_user->first_name,
    last_name  => $orig_user->last_name,
    email      => $orig_user->email,
    birthdate  => $orig_user->birthdate,
  );

  my %new =
  (
    username   => body_parameters->get( 'username' ),
    first_name => body_parameters->get( 'first_name' ),
    last_name  => body_parameters->get( 'last_name' ),
    email      => body_parameters->get( 'email' ),
    birthdate  => body_parameters->get( 'birthdate' ),
  );

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  foreach my $key ( [ qw/ username first_name last_name email birthdate / ] )
  {
    if ( $old{$key} ne $new{$key} )
    {
      $user->$key( $new{$key} );
    }
  }
  $user->updated_on( $now );

  $SCHEMA->txn_do(
                  sub
                  {
                    $user->update;
                  }
  );

  # Any changes in userroles?
  my $ur_updated = '';
  my @new_userroles = body_parameters->get_all( 'userroles' );
  my @old_userroles = ();
  foreach my $orig_urole ( $orig_user->userroles )
  {
    push @old_userroles, $orig_urole->role_id;
  }

  if ( Array::Utils::array_diff( @new_userroles, @old_userroles ) )
  {
    # We have differences in the userroles, so let's wipe out the roles and re-set them.
    $user->delete_related( 'userroles' );
    foreach my $role_id ( @new_userroles )
    {
      $user->add_to_userroles( { role_id => $role_id } );
    }
    $ur_updated = ' User roles updated.';
  }

  # Do we have a password change?
  my $pw_updated = '';
  if ( defined body_parameters->get( 'password' ) and body_parameters->get( 'password' ) ne '' )
  {
    user_password( username => $user->username, realm => $DPAE_REALM, new_password => body_parameters->get( 'password' ) );
    $pw_updated = ' Password updated.';
  };

  my $userdiffs = QP::Log->find_changes_in_data( old_data => \%old, new_data => \%new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'User %s updated: %s%s%s', $user->username, join( ', ', @{ $userdiffs } ), $ur_updated, $pw_updated ),
  );

  flash success => sprintf( 'Updated user &quot;<strong>%s</strong>&quot;', $user->username );
  redirect '/admin/manage_users';
};


=head2 ANY C</admin/manage_users/:user_id/delete>

Route to delete a user account. Admin Access required.

=cut

any '/admin/manage_users/:user_id/delete' => require_role Admin => sub
{
  my $user_id = route_parameters->get( 'user_id' );

  my $user = $SCHEMA->resultset( 'User' )->find( $user_id );
  my $username = $user->username;

  $user->delete_related( 'userroles' );
  $user->delete;

  flash success => sprintf( 'Successfully deleted User &quot;<strong>%s</strong>&quot;', $username );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Deleted User >%s< (ID:%s)', $username, $user_id ),
  );

  redirect '/admin/manage_users';
};


=head2 GET C</admin/manage_roles>

Route to manage user roles dashboard. Requires Admin access.

=cut

get '/admin/manage_roles' => require_role Admin => sub
{
  my @roles = $SCHEMA->resultset( 'Role' )->search( {}, { order_by => [ 'role' ] } );

  template 'admin_manage_user_roles',
    {
      data =>
      {
        roles => \@roles,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage User Roles', current => 1 },
      ],
    };
};


=head2 GET C</admin/manage_roles/:role_id/edit>

Route for displaying the edit role form. Admin access required.

=cut

get '/admin/manage_roles/:role_id/edit' => require_role Admin => sub
{
  my $role_id = route_parameters->get( 'role_id' );

  my $role = $SCHEMA->resultset( 'Role' )->find( $role_id );

  if
  (
    not defined $role
    or
    ref( $role ) ne 'QP::Schema::Result::Role'
  )
  {
    warn sprintf( 'Invalid or undefined role ID: >%s<', $role_id );
    flash error => 'Error: Invalid or undefined Role ID.';
    redirect '/admin/manage_roles';
  }

  template 'admin_manage_roles_edit_form',
    {
      data =>
      {
        role => $role,
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage User Roles', link => '/admin/manage_roles' },
        { name => 'Edit User Role', current => 1 },
      ],
    };
};


=head2 POST C</admin/manage_roles/:role_id/update>

Route to save updated role data to the database. Admin access required.

=cut

post '/admin/manage_roles/:role_id/update' => require_role Admin => sub
{
  my $role_id = route_parameters->get( 'role_id' );

  if ( not defined body_parameters->get( 'role' ) )
  {
    flash error => 'Error: You must provide a Role name.';
    redirect sprintf( '/admin/manage_roles/%s/edit', $role_id );
  }

  my $role = $SCHEMA->resultset( 'Role' )->find( $role_id );

  if
  (
    not defined $role
    or
    ref( $role ) ne 'QP::Schema::Result::Role'
  )
  {
    warn sprintf( 'Invalid or undefined role ID: >%s<', $role_id );
    flash error => 'Error: Invalid or undefined Role ID.';
    redirect '/admin/manage_roles';
  }

  my $orig_role = Clone::clone( $role );
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  if ( $role->role ne body_parameters->get( 'role' ) )
  {
    $role->role( body_parameters->get( 'role' ) );
    $role->updated_on( $now );

    $role->update;

    flash success => sprintf( 'Role &quot;<strong>%s</strong>&quot; has been updated.', $role->role );
    info sprintf( 'Updated user role >%s< -> >%s<, on %s', $orig_role->role, $role->role, $now );
    my $logged = QP::Log->admin_log
    (
      admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
      ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
      log_level   => 'Info',
      log_message => sprintf( 'Updated User Role: %s -&gt; %s ', $orig_role->role, $role->role ),
    );
    redirect '/admin/manage_roles';
  }
  else
  {
    flash error => 'Error: You changed nothing. So nothing was updated.';
    redirect sprintf( '/admin/manage_roles/%s/edit', $role_id );
  }
};


=head2 GET C</admin/manage_roles/add>

Route to add user role form. Admin access required.

=cut

get '/admin/manage_roles/add' => require_role Admin => sub
{
  template 'admin_manage_roles_add_form',
    {
      data =>
      {
      },
      breadcrumbs =>
      [
        { name => 'Admin', link => '/admin' },
        { name => 'Manage User Roles', link => '/admin/manage_roles' },
        { name => 'Add New User Role', current => 1 },
      ],
    };
};


=head2 POST C</admin/manage_roles/create>

Route to save new role to the DB. Admin access required.

=cut

post '/admin/manage_roles/create' => require_role Admin => sub
{
  if
  (
    not defined body_parameters->get( 'role' )
    or
    body_parameters->get( 'role' ) eq ''
  )
  {
    flash error => 'Error: You must provide a Role Name.';
    redirect '/admin/manage_roles/add';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  my $new_role = $SCHEMA->resultset( 'Role' )->create
  (
    {
      role       => body_parameters->get( 'role' ),
      created_on => $now,
    }
  );

  info sprintf( 'Created new user role >%s<, ID: >%s<, on %s', body_parameters->get( 'role' ), $new_role->id, $now );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created New User Role: %s (ID:%s)', $new_role->role, $new_role->id ),
  );

  flash success => sprintf( 'Successfully created new User Role &quot;<strong>%s</strong>&quot;.', $new_role->role );
  redirect '/admin/manage_roles';
};


=head2 GET C</admin/manage_roles/:role_id/delete>

Route to delete a user role. Admin access required.

=cut

get '/admin/manage_roles/:role_id/delete' => require_role Admin => sub
{
  my $role_id = route_parameters->get( 'role_id' );

  my $role = $SCHEMA->resultset( 'Role' )->find( $role_id );

  if
  (
    not defined $role
    or
    ref( $role ) ne 'QP::Schema::Result::Role'
  )
  {
    warn sprintf( 'Invalid or undefined role ID: >%s<', $role_id );
    flash error => 'Error: Invalid or undefined Role ID.';
    redirect '/admin/manage_roles';
  }

  my $rolename = $role->role;
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  $role->delete_related( 'userroles' );
  $role->delete;

  info sprintf( 'Deleted user role >%s<, on %s', $rolename, $now );
  flash success => sprintf( 'Successfully deleted User Role &quot;<strong>%s</strong>&quot;', $rolename );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Deleted User Role >%s< (ID:%s)', $rolename, $role_id ),
  );

  redirect '/admin/manage_roles';
};


=head2 permission_denied_page_handler

Routine to display the 'permission_denied' screen when a User doesn't have the proper role.

=cut

sub permission_denied_page_handler
{
  template 'views/permission_denied.tt';
}

true;
