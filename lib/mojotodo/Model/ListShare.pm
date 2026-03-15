package mojotodo::Model::ListShare;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'list_shares';

column id                 => ( is => 'rw', isa => 'Int', primary_key => 1 );
column todo_list_id       => ( is => 'rw', isa => 'Int', required => 1 );
column user_id            => ( is => 'rw', isa => 'Int', required => 1 );
column created_by_user_id => ( is => 'rw', isa => 'Int', required => 1 );
column created_at         => ( is => 'rw', isa => 'Timestamp' );
column updated_at         => ( is => 'rw', isa => 'Timestamp' );

belongs_to todo_list => (
    is          => 'rw',
    isa         => 'mojotodo::Model::TodoList',
    foreign_key => 'todo_list_id',
);

belongs_to user => (
    is          => 'rw',
    isa         => 'mojotodo::Model::User',
    foreign_key => 'user_id',
);

belongs_to created_by_user => (
    is          => 'rw',
    isa         => 'mojotodo::Model::User',
    foreign_key => 'created_by_user_id',
);

1;
