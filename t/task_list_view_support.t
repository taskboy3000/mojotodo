#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use Test2::V0;

use Durance::Schema;
use mojotodo::DB;
use mojotodo::Model::Task;
use mojotodo::Model::TaskAssignment;
use mojotodo::Model::TodoList;
use mojotodo::Model::User;

my $tmpdir = tempdir(CLEANUP => 1);
my $db_path = "$tmpdir/list_view.db";

$ENV{MOJOTODO_DSN} = "dbi:SQLite:dbname=$db_path";

my $db = mojotodo::DB->new;
my $schema = Durance::Schema->new(dbh => $db->dbh);

$schema->sync_table(mojotodo::Model::User->new(db => $db));
$schema->sync_table(mojotodo::Model::TodoList->new(db => $db));
$schema->sync_table(mojotodo::Model::Task->new(db => $db));
$schema->sync_table(mojotodo::Model::TaskAssignment->new(db => $db));

my $owner = mojotodo::Model::User->create({ email => 'owner@example.com', is_active => 1 });
my $assignee = mojotodo::Model::User->create({ email => 'assignee@example.com', is_active => 1 });

my $source_list = mojotodo::Model::TodoList->create({
    owner_user_id => $owner->id,
    title         => 'Source',
    archived      => 0,
});

my $target_list = mojotodo::Model::TodoList->create({
    owner_user_id => $assignee->id,
    title         => 'Target',
    archived      => 0,
});

my $assigned_task = mojotodo::Model::Task->create({
    todo_list_id       => $source_list->id,
    title              => 'Assigned task',
    status             => 'open',
    created_by_user_id => $owner->id,
});

my $local_task = mojotodo::Model::Task->create({
    todo_list_id       => $source_list->id,
    title              => 'Local task',
    status             => 'open',
    created_by_user_id => $owner->id,
});

mojotodo::Model::TaskAssignment->create({
    task_id             => $assigned_task->id,
    source_list_id      => $source_list->id,
    target_list_id      => $target_list->id,
    assigned_by_user_id => $owner->id,
    assigned_to_user_id => $assignee->id,
});

subtest 'list_view includes assignment labeling' => sub {
    my $rows = mojotodo::Model::Task->list_view($source_list->id);

    is(scalar @$rows, 2, 'source list returns both tasks by default');

    my ($row) = grep { $_->{id} == $assigned_task->id } @$rows;
    ok($row, 'assigned task is present');
    is($row->{is_assigned_out}, 1, 'assigned task flagged as assigned_out');
    is($row->{assigned_to_email}, 'assignee@example.com', 'assignee email included');
    is($row->{target_list_id}, $target_list->id, 'target list id included');
};

subtest 'hide_assigned_out filter excludes assigned tasks' => sub {
    my $rows = mojotodo::Model::Task->list_view($source_list->id, { hide_assigned_out => 1 });

    is(scalar @$rows, 1, 'only one non-assigned task remains');
    is($rows->[0]{id}, $local_task->id, 'local task remains visible');
};

done_testing;
