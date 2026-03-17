package mojotodo::Model::TodoList;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'todo_lists';

column id            => ( is => 'rw', isa => 'Int', primary_key => 1 );
column owner_user_id => ( is => 'rw', isa => 'Int', required => 1 );
column title         => ( is => 'rw', isa => 'Str', required => 1, length => 200 );
column position      => ( is => 'rw', isa => 'Int' );
column archived      => ( is => 'rw', isa => 'Bool', default => 0 );
column created_at    => ( is => 'rw', isa => 'Timestamp' );
column updated_at    => ( is => 'rw', isa => 'Timestamp' );

belongs_to user => (
    is          => 'rw',
    isa         => 'mojotodo::Model::User',
    foreign_key => 'owner_user_id',
);

has_many tasks => (
    is          => 'rw',
    isa         => 'mojotodo::Model::Task',
    foreign_key => 'todo_list_id',
);

validates title => ( format => qr/\S/ );

sub create_default_list {
    my ($class, $user_id) = @_;
    return $class->create({
        owner_user_id => $user_id,
        title         => 'My Tasks',
        archived      => 0,
    });
}

1;
