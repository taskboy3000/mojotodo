#!/usr/bin/env perl
use strict;
use warnings;

use Test2::V0;

use mojotodo::Model::TaskAssignment;

subtest 'TaskAssignment model instantiates' => sub {
    my $assignment = mojotodo::Model::TaskAssignment->new(
        task_id             => 100,
        source_list_id      => 10,
        target_list_id      => 20,
        assigned_by_user_id => 1,
        assigned_to_user_id => 2,
    );

    isa_ok($assignment, 'mojotodo::Model::TaskAssignment');
    is($assignment->task_id, 100, 'task_id set');
    is($assignment->source_list_id, 10, 'source_list_id set');
    is($assignment->target_list_id, 20, 'target_list_id set');
    is($assignment->assigned_by_user_id, 1, 'assigned_by_user_id set');
    is($assignment->assigned_to_user_id, 2, 'assigned_to_user_id set');
};

subtest 'TaskAssignment relation methods exist' => sub {
    ok(mojotodo::Model::TaskAssignment->can('task'), 'belongs_to task accessor exists');
    ok(mojotodo::Model::TaskAssignment->can('source_list'), 'belongs_to source_list accessor exists');
    ok(mojotodo::Model::TaskAssignment->can('target_list'), 'belongs_to target_list accessor exists');
    ok(mojotodo::Model::TaskAssignment->can('assigned_by_user'), 'belongs_to assigned_by_user accessor exists');
    ok(mojotodo::Model::TaskAssignment->can('assigned_to_user'), 'belongs_to assigned_to_user accessor exists');
};

done_testing;
