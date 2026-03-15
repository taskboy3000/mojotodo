package mojotodo::Model::TaskAssignment;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'task_assignments';

column id                  => ( is => 'rw', isa => 'Int', primary_key => 1 );
column task_id             => ( is => 'rw', isa => 'Int', required => 1 );
column source_list_id      => ( is => 'rw', isa => 'Int', required => 1 );
column target_list_id      => ( is => 'rw', isa => 'Int', required => 1 );
column assigned_by_user_id => ( is => 'rw', isa => 'Int', required => 1 );
column assigned_to_user_id => ( is => 'rw', isa => 'Int', required => 1 );
column created_at          => ( is => 'rw', isa => 'Timestamp' );
column updated_at          => ( is => 'rw', isa => 'Timestamp' );

belongs_to task => (
    is          => 'rw',
    isa         => 'mojotodo::Model::Task',
    foreign_key => 'task_id',
);

belongs_to source_list => (
    is          => 'rw',
    isa         => 'mojotodo::Model::TodoList',
    foreign_key => 'source_list_id',
);

belongs_to target_list => (
    is          => 'rw',
    isa         => 'mojotodo::Model::TodoList',
    foreign_key => 'target_list_id',
);

belongs_to assigned_by_user => (
    is          => 'rw',
    isa         => 'mojotodo::Model::User',
    foreign_key => 'assigned_by_user_id',
);

belongs_to assigned_to_user => (
    is          => 'rw',
    isa         => 'mojotodo::Model::User',
    foreign_key => 'assigned_to_user_id',
);

1;
