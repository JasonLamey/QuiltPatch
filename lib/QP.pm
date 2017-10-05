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
use Array::Utils;
use GD::Thumbnail;

use QP::Log;
use QP::Mail;
use QP::Schema;
use QP::Util;

our $VERSION = '2.0';

const my $DOMAIN_ROOT               => 'http://www.quiltpatchva.com';
const my $SCHEMA                    => QP::Schema->db_connect();
const my $DT_PARSER                 => $SCHEMA->storage->datetime_parser;
const my $USER_SESSION_EXPIRE_TIME  => 172800; # 48 hours in seconds.
const my $ADMIN_SESSION_EXPIRE_TIME => 600;    # 10 minutes in seconds.
const my $DPAE_REALM                => 'site'; # Dancer2::Plugin::Auth::Extensible realm
const my $DATA_FORM_VALIDATOR       => ''; # TEMPORARY TO KILL ERROR WHILE IMPORTING ADMIN CODE
const my $BASE_UPLOAD_FILE_DIR      => path( config->{ appdir }, 'public/downloads' );
const my $BASE_CLASS_FILE_DIR       => path( config->{ appdir }, 'public/class_files' );
const my $MAX_IMAGE_FILE_SIZE       => 1048576;     # 10MB in bytes.
const my $MAX_PDF_FILE_SIZE         => 1048576;     # 10MB in bytes.

$SCHEMA->storage->debug(0); # Turns on DB debuging. Turn off for production.

hook before_template_render => sub
{
  my $tokens = shift;
  $tokens->{domain_root}           = $DOMAIN_ROOT;
  $tokens->{datetime_format_short} = config->{datetime_format_short};
  $tokens->{datetime_format_long}  = config->{datetime_format_long};
  $tokens->{date_format_short}     = config->{date_format_short};
  $tokens->{date_format_long}      = config->{date_format_long};
  $tokens->{liuid}                 = ( defined logged_in_user ) ? logged_in_user->id : 0;
  $tokens->{newsletter_session}    = $SCHEMA->resultset( 'NewsletterSession' )->search( {},
                                          { order_by => { -desc => 'created_on' }, rows => 1 } )->single();
  $tokens->{newsletter_file}       = $SCHEMA->resultset( 'SiteFile' )->search( {},
                                          { order_by => { -desc => 'created_on' }, rows => 1 } )->single();
};


=head1 GENERAL ROUTES


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

  my @bookclub_dates = $SCHEMA->resultset( 'BookClubDate' )->search( { date => { '>=' => $DT_PARSER->format_datetime($today) } },
    {
      order_by => { -asc => 'date' },
    }
  )->all();

  template 'index',
            {
              data =>
              {
                news       => \@news,
                events     => \@events,
                closings   => \@closings,
                newsletter => $newsletter_rs->first,
                bookclub   => \@bookclub_dates,
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
                                                          'dates', 'classteachers',
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


=head1 ROUTES INVOLVING LOGIN/SIGN UP


=head2 GET C</reset_password>

Route to reset a user's password.

=cut

get '/reset_password' => sub
{
  template 'reset_password_form', { title => 'Reset Password' };
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

  authenticate_user
  (
    $username, $new_temp_pw,
  );

  flash( success => sprintf( 'Welcome back, %s!', $username ) ) );
  redirect sprintf( '/user/change_password/%s', $new_temp_pw );
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
      title => 'Thanks for Signing Up!',
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
      title => 'Login to Your Account',
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
      title => 'Account Confirmation',
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

=head1 ROUTES REQUIRING THE USER BE LOGGED IN


=head2 AJAX C</bookmark_class/:class_id/:action>

AJAX call route to toggle the bookmarking of a class.

=cut

ajax '/bookmark_class/:class_id/:action' => require_login sub
{

  my $class_id = route_parameters->get( 'class_id' );
  my $action   = route_parameters->get( 'action' );

  my @json = ();

  if ( not session( 'logged_in_user' ) )
  {
    warning 'Failed attempt at bookmarking a class by a non-logged-in user.';
    push( @json,
      {
        message => 'Could not update the bookmark. You must be logged in.',
        success => 0,
      }
    );
    return to_json( \@json );
  }

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );

  if
  (
    not defined $class
    or
    ref( $class ) ne 'QP::Schema::Result::ClassInfo'
  )
  {
    warning 'Failed attempt at bookmarking a class with an invalid or undefined class ID.';
    push( @json,
      {
        message => 'Could not update the bookmark. Invalid Class.',
        success => 0,
      }
    );
    return to_json( \@json );
  }

  my $user = $SCHEMA->resultset( 'User' )->find( logged_in_user->id );

  if
  (
    ! defined $user
    or
    ref( $user ) ne 'QP::Schema::Result::User'
  )
  {
    warning 'Failed attempt at bookmarking a class with an invalid or undefined user ID.';
    push( @json,
      {
        message => 'Could not update the bookmark. Invalid User.',
        success => 0,
      }
    );
    return to_json( \@json );
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  if ( $action == -1 )
  {
    $user->remove_from_bookmarks( $class );
  }
  else
  {
    $user->add_to_bookmarks( $class, { created_at => $now } );
  }

  my $action_msg = ( $action == -1 ) ? 'Successfully removed your bookmark for "%s".'
                                     : 'Successfully bookmarked "%s".';

  push ( @json,
    {
      message => sprintf( $action_msg, $class->title ),
      success => 1,
    }
  );

  my $logged = QP::Log->user_log
  (
    user        => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( $action_msg, $class->title ),
  );

  to_json( \@json );
};


=head2 GET C</user>

GET route for the default user home page.

=cut

get '/user' => require_login sub
{
  my $user = $SCHEMA->resultset( 'User' )->find( logged_in_user->id );
  if ( ! defined $user or ! defined $user->id )
  {
    warning 'Invalid username supplied to find User account in user dashboard.';
  }

  my @bookmarks = $user->bookmarks();
  my %by_date   = ();
  foreach my $bm ( @bookmarks )
  {
    if ( defined $bm->next_upcoming_date )
    {
      $by_date{ $bm->next_upcoming_date->date . '.' . $bm->next_upcoming_date->start_time1 . '.' . $bm->id } = $bm;
    }
    else
    {
      $by_date{ '3000-01-01' . '.' . '00:00:00' . '.' . $bm->id } = $bm;
    }
  }
  my @by_date = ();
  foreach my $key ( sort keys %by_date )
  {
    push( @by_date, $by_date{$key} );
  }

  template 'user_dashboard',
  {
    data =>
    {
      user              => $user,
      bookmarks         => \@bookmarks,
      bookmarks_by_date => \@by_date,
    },
    title => 'Your Account',
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
    },
    title => 'Edit Your User Info',
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


=head2 GET C</user/change_password/?:new_password?>

Route to change a user's password. Requires the user to be logged in.

=cut

get '/user/change_password/?:old_password?' => require_login sub
{
  my $old_password = route_parameters->get( 'old_password' ) // undef;

  template 'user_change_password',
  {
    data =>
    {
      old_password => $old_password,
    },
    title => 'Change Password',
  };
};


=head2 POST C</user/change_password>

Route to update password data for a user's account. Requires the user to be logged in.

=cut

post '/user/change_password' => require_login sub
{
  my $old_password     = body_parameters->get( 'old_password' );
  my $new_password     = body_parameters->get( 'new_password' );
  my $confirm_password = body_parameters->get( 'confirm_password' );

  unless( user_password( username => logged_in_user->username, password => $old_password ) )
  {
    flash( error => 'Could not update your password. Your Old Password was incorrect.' );
    redirect '/user/change_password';
  }

  unless( $old_password ne $new_password )
  {
    flash( error => 'Could not update your password. Your New Password must be different from the Old Password.' );
    redirect '/user/change_password';
  }

  unless( $new_password eq $confirm_password )
  {
    flash( error => 'Could not update your password. Your New Password and Confirm Password did not match.' );
    redirect '/user/change_password';
  }

  user_password( username => logged_in_user->username, new_password => $new_password );

  info sprintf( 'User >%s< successfully changed password.', logged_in_user->username );
  my $logged = QP::Log->user_log
  (
    user        => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => 'Successful password change.',
  );

  flash( success => 'Your password has been successfully updated!' );
  redirect '/user';
};


=head2 GET C</user/bookmarks>

GET route for managing User bookmarks data.

=cut

get '/user/bookmarks' => require_login sub
{
  my $user = $SCHEMA->resultset( 'User' )->find( logged_in_user->id );

  my @bookmarks = $user->bookmarks;

  template 'user_bookmarks',
  {
    title => 'Manage Your Bookmarks',
    data  =>
    {
      bookmarks => \@bookmarks,
    },
  };
};


=head2 GET C</user/bookmarks/:bookmark_id/delete>

GET route for deleting User bookmarks data.

=cut

get '/user/bookmarks/:bookmark_id/delete' => require_login sub
{
  my $bookmark_id = route_parameters->get( 'bookmark_id' );
  my $user = $SCHEMA->resultset( 'User' )->find( logged_in_user->id );
  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $bookmark_id );

  if
  (
    not defined $class
    or
    ref( $class ) ne 'QP::Schema::Result::ClassInfo'
  )
  {
    flash( error => sprintf( 'An error occurred and we could not remove your bookmark. Please try again later.' ) );
    redirect '/user/bookmarks';
  }

  $user->remove_from_bookmarks( $class );

  flash( success => sprintf( 'Successfully removed %s from your bookmarks.', $class->title ) );
  redirect '/user/bookmarks';
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

Route for presenting the edit class groups form. Requires the user be logged in and an Admin.

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

  my $order = 1;
  foreach my $teacher ( 'teacher_id', 'secondary_teacher_id', 'tertiary_teacher_id' )
  {
    debug sprintf( 'Looking for %s', $teacher );
    if
    (
      defined body_parameters->get( $teacher )
      and
      int( body_parameters->get( $teacher ) ) > 0
    )
    {
      my $teacher_to_add = $SCHEMA->resultset( 'Teacher' )->find( body_parameters->get( $teacher ) );
      debug sprintf( 'TEACHER TO ADD: %d %s', body_parameters->get( $teacher ), $teacher_to_add->name );
      if ( defined $teacher_to_add and ref( $teacher_to_add ) eq 'QP::Schema::Result::Teacher' )
      {
        $new_class->add_to_teachers( $teacher_to_add, { sort_order => $order } );
      }
    }
    $order++;
  }

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

  # See if any teachers have changed.
  my @classteachers = $class->classteachers;
  my @clteachers = map { $_->teacher_id } @classteachers;
  my @old_teachers = (
                        body_parameters->get( 'teacher_id' ),
                        body_parameters->get( 'secondary_teacher_id' ),
                        body_parameters->get( 'tertiary_teacher_id' )
  );

  my @changed_teachers = Array::Utils::array_diff( @clteachers, @old_teachers );
  debug sprintf( 'Changed Teachers: %s', Data::Dumper::Dumper( @changed_teachers ) );

  if ( scalar( @changed_teachers ) > 0 )
  {
    $class->delete_related( 'classteachers' );
    my $t_count = 1;
    foreach my $teacher_id ( 'teacher_id', 'secondary_teacher_id', 'tertiary_teacher_id' )
    {
      debug sprintf( 'Looking for: %s', $teacher_id );
      if
      (
        defined body_parameters->get( $teacher_id )
        and
        int( body_parameters->get( $teacher_id ) ) > 0
      )
      {
        my $teacher_to_add = $SCHEMA->resultset( 'Teacher' )->find( body_parameters->get( $teacher_id ) );
        debug sprintf( 'TEACHER TO ADD: %d %s', body_parameters->get( $teacher_id ), $teacher_to_add->name );
        my %link_vals = ( sort_order => $t_count );
        $class->add_to_teachers( $teacher_to_add, \%link_vals );
      }
      $t_count++;
    }
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $class->class_group_id( body_parameters->get( 'class_group_id' ) ),
  $class->class_subgroup_id( body_parameters->get( 'class_subgroup_id' ) ? body_parameters->get( 'class_subgroup_id' ) : undef ),
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

  $class->delete_related( 'classteachers' );
  $class->delete_related( 'dates' );

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


=head2 GET C</admin/manage_classes/classes/:class_id/dates>

Route to Class Date management dashboard. Requires being logged in and of admin role.

=cut

get '/admin/manage_classes/classes/:class_id/dates' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );

  my @dates = $class->dates;

  template 'admin_manage_classes_class_dates',
  {
    data =>
    {
      class => $class,
      dates => \@dates,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Classes', link => '/admin/manage_classes/classes' },
      { name => 'Manage Class Dates', current => 1 },
    ],
    title => 'Manage Class Dates',
  },
  {
    layout => 'ajax-modal',
  };
};


=head2 GET C</admin/manage_classes/classes/:class_id/dates/add>

Route to add new class dates form. Requires being logged in and of Admin role.

=cut

get '/admin/manage_classes/classes/:class_id/dates/add' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );

  template 'admin_manage_classes_class_dates_add_form',
  {
    data =>
    {
      class => $class,
    },
    title => 'Add New Class Dates',
  },
  {
    layout => 'ajax-modal',
  };
};


=head2 POST C</admin/manage_classes/classes/:class_id/dates/create>

Route to save new class dates data to the database.  Requires being logged in and of Admin role.

=cut

post '/admin/manage_classes/classes/:class_id/dates/create' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $class_id = route_parameters->get( 'class_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );

  if ( ! defined $class or ref( $class ) ne 'QP::Schema::Result::ClassInfo' )
  {
    flash error => sprintf( 'Cannot find class to add dates to.' );
    redirect '/admin/manage_classes/classes';
  }

  my $new_date_count = 0;
  foreach my $datenum ( 1 .. 12 )
  {
    if
    (
      defined body_parameters->get( 'date' . $datenum )
      &&
      body_parameters->get( 'date' . $datenum ) ne ''
    )
    {
      $class->create_related('dates',
        {
          date             => body_parameters->get( 'date' . $datenum ),
          start_time1      => body_parameters->get( 'start_time1' ),
          end_time1        => body_parameters->get( 'end_time1' ),
          start_time2      => ( body_parameters->get( 'start_time2' )           ? body_parameters->get( 'start_time2' )           : undef ),
          end_time2        => ( body_parameters->get( 'end_time2' )             ? body_parameters->get( 'end_time2' )             : undef ),
          date_group       => ( body_parameters->get( 'date_group' )            ? body_parameters->get( 'date_group' )            : undef ),
          date_group_order => ( body_parameters->get( 'date_group_order' )      ? body_parameters->get( 'date_group_order' )      : undef ),
          is_holiday       => ( body_parameters->get( 'is_holiday' . $datenum ) ? body_parameters->get( 'is_holiday' . $datenum ) : 0 ),
          session          => 'depricated field',
        }
      );
      $new_date_count++;
    }
  }

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created %d new class dates for >%s<, ID: >%s<, on %s', $new_date_count, $class->title, $class->id, $now );

  flash success => sprintf( 'Successfully created <strong>%d</strong> new dates for &quot;<strong>%s</strong>&quot;!', $new_date_count, $class->title );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new %d class dates for %s<br>%s', $new_date_count, $class->title, join( '<br>', @fields ) ),
  );

  redirect '/admin/manage_classes/classes';
};


=head2 AJAX C</admin/manage_classes/classes/:class_id/dates/:date_id/edit>

Route for presenting the edit class subgroup form. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/classes/:class_id/dates/:date_id/edit' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );
  my $date_id  = route_parameters->get( 'date_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );

  my @dates = $class->search_related( 'dates', { id => $date_id } );

  template 'admin_manage_classes_class_dates_edit_form',
  {
    data =>
    {
      class     => $class,
      cldate    => $dates[0],
    },
    title => 'Edit Class Date',
  },
  {
    layout => 'ajax-modal',
  };
};


=head2 POST C</admin/manage_classes/classes/:class_id/dates/:date_id/update>

Route to send form data to for updating a class date in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_classes/classes/:class_id/dates/:date_id/update' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );
  my $date_id  = route_parameters->get( 'date_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );
  my @dates = $class->search_related( 'dates', { id => $date_id } );
  my $date  = $dates[0];

  if
  (
    not defined $date
    or
    ref( $date ) ne 'QP::Schema::Result::ClassDate'
  )
  {
    flash( error => 'Error: Cannot update class date - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/classes';
  }

  my $orig_date = Clone::clone( $date );

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  $date->start_time1( body_parameters->get('start_time1') );
  $date->end_time1( body_parameters->get('end_time1') );
  $date->date( body_parameters->get('date') );
  $date->start_time2( ( body_parameters->get('start_time2') ? body_parameters->get('start_time2') : undef ) );
  $date->end_time2( ( body_parameters->get('end_time2') ? body_parameters->get('end_time2') : undef ) );
  $date->is_holiday( ( body_parameters->get('is_holiday') ? body_parameters->get('is_holiday') : 0 ) );
  $date->date_group( ( body_parameters->get('date_group') ? body_parameters->get('date_group') : undef ) );
  $date->date_group_order( ( body_parameters->get('date_group_order') ? body_parameters->get('date_group_order') : undef ) );

  $date->update();

  info sprintf( 'Class date for >%s< updated by %s on %s.', $class->title, logged_in_user->username, $now );

  my $old =
  {
    start_time1      => $orig_date->start_time1,
    end_time1        => $orig_date->end_time1,
    date             => $orig_date->date,
    start_time2      => $orig_date->start_time2,
    end_time2        => $orig_date->end_time2,
    is_holiday       => $orig_date->is_holiday,
    date_group       => $orig_date->date_group,
    date_group_order => $orig_date->date_group_order,
  };
  my $new =
  {
    start_time1      => body_parameters->get('start_time1'),
    end_time1        => body_parameters->get('end_time1'),
    date             => body_parameters->get('date'),
    start_time2      => ( body_parameters->get('start_time2') ? body_parameters->get('start_time2') : undef ),
    end_time2        => ( body_parameters->get('end_time2') ? body_parameters->get('end_time2') : undef ),
    is_holiday       => ( body_parameters->get('is_holiday') ? body_parameters->get('is_holiday') : 0 ),
    date_group       => ( body_parameters->get('date_group') ? body_parameters->get('date_group') : undef ),
    date_group_order => ( body_parameters->get('date_group_order') ? body_parameters->get('date_group_order') : undef ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class date modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated class date for &quot;<strong>%s</strong>&quot;.',
                                $class->title ) );
  redirect '/admin/manage_classes/classes';
};


=head2 GET C</admin/manage_classes/classes/:class_id/dates/:date_id/delete>

Route to delete a class date. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_classes/classes/:class_id/dates/:date_id/delete' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );
  my $date_id  = route_parameters->get( 'date_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );
  my $class_title = $class->title;

  if
  (
    not defined $class
    or
    ref( $class ) ne 'QP::Schema::Result::ClassInfo'
  )
  {
    flash( error => 'Error: Cannot delete class date - Invalid or unknown ID.' );
    redirect '/admin/manage_classes/classes';
  }

  $class->delete_related( 'dates', { id => $date_id } );

  flash success => sprintf( 'Successfully deleted Class Date for <strong>%s</strong>.', $class_title );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Class Date for &quot;%s&quot; deleted', $class_title ),
  );

  redirect '/admin/manage_classes/classes';
};


=head2 GET C</admin/manage_classes/classes/:class_id/files>

Route to manage class-related files. Requires user to be an admin.

=cut

get '/admin/manage_classes/classes/:class_id/files' => require_role Admin => sub
{
  my $class_id = route_parameters->get( 'class_id' );

  my $class = $SCHEMA->resultset( 'ClassInfo' )->find( $class_id );

  template 'admin_manage_classes_class_files',
  {
    title => 'Manage Class Files',
    data  =>
    {
      class => $class,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Classes', link => '/admin/manage_classes/classes' },
      { name => 'Manage Class Files', current => 1 },
    ],
  };
};


=head2 AJAX C</admin/manage_classes/class/:class_id/:file_type/get_files>

AJAX route to fetch existing class files. Admin required.

=cut

ajax '/admin/manage_classes/class/:class_id/:file_type/get_files' => require_role Admin => sub
{
  my $class_id  = route_parameters->get( 'class_id' );
  my $file_type = route_parameters->get( 'file_type' );

  return if ( ! defined $class_id or ! defined $file_type );

  my $file_path = path( $BASE_CLASS_FILE_DIR . sprintf( '/%d/%s', $class_id, $file_type ) );

  opendir( DIR, $file_path );
  my @class_files = readdir( DIR );
  closedir DIR;

  my @return_files = ();
  foreach my $file ( @class_files )
  {
    next if $file =~ /^\./;
    next if -d $file_path . '/' . $file;
    my %details = (
      name => $file,
      path => sprintf( '/class_files/%d/%s/%s', $class_id, $file_type, $file ),
      size => ( stat( "$file_path/$file" ) )[7]
    );
    push( @return_files, \%details );
  }

  return to_json( \@return_files );
};


=head2 POST C</admin/manage_classes/class/:class_id/:file_type/fileupload>

Route to upload class files. Requires Admin.

=cut

post '/admin/manage_classes/class/:class_id/:file_type/fileupload' => require_role Admin => sub
{
  my $class_id  = route_parameters->get( 'class_id' );
  my $file_type = route_parameters->get( 'file_type' );

  my %enum_values = (
    photos      => 'image',
    supply_list => 'supply list',
  );

  return if ( ! defined $class_id or ! defined $file_type );

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $class_dir = path( $BASE_CLASS_FILE_DIR . sprintf( '/%d', $class_id ) );
  if ( ! -e $class_dir )
  {
    mkdir $class_dir;
    info sprintf( 'Created new class directory: %s', $class_dir );
  }

  my $upload_path = path( $class_dir . sprintf( '/%s', $file_type ) );
  if ( ! -e $upload_path )
  {
    mkdir $upload_path;
    info sprintf( 'Created new class directory: %s', $upload_path );
  }

  if ( uc( $file_type ) eq 'PHOTOS' )
  {
    my $thumbs_dir = $upload_path . '/thumbs';
    if ( ! -e $thumbs_dir )
    {
      mkdir $thumbs_dir;
      info sprintf( 'Created new class directory: %s', $thumbs_dir );
    }
  }

  my $upload = upload('file');    # upload object

  $upload->copy_to( sprintf( '%s/%s', $upload_path, $upload->filename ) );

  my $new_file = $SCHEMA->resultset( 'ClassFile' )->create(
    {
      class_id   => $class_id,
      filename   => $upload->filename,
      filetype   => $enum_values{ $file_type },
      created_on => $now,
    }
  );

  if ( uc( $file_type ) eq 'PHOTOS' )
  {
    # Create Thumbnails - Small: max 100px w, Med: max 300px w, Large: max 650px w
    my @thumbs_config = (
      { max => 100, prefix => 's', rules => { square => 'crop' } },
      { max => 300, prefix => 'm', rules => { square => 'crop' } },
      { max => 650, prefix => 'l', rules => { square => 'crop', dimension_constraint => 1 } },
    );

    foreach my $thumb ( @thumbs_config )
    {
      my $thumbnail = GD::Thumbnail->new( %{$thumb->{rules}} );
      my $raw       = $thumbnail->create( sprintf( '%s/%s', $upload_path, $upload->filename ), $thumb->{max}, undef );
      my $mime      = $thumbnail->mime;
      open    IMG, sprintf( '>%s/thumbs/%s-%s', $upload_path, $thumb->{prefix}, $upload->filename );
      binmode IMG;
      print   IMG $raw;
      close   IMG;
    }
  }

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( '%s file &quot;%s&quot; uploaded for class ID %d.',
                    ucfirst( $file_type), $upload->filename, $class_id ),
  );

  my @return = ( $upload->filename );

  return to_json( \@return );
};


=head2 POST C</admin/manage_classes/class/:class_id/:file_type/delete>

Route to delete a class file and DB record. Admin required.

=cut

post '/admin/manage_classes/class/:class_id/:file_type/delete' => require_role Admin => sub
{
  my $class_id       = route_parameters->get( 'class_id' );
  my $file_type      = route_parameters->get( 'file_type' );
  my $file_to_delete = body_parameters->get( 'name' );
  my $op             = body_parameters->get( 'op' );

  if
  (
    defined $op
    and
    uc( $op ) eq 'DELETE'
    and
    defined $file_to_delete
  )
  {
    $file_to_delete =~ s/\.\./\./g;
    my $file_path = path( $BASE_CLASS_FILE_DIR . sprintf( '/%d/%s/%s', $class_id, $file_type, $file_to_delete ) );
    info sprintf( 'Attempting to delete class file from: %s', $file_path );
    if ( -e $file_path )
    {
      unlink( $file_path );
      if ( uc( $file_type ) eq 'PHOTOS' )
      {
        foreach my $prefix ( 's-', 'm-', 'l-' )
        {
          my $file_path = path( $BASE_CLASS_FILE_DIR . sprintf( '/%d/%s/thumbs/%s%s', $class_id, $file_type, $prefix, $file_to_delete ) );
          unlink( $file_path );
        }
      }
      $SCHEMA->resultset( 'ClassFile' )->find( { class_id => $class_id, filename => $file_to_delete } )->delete;

      my $logged = QP::Log->admin_log
      (
        admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
        ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
        log_level   => 'Info',
        log_message => sprintf( '%s file &quot;%s&quot; deleted for class ID %d.',
                        ucfirst( $file_type), $file_to_delete, $class_id ),
      );

      info sprintf( 'Deleted class file: %s - from class ID: %d', $file_to_delete, $class_id );
      return sprintf( 'Deleted file %s', $file_to_delete );
    }
  }

  return 'File not deleted. Invalid or non-existent file.';
};


=head2 GET C</admin/manage_session>

Route for handling newsletter session info. Requires the user to be an Admin.

=cut

get '/admin/manage_session' => require_role Admin => sub
{
  my $session = $SCHEMA->resultset( 'NewsletterSession' )->search( {},
    {
      order_by => { -desc => 'created_on' },
      rows     => 1,
    }
  )->single();

  template 'admin_manage_site_files',
  {
    data =>
    {
      current_session => $session,
    },
    title => 'Manage Newsletter Session',
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Newsletter Session', current => 1 },
    ],
  };
};


=head2 POST C</admin/manage_session>

Route to insert new session information. Reqires user be an Admin.

=cut

post '/admin/manage_session' => require_role Admin => sub
{
  my $session_name = body_parameters->get( 'session_name' );

  if ( ! defined $session_name or $session_name eq '' )
  {
    flash( error => 'Invalid or unsupplied session name. Could not save new session information.' );
    redirect '/admin/manage_session';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $new_session = $SCHEMA->resultset( 'NewsletterSession' )->create(
    {
      session_name => $session_name,
      created_on   => $now,
    }
  );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Successfully created newsletter session %s', $session_name ),
  );

  flash( success => sprintf( 'Successfully created new newsletter session <strong>%s</strong>.', $session_name ) );
  redirect '/admin/manage_session';
};


=head2 GET C</admin/manage_newsletter>

Route for updating/editing the newsletter from Leslie.  Require the user is an Admin.

=cut

get '/admin/manage_newsletter' => require_role Admin => sub
{
  my $newsletter = $SCHEMA->resultset( 'Newsletter' )->search( undef,
    {
      order_by => { -desc => 'created_at' },
      rows     => 1,
    }
  )->single();

  template 'admin_manage_newsletter_edit_form',
  {
    data =>
    {
      newsletter => $newsletter,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => "Manage Leslie's Newsletter", current => 1 },
    ],
    title => "Manage Leslie's Newsletter",
  }
};


=head2 POST C</admin/manage_newsletter/:newsletter_id/update>

Route to send form data to for updating a newsletter in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_newsletter/:newsletter_id/update' => require_role Admin => sub
{
  my $newsletter_id = route_parameters->get( 'newsletter_id' );

  my $newsletter = $SCHEMA->resultset( 'Newsletter' )->find( $newsletter_id );

  if
  (
    not defined $newsletter
    or
    ref( $newsletter ) ne 'QP::Schema::Result::Newsletter'
  )
  {
    flash( error => 'Error: Cannot update newsletter - Invalid or unknown ID.' );
    redirect '/admin/manage_newsletter';
  }

  my $orig_newsletter = Clone::clone( $newsletter );

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  $newsletter->body( body_parameters->get('body') );
  $newsletter->title( ( body_parameters->get('title') ? body_parameters->get('title') : undef ) );
  $newsletter->postscript( ( body_parameters->get('postscript') ? body_parameters->get('postscript') : undef ) );
  $newsletter->updated_at( $now );

  $newsletter->update();

  info sprintf( 'Newsletter updated by %s on %s.', logged_in_user->username, $now );

  my $old =
  {
    body       => $orig_newsletter->body,
    title      => $orig_newsletter->title,
    postscript => $orig_newsletter->postscript,
  };
  my $new =
  {
    body       => body_parameters->get('body'),
    title      => ( body_parameters->get('title')      ? body_parameters->get('title')      : undef ),
    postscript => ( body_parameters->get('postscript') ? body_parameters->get('postscript') : undef ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Newsletter modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => 'Successfully updated Newsletter.' );
  redirect '/admin/manage_newsletter';
};


=head2 AJAX C</admin/newsletters/get_files>

AJAX route to fetch existing newsletter files. Admin required.

=cut

ajax '/admin/newsletter/get_files' => require_role Admin => sub
{
  my $newsletter_path = path( $BASE_UPLOAD_FILE_DIR . '/newsletters' );

  opendir( DIR, $newsletter_path );
  my @newsletter_files = readdir( DIR );
  closedir DIR;

  my @return_files = ();
  foreach my $file ( @newsletter_files )
  {
    next if $file =~ /^\./;
    my %details = (
      name => $file,
      path => sprintf( '/downloads/newsletters/%s', $file ),
      size => ( stat( "$newsletter_path/$file" ) )[7]
    );
    push( @return_files, \%details );
  }

  return to_json( \@return_files );
};


=head2 POST C</admin/newsletter/fileupload>

Route to upload newsletter PDFs. Requires Admin.

=cut

post '/admin/newsletter/fileupload' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $upload_path = path( $BASE_UPLOAD_FILE_DIR . '/newsletters' );
  if ( ! -e $upload_path )
  {
    mkdir $upload_path;
  }

  my $upload = upload('file');    # upload object

  $upload->copy_to( sprintf( '%s/%s', $upload_path, $upload->filename ) );

  my $new_file = $SCHEMA->resultset( 'SiteFile' )->create(
    {
      filename   => $upload->filename,
      filetype   => 'newsletter',
      created_on => $now,
    }
  );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Newsletter file &quot;%s&quot; uploaded.', $upload->filename ),
  );

  my @return = ( $upload->filename );

  return to_json( \@return );
};


=head2 POST C</admin/newsletter/delete>

Route to delete a newsletter file and DB record. Admin required.

=cut

post '/admin/newsletter/delete' => require_role Admin => sub
{
  my $file_to_delete = body_parameters->get( 'name' );
  my $op             = body_parameters->get( 'op' );

  if
  (
    defined $op
    and
    uc( $op ) eq 'DELETE'
    and
    defined $file_to_delete
  )
  {
    $file_to_delete =~ s/\.\./\./g;
    my $file_path = path( $BASE_UPLOAD_FILE_DIR . sprintf( '/newsletters/%s', $file_to_delete ) );
    if ( -e $file_path )
    {
      unlink( $file_path );

      my $logged = QP::Log->admin_log
      (
        admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
        ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
        log_level   => 'Info',
        log_message => sprintf( 'Newsletter file &quot;%s&quot; deleted.', $file_to_delete ),
      );

      $SCHEMA->resultset( 'SiteFile' )->search( { filename => $file_to_delete }, { rows => 1 } )->single()->delete;
      return sprintf( 'Deleted file %s', $file_to_delete );
    }
  }

  return 'File not deleted. Invalid or non-existent file.';
};


=head2 GET C</admin/manage_book_club>

Route for managing book club dates.  Require the user is an Admin.

=cut

get '/admin/manage_book_club' => require_role Admin => sub
{
  my @bookclub_dates = $SCHEMA->resultset( 'BookClubDate' )->search( undef,
    {
      order_by => { -desc => 'date' },
    }
  )->all();

  template 'admin_manage_book_club_dates',
  {
    data =>
    {
      dates => \@bookclub_dates,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => "Manage Book Club", current => 1 },
    ],
    title => "Manage Book Club",
  }
};


=head2 GET C</admin/manage_book_club/add>

Route to add new book club date form. Requires being logged in and of Admin role.

=cut

get '/admin/manage_book_club/add' => require_role Admin => sub
{
  template 'admin_manage_book_club_dates_add_form',
  {
    data =>
    {
    },
    title => 'Add New Book Club Date',
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => "Manage Book Club", link => '/admin/manage_book_club' },
      { name => "Add New Book Club Date", current => 1 },
    ],
  };
};


=head2 POST C</admin/manage_book_club/create>

Route to save new book club date data to the database.  Requires being logged in and of Admin role.

=cut

post '/admin/manage_book_club/create' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $new_date = $SCHEMA->resultset( 'BookClubDate' )->create(
    {
      book   => body_parameters->get( 'book' ),
      author => body_parameters->get( 'author' ),
      date   => body_parameters->get( 'date' ),
    }
  );

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new book club date, >%s< on >%s<, ID: >%s<, on %s',
      body_parameters->get( 'book' ), body_parameters->get( 'date' ), $new_date->id, $now );

  flash success => sprintf( 'Successfully created date for &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'book' ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new book club date<br>%s', join( '<br>', @fields ) ),
  );

  redirect '/admin/manage_book_club';
};


=head2 GET C</admin/manage_book_club/:date_id/edit>

Route for presenting the edit book club date form. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_book_club/:date_id/edit' => require_role Admin => sub
{
  my $date_id = route_parameters->get( 'date_id' );

  my $date = $SCHEMA->resultset( 'BookClubDate' )->find( $date_id );


  template 'admin_manage_book_club_dates_edit_form',
  {
    data =>
    {
      date => $date,
    },
    title => 'Edit Book Club Date',
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => "Manage Book Club", link => '/admin/manage_book_club' },
      { name => "Edit Book Club Date", current => 1 },
    ],
  };
};


=head2 POST C</admin/manage_book_club/:date_id/update>

Route to send form data to for updating a book club date in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_book_club/:date_id/update' => require_role Admin => sub
{
  my $date_id = route_parameters->get( 'date_id' );

  my $date      = $SCHEMA->resultset( 'BookClubDate' )->find( $date_id );
  my $orig_date = Clone::clone( $date );

  if
  (
    not defined $date
    or
    ref( $date ) ne 'QP::Schema::Result::BookClubDate'
  )
  {
    flash( error => 'Error: Cannot update book club date - Invalid or unknown ID.' );
    redirect '/admin/manage_book_club';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $date->book( body_parameters->get( 'book' ) );
  $date->author( body_parameters->get( 'author' ) );
  $date->date( body_parameters->get( 'date' ) );

  $date->update();

  info sprintf( 'Book Club date for >%s< updated by %s on %s.', $date->book, logged_in_user->username, $now );

  my $old =
  {
    book   => $orig_date->book,
    author => $orig_date->author,
    date   => $orig_date->date,
  };
  my $new =
  {
    book   => body_parameters->get( 'book' ),
    author => body_parameters->get( 'author' ),
    date   => body_parameters->get( 'date' ),
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Book Club Date modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated book club date for &quot;<strong>%s</strong>&quot;.',
                                body_parameters->get( 'book' ) ) );
  redirect '/admin/manage_book_club';
};


=head2 GET C</admin/manage_book_club/:date_id/delete>

Route to delete a book club date. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_book_club/:date_id/delete' => require_role Admin => sub
{
  my $date_id = route_parameters->get( 'date_id' );

  my $date      = $SCHEMA->resultset( 'BookClubDate' )->find( $date_id );
  my $date_book = $date->book;

  if
  (
    not defined $date
    or
    ref( $date ) ne 'QP::Schema::Result::BookClubDate'
  )
  {
    flash( error => 'Error: Cannot delete book club date - Invalid or unknown ID.' );
    redirect '/admin/manage_book_club';
  }

  $date->delete;

  flash success => sprintf( 'Successfully deleted date for <strong>%s</strong>.', $date_book );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Book club date for &quot;%s&quot; deleted', $date_book ),
  );
  redirect '/admin/manage_book_club';
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
      title => 'Manage User Accounts',
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
      title => 'Create User Account',
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
      title => 'Edit User Account',
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


=head2 GET C</admin/manage_links/groups>

Route to managing Link Groups. Admin required.

=cut

get '/admin/manage_links/groups' => require_role Admin => sub
{
  my @link_groups = $SCHEMA->resultset( 'LinkGroup' )->search( {},
    {
      prefetch => 'links',
      order_by => { -asc => 'order_by' },
    }
  )->all;

  template 'admin_manage_links_groups.tt',
  {
    data =>
    {
      link_groups => \@link_groups,
    },
    title => 'Manage Link Groups',
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Link Groups', current => 1 },
    ],
  };
};


=head2 GET C</admin/manage_links/groups/add>

Route to the Add Links Group form. Admin required.

=cut

get '/admin/manage_links/groups/add' => require_role Admin => sub
{
  template 'admin_manage_links_group_add_form',
  {
    data =>
    {
    },
    title => 'Create New Link Group',
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Link Groups', link => '/admin/manage_links/groups' },
      { name => 'Create New Link Group', current => 1 },
    ],
  };
};


=head2 POST C</admin/manage_links/groups/create>

Route to the save data from the Add Links Group form. Admin required.

=cut

post '/admin/manage_links/groups/create' => require_role Admin => sub
{
  my $group_name = body_parameters->get( 'name' )     // undef;
  my $order_by   = body_parameters->get( 'order_by' ) // 1;

  if ( ! defined $group_name )
  {
    flash( error => 'A group name must be provided. New group not saved.' );
    redirect '/admin/manage_links/groups';
  }

  my $new_group = $SCHEMA->resultset( 'LinkGroup' )->create(
    {
      name     => $group_name,
      order_by => $order_by,
    }
  );

  info( sprintf( 'New Link Group created for &quot;%s&quot;.', $new_group->name ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created Link Group >%s< (ID:%s)', $new_group->name, $new_group->id ),
  );

  flash( success => sprintf( 'New Link Group <strong>%s</strong> successfully created.', $new_group->name ) );
  redirect '/admin/manage_links/groups';
};


=head2 GET C</admin/manage_links/groups/:group_id/edit>

Route to the edit link group form. Admin required.

=cut

get '/admin/manage_links/groups/:group_id/edit' => require_role Admin => sub
{
  my $group_id = route_parameters->get( 'group_id' );

  my $group = $SCHEMA->resultset( 'LinkGroup' )->find( $group_id );

  if
  (
    ! defined $group
    or
    ref( $group ) ne 'QP::Schema::Result::LinkGroup'
  )
  {
    flash( error => 'Could not edit Link Group. Invalid or missing group ID.' );
    redirect '/admin/manage_links/groups';
  }


  template 'admin_manage_links_groups_edit_form',
  {
    data =>
    {
      group => $group,
    },
    title => 'Edit Link Group',
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Link Groups', link => '/admin/manage_links/groups' },
      { name => 'Edit Link Group', current => 1 },
    ],
  };
};


=head2 POST C</admin/manage_links/groups/:group_id/update>

Route to update database info from the edit link group form. Admin required.

=cut

post '/admin/manage_links/groups/:group_id/update' => require_role Admin => sub
{
  my $group_id = route_parameters->get( 'group_id' );

  my $group = $SCHEMA->resultset( 'LinkGroup' )->find( $group_id );

  if
  (
    not defined $group
    or
    ref( $group ) ne 'QP::Schema::Result::LinkGroup'
  )
  {
    warn sprintf( 'Invalid or undefined link group ID: >%s<', $group_id );
    flash( error => 'Could not edit Link Group. Invalid or missing group ID.' );
    redirect '/admin/manage_links/groups';
  }

  my $orig_group = Clone::clone( $group );
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  $group->name( body_parameters->get( 'name' ) );
  $group->order_by( ( body_parameters->get( 'order_by' ) // 1 ) );

  $group->update;

  flash success => sprintf( 'Link Group &quot;<strong>%s</strong>&quot; has been updated.', $group->name );
  info sprintf( 'Updated link group >%s< -> >%s<, on %s', $orig_group->name, $group->name, $now );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Updated Link Group %s -&gt; %s ', $orig_group->name, $group->name ),
  );
  redirect '/admin/manage_links/groups';
};


=head2 GET C</admin/manage_links/groups/:group_id/delete>

Route for deleting a particular link group. Admin required.

=cut

get '/admin/manage_links/groups/:group_id/delete' => require_role Admin => sub
{
  my $group_id = route_parameters->get( 'group_id' );

  my $group = $SCHEMA->resultset( 'LinkGroup' )->find( $group_id );

  if
  (
    not defined $group
    or
    ref( $group ) ne 'QP::Schema::Result::LinkGroup'
  )
  {
    warn sprintf( 'Invalid or undefined group ID: >%s<', $group_id );
    flash error => 'Error: Invalid or undefined Link Group ID.';
    redirect '/admin/manage_links/groups';
  }

  my $groupname = $group->name;
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  $group->delete;

  info sprintf( 'Deleted link group >%s<, on %s', $groupname, $now );
  flash success => sprintf( 'Successfully deleted Link Group &quot;<strong>%s</strong>&quot;', $groupname );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Deleted Link Group >%s< (ID:%s)', $groupname, $group_id ),
  );

  redirect '/admin/manage_links/groups';
};


=head2 GET C</admin/manage_links/links>

Route to Links management dashboard. Requires being logged in and of admin role.

=cut

get '/admin/manage_links/links' => require_role Admin => sub
{
  my @links = $SCHEMA->resultset( 'Link' )->search( undef,
                                                          {
                                                            order_by =>
                                                            {
                                                              -asc =>
                                                              [
                                                                'link_group_id',
                                                                'name',
                                                              ]
                                                            },
                                                          }
  );

  my @groups = $SCHEMA->resultset( 'LinkGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_links',
  {
    data =>
    {
      links  => \@links,
      groups => \@groups,
    },
    breadcrumbs =>
    [
      { name => 'Admin', link => '/admin' },
      { name => 'Manage Links', current => 1 },
    ],
    title => 'Manage Links',
  };
};


=head2 GET C</admin/manage_links/links/add>

Route to add new link form. Requires being logged in and of Admin role.

=cut

get '/admin/manage_links/links/add' => require_role Admin => sub
{
  my @groups   = $SCHEMA->resultset( 'LinkGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );
  template 'admin_manage_links_add_form',
      {
        data =>
        {
          groups => \@groups,
        },
        title => 'Add Link',
      },
      {
        layout => 'ajax-modal'
      };
};


=head2 POST C</admin/manage_links/links/create>

Route to save new link data to the database.  Requires being logged in and of Admin role.

=cut

post '/admin/manage_links/links/create' => require_role Admin => sub
{
  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;

  my $new_link = $SCHEMA->resultset( 'Link' )->create(
    {
      name          => body_parameters->get( 'name' ),
      link_group_id => body_parameters->get( 'link_group_id' ),
      url           => body_parameters->get( 'url' ),
      show_url      => body_parameters->get( 'show_url' ),
    }
  );

  my $fields = body_parameters->as_hashref;
  my @fields = ();
  foreach my $key ( sort keys %{ $fields } )
  {
    push @fields, sprintf( '%s: %s', $key, $fields->{$key} );
  }

  info sprintf( 'Created new link >%s<, ID: >%s<, on %s', body_parameters->get( 'name' ), $new_link->id, $now );

  flash success => sprintf( 'Successfully created Link &quot;<strong>%s</strong>&quot;!', body_parameters->get( 'name' ) );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Created new link<br>%s', join( '<br>', @fields ) ),
  );

  redirect '/admin/manage_links/links';
};


=head2 AJAX C</admin/manage_links/links/:link_id/edit>

Route for presenting the edit link form. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_links/links/:link_id/edit' => require_role Admin => sub
{
  my $link_id = route_parameters->get( 'link_id' );

  my $link = $SCHEMA->resultset( 'Link' )->find( $link_id );

  if
  (
    ! defined $link
    or
    ref( $link ) ne 'QP::Schema::Result::Link'
  )
  {
    info sprintf( 'Invalid or missing link ID: >%s< for Edit Link', $link_id );
    flash( error => 'Could not edit link: Invalid or missing link ID.' );
    redirect '/admin/manage_links/link';
  }

  my @groups   = $SCHEMA->resultset( 'LinkGroup' )->search( undef,
                                                          {
                                                            order_by => { -asc => 'name' },
                                                          }
  );

  template 'admin_manage_links_edit_form',
      {
        data =>
        {
          groups => \@groups,
          link   => $link,
        },
        title => 'Edit Link',
      },
      {
        layout => 'ajax-modal'
      };
};


=head2 POST C</admin/manage_links/links/:link_id/update>

Route to send form data to for updating a link in the DB. Requires user to have Admin role.

=cut

post '/admin/manage_links/links/:link_id/update' => require_role Admin => sub
{
  my $link_id = route_parameters->get( 'link_id' );

  my $link      = $SCHEMA->resultset( 'Link' )->find( $link_id );
  my $orig_link = Clone::clone( $link );

  if
  (
    not defined $link
    or
    ref( $link ) ne 'QP::Schema::Result::Link'
  )
  {
    flash( error => 'Error: Cannot update link - Invalid or unknown ID.' );
    redirect '/admin/manage_links/links';
  }

  my $now = DateTime->now( time_zone => 'America/New_York' )->datetime;
  $link->link_group_id( body_parameters->get( 'link_group_id' ) );
  $link->name( body_parameters->get( 'name' ) );
  $link->url( body_parameters->get( 'url' ) );
  $link->show_url( body_parameters->get( 'show_url' ) ? body_parameters->get( 'show_url' ) : 0 );

  $link->update();

  info sprintf( 'Link >%s< updated by %s on %s.', $link->name, logged_in_user->username, $now );

  my $old =
  {
    link_group_id => $orig_link->link_group_id,
    name          => $orig_link->name,
    url           => $orig_link->url,
    show_url      => $orig_link->show_url,
  };
  my $new =
  {
    link_group_id => body_parameters->get( 'link_group_id' ),
    name          => body_parameters->get( 'name' ),
    url           => body_parameters->get( 'url' ),
    show_url      => body_parameters->get( 'show_url' ) ? body_parameters->get( 'show_url' ) : 0,
  };

  my $diffs = QP::Log->find_changes_in_data( old_data => $old, new_data => $new );

  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Link modified:<br>%s', join( ', ', @{ $diffs } ) ),
  );

  flash( success => sprintf( 'Successfully updated link &quot;<strong>%s</strong>&quot;.',
                                body_parameters->get( 'name' ) ) );
  redirect '/admin/manage_links/links';
};


=head2 GET C</admin/manage_links/links/:link_id/delete>

Route to delete a link. Requires the user be logged in and an Admin.

=cut

get '/admin/manage_links/links/:link_id/delete' => require_role Admin => sub
{
  my $link_id = route_parameters->get( 'link_id' );

  my $link = $SCHEMA->resultset( 'Link' )->find( $link_id );
  my $link_name = $link->name;

  if
  (
    not defined $link
    or
    ref( $link ) ne 'QP::Schema::Result::Link'
  )
  {
    flash( error => 'Error: Cannot delete link - Invalid or unknown ID.' );
    redirect '/admin/manage_links/links';
  }

  $link->delete;

  flash success => sprintf( 'Successfully deleted Link <strong>%s</strong>.', $link_name );
  my $logged = QP::Log->admin_log
  (
    admin       => sprintf( '%s (ID:%s)', logged_in_user->username, logged_in_user->id ),
    ip_address  => ( request->header('X-Forwarded-For') // 'Unknown' ),
    log_level   => 'Info',
    log_message => sprintf( 'Link &quot;%s&quot; deleted', $link_name ),
  );
  redirect '/admin/manage_links/links';
};


=head2 permission_denied_page_handler

Routine to display the 'permission_denied' screen when a User doesn't have the proper role.

=cut

sub permission_denied_page_handler
{
  template 'views/permission_denied.tt';
}

true;
