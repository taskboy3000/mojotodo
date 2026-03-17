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
column position           => ( is => 'rw', isa => 'Int' );
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
    my $limit = $opts->{limit} // 20;
    my $offset = $opts->{offset} // 0;
    my $include_count = $opts->{include_count};

    my @tasks = $class->where({ todo_list_id => $todo_list_id })
        ->order('position ASC, id DESC')
        ->limit($limit)
        ->offset($offset)
        ->all;

    require mojotodo::Model::TaskAssignment;
    require mojotodo::Model::User;

    my @all_tasks = $class->where({ todo_list_id => $todo_list_id })->order('position ASC, id DESC')->all;
    my %assigned_out;
    for my $t (@all_tasks) {
        my $assignment = mojotodo::Model::TaskAssignment->where({
            task_id        => $t->id,
            source_list_id => $todo_list_id,
        })->order('id DESC')->first;
        $assigned_out{$t->id} = $assignment ? $assignment : undef;
    }

    my $total = 0;
    my @rows;
    for my $task (@tasks) {
        my $assignment = $assigned_out{$task->id};

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
        $total++;
    }

    if ($include_count) {
        return {
            rows  => \@rows,
            total => $total,
        };
    }

    return \@rows;
}

1;
