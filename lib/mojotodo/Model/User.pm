package mojotodo::Model::User;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'users';

column id         => ( is => 'rw', isa => 'Int', primary_key => 1 );
column email      => ( is => 'rw', isa => 'Str', required => 1, unique => 1, length => 254 );
column is_active  => ( is => 'rw', isa => 'Bool', default => 1 );
column created_at => ( is => 'rw', isa => 'Timestamp' );
column updated_at => ( is => 'rw', isa => 'Timestamp' );

has_many auth_challenges => (
    is          => 'rw',
    isa         => 'mojotodo::Model::AuthChallenge',
    foreign_key => 'user_id',
);

has_many todo_lists => (
    is          => 'rw',
    isa         => 'mojotodo::Model::TodoList',
    foreign_key => 'owner_user_id',
);

validates email => ( format => qr/^[^\s\@]+\@[^\s\@]+\.[^\s\@]+$/ );

1;
