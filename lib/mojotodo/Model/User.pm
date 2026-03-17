package mojotodo::Model::User;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'users';

column id         => ( is => 'rw', isa => 'Int', primary_key => 1 );
column email      => ( is => 'rw', isa => 'Str', required => 1, unique => 1, length => 254 );
column phone      => ( is => 'rw', isa => 'Str', length => 20 );
column phone_verified => ( is => 'rw', isa => 'Bool', default => 0 );
column preferred_contact_method => ( is => 'rw', isa => 'Str', default => 'email' );
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

sub mask_phone {
    my ($self) = @_;
    my $phone = $self->phone // return undef;
    $phone =~ s/\D//g;
    return undef if length $phone < 4;
    return '*' x (length $phone - 4) . substr($phone, -4);
}

sub normalize_phone {
    my ($phone) = @_;
    return undef if !defined $phone || $phone eq '';
    $phone =~ s/\D//g;
    return length $phone >= 10 ? $phone : undef;
}

sub delete_account {
    my ($class, $user_id) = @_;

    my $self = $class->find($user_id);
    return 0 unless $self;

    my $dbh = $self->db->dbh;
    $dbh->begin_work;

    eval {
        my @assignments = mojotodo::Model::TaskAssignment->where({
            assigned_to_user_id => $user_id,
        })->all;

        for my $assignment (@assignments) {
            my $assigner = mojotodo::Model::User->find($assignment->assigned_by_user_id);
            if ($assigner) {
                my $task = mojotodo::Model::Task->find($assignment->task_id);
                if ($task) {
                    $task->todo_list_id($assignment->source_list_id);
                    $task->update;
                }
                $assignment->delete;
            } else {
                my $task = mojotodo::Model::Task->find($assignment->task_id);
                $task->delete if $task;
                $assignment->delete;
            }
        }

        my @outgoing = mojotodo::Model::TaskAssignment->where({
            assigned_by_user_id => $user_id,
        })->all;
        for my $assignment (@outgoing) {
            $assignment->delete;
        }

        my @challenges = mojotodo::Model::AuthChallenge->where({
            user_id => $user_id,
        })->all;
        for my $challenge (@challenges) {
            $challenge->delete;
        }

        my @shares = mojotodo::Model::ListShare->where({
            user_id => $user_id,
        })->all;
        for my $share (@shares) {
            $share->delete;
        }

        my @created_shares = mojotodo::Model::ListShare->where({
            created_by_user_id => $user_id,
        })->all;
        for my $share (@created_shares) {
            $share->delete;
        }

        my @notifications = mojotodo::Model::Notification->where({
            user_id => $user_id,
        })->all;
        for my $notification (@notifications) {
            $notification->delete;
        }

        my @lists = mojotodo::Model::TodoList->where({
            owner_user_id => $user_id,
        })->all;
        for my $list (@lists) {
            my @tasks = mojotodo::Model::Task->where({
                todo_list_id => $list->id,
            })->all;
            for my $task (@tasks) {
                $task->delete;
            }
            $list->delete;
        }

        $self->delete;
        $dbh->commit;
    };

    if ($@) {
        $dbh->rollback;
        return 0;
    }

    return 1;
}

1;
