package DBIx::Class::UserStamp;

use base qw(DBIx::Class);

use warnings;
use strict;

our $VERSION = '0.10';

__PACKAGE__->mk_classdata( 
    '__column_userstamp_triggers' => {
        on_update => [], on_create => []
    }
);

=head1 NAME

DBIx::Class::UserStamp - Automatically set update and create user id fields

=head1 DESCRIPTION

Automatically set fields on 'update' and 'create' that hold user id 
values in a table. This can be used for any user id based  
field that needs trigger like functionality when a record is 
added or updated.

=head1 SYNOPSIS

 package MyApp::Schema;

 __PACKAGE__->mk_group_accessors('simple' => qw/current_user_id/);


 package MyApp::Model::MyAppDB;
 use Moose;

 around 'build_per_context_instance' => sub {
   my ($meth, $self) = (shift, shift);
   my ($c) = @_; # There are other params but we dont care about them
   my $new = bless({ %$self }, ref($self));
   my $user_info = $c->_user_in_session; 
   my $user = $new->schema->resultset('User')->new_result({ %$user_info });
   $new->schema->current_user_id($user->id) if (defined $user_info);
   return $new;
 };


 package MyApp::Schema::SomeTable;

 __PACKAGE__->load_components(qw( UserStamp ... Core ));
 
 __PACKAGE__->add_columns(
    id => { data_type => 'integer' },
    u_created => { data_type => 'int', store_user_on_create => 1 },
    u_updated => { data_type => 'int',
        store_user_on_create => 1, store_user_on_update => 1 },
 );

Now, any update or create actions will update the specified columns with the
current user_id, using the current_user_id accessor.  

This is effectively trigger emulation to ease user id field insertion 

=cut

sub add_columns {
    my $self = shift;

    # Add everything else, get everything setup, and then process
    $self->next::method(@_);
   
    my @update_columns = ();
    my @create_columns = ();

    foreach my $column ( $self->columns ) {
        my $info = $self->column_info($column);
        if ( $info->{store_user_on_update} ) {
            push @update_columns, $column;
        }
        if ( $info->{store_user_on_create} ) {
            push @create_columns, $column;
        }
    }
    if ( @update_columns or @create_columns ) {
        my $triggers = {
            on_update => [ @update_columns ],
            on_create => [ @create_columns ],
        };
        $self->__column_userstamp_triggers($triggers);
    }
}

sub insert {
    my $self  = shift;
    my $attrs = shift;

    my $user_id = $self->get_current_user_id;

    my @columns = @{ $self->__column_userstamp_triggers()->{on_create} };

    foreach my $column ( @columns ) {
        next if defined $self->get_column( $column );
        my $accessor = $self->column_info($column)->{accessor} || $column;
        $self->$accessor($user_id);
    }
    
    return $self->next::method(@_);
}

sub update {
    my $self = shift;

    my $user_id = $self->get_current_user_id;
    my %dirty = $self->get_dirty_columns();
    my @columns = @{ $self->__column_userstamp_triggers()->{on_update} };

    foreach my $column ( @columns ) {
        next if exists $dirty{ $column };
        my $accessor = $self->column_info($column)->{accessor} || $column;
        $self->$accessor($user_id);
    }

    return $self->next::method(@_);
}

=head1 METHODS

=head2 get_current_user_id

This method is meant to be overridden.  The default is to return a 
schema accessor called current_user_id which should be populated as such.

=cut
sub get_current_user_id { shift->result_source->schema->current_user_id }

=head1 AUTHOR

 Matt S. Trout     <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTOR 

 John Goulah     <jgoulah@cpan.org>

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=cut

1;
