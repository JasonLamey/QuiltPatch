package QP::Schema::Result::ClassInfo;

use base qw/DBIx::Class::Core/;

use DateTime;

__PACKAGE__->table( 'classes' );

__PACKAGE__->add_columns(
                          id =>
                          {
                            data_type         => 'integer',
                            size              => 8,
                            is_nullable       => 0,
                            is_auto_increment => 1,
                          },
                          class_group_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 0,
                          },
                          class_subgroup_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
                          },
                          teacher_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
                          },
                          secondary_teacher_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
                          },
                          tertiary_teacher_id =>
                          {
                            datatype          => 'integer',
                            size              => 8,
                            is_nullable       => 1,
                          },
                          title =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 0,
                          },
                          description =>
                          {
                            data_type         => 'text',
                            is_nullable       => 0,
                            default_value     => undef,
                          },
                          num_sessions =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          fee =>
                          {
                            data_type         => 'varchar',
                            size              => 100,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          skill_level =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          is_also_embroidery =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 1,
                            default_value     => 0,
                          },
                          is_also_club =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 1,
                            default_value     => 0,
                          },
                          show_club =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          image_filename =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          supply_list_filename =>
                          {
                            data_type         => 'varchar',
                            size              => 255,
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          no_supply_list =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          always_show =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                          anchor =>
                          {
                            data_type         => 'varchar',
                            is_nullable       => 1,
                            default_value     => undef,
                          },
                          is_new =>
                          {
                            data_type         => 'boolean',
                            is_nullable       => 0,
                            default_value     => 0,
                          },
                        );

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->belongs_to( 'class_group' => 'QP::Schema::Result::ClassGroup',    'class_group_id' );
__PACKAGE__->belongs_to( 'subgroup'    => 'QP::Schema::Result::ClassSubgroup', 'class_subgroup_id' );

__PACKAGE__->has_many( 'dates'         => 'QP::Schema::Result::ClassDate',    'class_id' );
__PACKAGE__->has_many( 'files'         => 'QP::Schema::Result::ClassFile',    'class_id' );
__PACKAGE__->has_many( 'classteachers' => 'QP::Schema::Result::ClassTeacher', 'class_id', { order_by => { -asc => 'sort_order' } } );
__PACKAGE__->has_many( 'classbookmarks' => 'QP::Schema::Result::ClassBookmark', 'class_id', { order_by => { -desc => 'created_at' } } );

__PACKAGE__->many_to_many( 'teachers'  => 'classteachers',  'teacher' );
__PACKAGE__->many_to_many( 'bookmarks' => 'classbookmarks', 'user' );

# ADDITIONAL METHODS

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

  #warn sprintf( 'NEXT-UPCOMING-DATE: %s', $upcoming->date );

  return ( $upcoming // undef );
}

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

sub is_bookmarked
{
  my $self    = shift;
  my $user_id = shift // 0;

  return 0 if not defined $self or ref($self) ne 'QP::Schema::Result::ClassInfo';

  $user_id =~ s/\D//g;

  return 0 if $user_id == 0;

  my $bookmarked = $self->search_related( 'classbookmarks',
    {
      'user_id' => $user_id,
    }
  )->single();

  return ( ref( $bookmarked ) eq 'QP::Schema::Result::ClassBookmark' ) ? 1 : 0;
}

sub get_supply_list
{
  my $self = shift;

  my $supply_list = $self->search_related( 'files',
    {
      filetype => 'supply list',
    },
    {
      order_by => { -desc => created_on },
      rows     => 1
    }
  )->single();

  return ( ref( $supply_list ) eq 'QP::Schema::Result::ClassFile' ) ? $supply_list : undef;
}

sub get_photos
{
  my $self = shift;

  my @photos = $self->search_related( 'files',
    {
      filetype => 'image',
    },
    {
      order_by => { -desc => created_on },
    }
  );

  return ( scalar( @photos ) > 0 ) ? @photos : undef;
}

1;
