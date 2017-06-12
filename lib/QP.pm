package QP;
use Dancer2;
use Dancer2::Session::Cookie;
use Dancer2::Plugin::Flash;
use Dancer2::Plugin::DBIC;
use Dancer2::Plugin::Auth::Extensible;

use strict;
use warnings;

use Data::Dumper;
use Const::Fast;
use DateTime;
use URI::Escape::JavaScript;
use DBICx::Sugar;

use QP::Log;
use QP::Mail;
use QP::Schema;
use QP::Util;

our $VERSION = '2.0';

const my $SCHEMA    => QP::Schema->db_connect();
const my $DT_PARSER => $SCHEMA->storage->datetime_parser;
const my $USER_SESSION_EXPIRE_TIME  => 172800; # 48 hours in seconds.
const my $ADMIN_SESSION_EXPIRE_TIME => 600;    # 10 minutes in seconds.
const my $DPAE_REALM                => 'site'; # Dancer2::Plugin::Auth::Extensible realm

$SCHEMA->storage->debug(1); # Turns on DB debuging. Turn off for production.

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

get '/calendar' => sub
{
  template 'calendar',
    { title => 'Events Calendar' };
};

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

  my @classes = $SCHEMA->resultset( 'Class' )->search(
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

get '/classes' => sub
{
  template 'classes',
  {
    title => 'Classes',
  };
};

get '/clubs' => sub
{
  my $today   = DateTime->today( time_zone => 'America/New_York' );
  my @classes = $SCHEMA->resultset( 'Class' )->search(
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
      classes => \@classes,
    },
  };
};

get '/embroidery' => sub
{
  my $today   = DateTime->today( time_zone => 'America/New_York' );
  my @classes = $SCHEMA->resultset( 'Class' )->search(
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

post '/search' => sub
{
  my $search = body_parameters->get( 'search' ) // undef;

  if ( ! defined $search or $search =~ /^[\s\W]*$/ )
  {
    flash( error => 'Invalid search term.' );
    redirect '/classes';
  }

  my @classes = $SCHEMA->resultset( 'Class' )->search(
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

get '/services' => sub
{
  template 'services',
  {
    title => 'Services',
  };
};

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


=head2 GET C</user>

GET route for the default user home page.

=cut

get '/user' => require_login sub
{
  redirect '/';
};


true;
