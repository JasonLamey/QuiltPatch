package QP::Mail;

use Dancer2 appname => 'QP';

use strict;
use warnings;

# QP modules
use QP::Schema;

# Third Party modules
use version; our $VERSION = qv( 'v0.1.0' );
use Emailesque;
use Const::Fast;

const my $SCHEMA       => QP::Schema->db_connect();
const my $SYSTEM_FROM  => 'Quilt Patch <noreply@quiltpatchva.com>';
const my %EMAIL_CONFIG => (
                            driver => 'sendmail',
                            path   => '/usr/sbin/sendmail',
                          );


=head1 NAME

QP::Mail


=head1 AUTHOR

Jason Lamey L<email:jasonlamey@gmail.com>


=head1 SYNOPSIS AND USAGE

This module handles all of the mail handlers for the various emailings that need to go out.


=head1 METHODS


=head2 preflight_checklist()

Performs a series of basic pre-send error checks to ensure all necessary information for sending an e-mail
has been provided. These checks are common to all of the e-mail sending functions.

=over 4

=item Input: Takes a hash containing [ C<email>, C<username>, C<full_name>, C<email_type> ]. Email_type is the name of the e-mail being sent.

=item Output: Hashref containing [ C<success>, C<message> ].  Success is an integer (0/1). Message contains an error message, or undef.

=back

    my $preflight = QP::Mail->preflight_checklist(
                                                       username   => $username,
                                                       email      => $email_address,
                                                       full_name  => $full_name,
                                                       email_type => $email_type,
                                                      );

=cut

sub preflight_checklist
{
    my ( $self, %params ) = @_;

    my $username   = delete $params{'username'}   // undef;
    my $full_name  = delete $params{'full_name'}  // undef;
    my $email      = delete $params{'email'}      // undef;
    my $email_type = delete $params{'email_type'} // 'E-mail';

    my %return = ( success => 0, message => '' );
    # Need a username or a full_name for addressing an e-mail to a recipient.
    if ( ( not defined $username ) and ( not defined $full_name ) )
    {
        $return{'message'} = "Could not send the $email_type because you didn't provide a username or full name.";
        error "Email Preflight Failed: Could not send $email_type because no username or full name was provided.";
        return \%return;
    }

    # Cannot send an e-mail without an e-mail address...
    if ( not defined $email )
    {
        $return{'message'} = "Could not send the $email_type because you didn't provide an e-mail address.";
        error "Email Preflight Failed: Could not send $email_type because no 'To:' e-mail address was provided.";
        return \%return;
    }

    # Nothing failed, let's return.
    $return{'success'} = 1;
    return \%return;
}


=head2 send_welcome_email()

This function sends out the user welcome email, complete with a confirmation code and link.

=over 4

=item Input: This function receives the dsl, along with a hash with keys C<[ code, email, user ]> from Dancer2::Plugin::Auth::Extensible. C<code> is a password reset code, so it can be ignored in this function. C<email> is the user's email address.  C<user> is a hashref of user account data.

=item Output: Returns a hashref containing the keys C<[ success, error ]>. C<success> is a boolean. C<error> is the error message generated, otherwise C<undef>.

=back

  $result = QP::Mail::send_welcome_email();

=cut

sub send_welcome_email
{
  my ( $dsn, %params ) = @_;

  my $user  = delete $params{'user'}  // undef;
  my $email = delete $params{'email'} // undef;

  my %return = ( success => 0, error => undef );

  my $new_user = $SCHEMA->resultset( 'User' )->find( { username => $user->{'username'} } );
  if
  (
    not defined $new_user
    or
    ref( $new_user ) ne 'QP::Schema::Result::User'
  )
  {
    $return{'error'} = sprintf( 'Invalid or undefined user for username >%s< in send_welcome_email.', $user->{'username'} );
    return \%return;
  }

  # Ensure we have the bare minimum to proceed.
  my $preflight = QP::Mail->preflight_checklist(
                                                      username   => $new_user->username,
                                                      full_name  => $new_user->full_name,
                                                      email      => $new_user->email,
                                                      email_type => 'Welcome Email',
                                                    );
  if ( ! $preflight->{'success'} )
  {
    $return{'error'} = $preflight->{'message'};
    error sprintf( 'Preflight Checklist for email failed for %s: %s', 'Welcome Email', $preflight->{'message'} );
    return \%return;
  }

  my $send_email = Emailesque->new(
                                    driver => $EMAIL_CONFIG{'driver'},
                                    path   => $EMAIL_CONFIG{'path'},
                                    to     => QP::Mail->format_address(
                                                                            username  => $new_user->username,
                                                                            full_name => $new_user->full_name,
                                                                            email     => $new_user->email,
                                                                           ),
                                    from    => $SYSTEM_FROM,
                                    subject => 'Thanks For Signing Up with Infinite Monkeys Games!',
                                    type    => 'html',
  );

  $send_email->send(
                    {
                      message => template(
                                          'email/welcome_email.tt',
                                          {
                                            username  => $new_user->username,
                                            full_name => $new_user->full_name,
                                            ccode     => $new_user->confirm_code,
                                          },
                                          { layout => undef },
                                         ),
                    }
  );

  info sprintf( 'Successfully sent Welcome Email to >%s<.', $new_user->email );
  $return{'success'} = 1;
  return \%return;
}


=head2 send_password_reset_email()

This function sends out the user password reset email, complete with a reset code and link.

=over 4

=item Input: This function receives the dsl, along with a hash with keys C<[ code, email ]> from Dancer2::Plugin::Auth::Extensible. C<code> is a password reset code, so it can be ignored in this function. C<email> is the user's email address.

=item Output: Returns a hashref containing the keys C<[ success, error ]>. C<success> is a boolean. C<error> is the error message generated, otherwise C<undef>.

=back

  $result = QP::Mail::send_password_reset_email();

=cut

sub send_password_reset_email
{
  my ( $dsn, %params ) = @_;

  my $email = delete $params{'email'} // undef;
  my $code  = delete $params{'code'}  // undef;

  my $user = $SCHEMA->resultset( 'User' )->find( { email => $email } ) if defined $email;

  my $return = 0;

  if ( ! defined $user )
  {
    error sprintf( 'send_password_reset_email could not find User from e-mail address: >%s<.', $email );
    return $return;
  }

  # Ensure we have the bare minimum to proceed.
  my $preflight = QP::Mail->preflight_checklist(
                                                      username   => $user->username,
                                                      full_name  => $user->full_name,
                                                      email      => $email,
                                                      email_type => 'Password Reset Email',
                                                    );
  if ( ! $preflight->{'success'} )
  {
    error sprintf( 'Preflight Checklist for email failed for %s: %s', 'Password Reset Email', $preflight->{'message'} );
    return $return;
  }

  my $send_email = Emailesque->new(
                                    driver => $EMAIL_CONFIG{'driver'},
                                    path   => $EMAIL_CONFIG{'path'},
                                    to     => QP::Mail->format_address(
                                                                            username  => $user->username,
                                                                            full_name => $user->full_name,
                                                                            email     => $email,
                                                                           ),
                                    from    => $SYSTEM_FROM,
                                    subject => 'Your Infinite Monkeys Games Password Reset Request',
                                    type    => 'html',
  );

  $send_email->send(
                    {
                      message => template(
                                          'email/password_reset.tt',
                                          {
                                            username  => $user->username,
                                            full_name => $user->full_name,
                                            code     => $code,
                                          },
                                          { layout => undef },
                                         ),
                    }
  );

  info sprintf( 'Successfully sent Password Reset Email to >%s<.', $email );
  $return = 1;
  return $return;
}


=head2 send_contact_us_notification()

This function sends out the contact us email to an admin account, including all info in the Contact Us form.

=over 4

=item Input: This method receives all the data from the Contact Us email in a hash.

=item Output: Returns a hashref containing the keys C<[ success, error ]>. C<success> is a boolean. C<error> is the error message generated, otherwise C<undef>.

=back

  $result = QP::Mail::send_contact_us_notification();

=cut

sub send_contact_us_notification
{
  my ( %params ) = @_;

  my $name    = delete $params{'name'}       // undef;
  my $email   = delete $params{'email'}      // undef;
  my $message = delete $params{'comments'}   // undef;
  my $created = delete $params{'created_on'} // undef;

  my %return = ( success => 0, error => undef );

  # Ensure we have the bare minimum to proceed.
  my $preflight = QP::Mail->preflight_checklist(
                                                      username   => $name,
                                                      full_name  => undef,
                                                      email      => $email,
                                                      email_type => 'Contact Us Email',
                                                    );
  if ( ! $preflight->{'success'} )
  {
    $return{'error'} = $preflight->{'message'};
    error sprintf( 'Preflight Checklist for email failed for %s: %s', 'Contact Us Email', $preflight->{'message'} );
    return \%return;
  }

  my $send_email = Emailesque->new(
                                    driver => $EMAIL_CONFIG{'driver'},
                                    path   => $EMAIL_CONFIG{'path'},
                                    to     => QP::Mail->format_address(
                                                                            username  => 'Quilt Patch Contact Us',
                                                                            full_name => 'The Quilt Patch',
                                                                            email     => 'jasonlamey@gmail.com',
                                                                           ),
                                    from    => $SYSTEM_FROM,
                                    subject => 'Contact Us',
                                    type    => 'html',
  );

  $send_email->send(
                    {
                      message => template(
                                          'email/contact_us.tt',
                                          {
                                            name    => $name,
                                            email   => $email,
                                            message => $message,
                                            created => $created,
                                          },
                                          { layout => undef },
                                         ),
                    }
  );

  info sprintf( 'Successfully sent Contact Us Email to >%s<.', $email );
  $return{'success'} = 1;
  return \%return;
}


=head2 format_address()

Creates a valid To: e-mail address.  If a username or full name are provided, then an address in the format of C<Full Name E<lt>email@address.comE<gt>>
is provided. Otherwise, just the e-mail address is returned.  C<undef> is returned if no valid e-mail address is supplied.

=over 4

=item Input: Hash containing [C<username> (optional), C<full_name> (optional), and/or C<email>].

=item Ouptut: String containing the formatted e-mail address, or C<undef>.

=back

    my $to = QP::Mail->format_address( username => $username, full_name => $full_name, email => $email );

=cut

sub format_address
{
    my ( $self, %params ) = @_;

    my $username  = delete $params{'username'}  // undef;
    my $full_name = delete $params{'full_name'} // undef;
    my $email     = delete $params{'email'}     // undef;

    if ( not defined $email ) { return undef };

    if ( not defined $username && not defined $full_name )
    {
        return $email;
    }

    return ( defined $full_name ) ? "$full_name <$email>" : "$username <$email>";
}


=head1 COPYRIGHT & LICENSE

Copyright 2017, Perl Poet L<http://www.perlpoet.com>
All rights reserved.

=cut

1;
