package mojotodo::Model::Task;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'tasks';

column id                 => ( is => 'rw', isa => 'Int', primary_key => 1 );
column todo_list_id       => ( is => 'rw', isa => 'Int', required => 1 );
column title              => ( is => 'rw', isa => 'Str', required => 1, length => 255 );
column description        => ( is => 'rw', isa => 'Text' );
column status             => ( is => 'rw', isa => 'Str', required => 1, default => 'open', length => 32 );
column due_at             => ( is => 'rw', isa => 'Timestamp' );
column completed_at       => ( is => 'rw', isa => 'Timestamp' );
column created_by_user_id => ( is => 'rw', isa => 'Int', required => 1 );
column created_at         => ( is => 'rw', isa => 'Timestamp' );
column updated_at         => ( is => 'rw', isa => 'Timestamp' );

belongs_to todo_list => (
    is          => 'rw',
    isa         => 'mojotodo::Model::TodoList',
    foreign_key => 'todo_list_id',
);

validates title  => ( format => qr/\S/ );
validates status => ( format => qr/^(open|in_progress|done)$/ );

sub list_view {
    my ($class, $todo_list_id, $opts) = @_;
    $opts //= {};

    my $hide_assigned_out = $opts->{hide_assigned_out} ? 1 : 0;
    my @tasks = $class->where({ todo_list_id => $todo_list_id })->order('id ASC')->all;

    require mojotodo::Model::TaskAssignment;
    require mojotodo::Model::User;

    my @rows;
    for my $task (@tasks) {
        my $assignment = mojotodo::Model::TaskAssignment->where({
            task_id        => $task->id,
            source_list_id => $todo_list_id,
        })->order('id DESC')->first;

        my $is_assigned_out = $assignment ? 1 : 0;
        next if $hide_assigned_out && $is_assigned_out;

        my $row = $task->to_hash;
        $row->{is_assigned_out} = $is_assigned_out;

        if ($assignment) {
            $row->{target_list_id} = $assignment->target_list_id;
            my $assignee = mojotodo::Model::User->find($assignment->assigned_to_user_id);
            $row->{assigned_to_email} = $assignee->email if $assignee;
        }

        push @rows, $row;
    }

    return \@rows;
}

1;
