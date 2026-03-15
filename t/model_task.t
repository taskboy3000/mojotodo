#!/usr/bin/env perl
use strict;
use warnings;

use Test2::V0;

use mojotodo::Model::Task;

subtest 'Task model instantiates' => sub {
    my $task = mojotodo::Model::Task->new(
        todo_list_id       => 10,
        title              => 'Ship MVP auth',
        description        => 'Complete OTP hardening pass',
        status             => 'open',
        created_by_user_id => 1,
    );

    isa_ok($task, 'mojotodo::Model::Task');
    is($task->todo_list_id, 10, 'todo_list_id set');
    is($task->title, 'Ship MVP auth', 'title set');
    is($task->status, 'open', 'status set');
    is($task->created_by_user_id, 1, 'created_by_user_id set');
};

done_testing;
