#!/usr/bin/env perl
use strict;
use warnings;

use Test2::V0;

use mojotodo::Model::TodoList;
use mojotodo::Model::Task;
use mojotodo::Model::User;

subtest 'TodoList model instantiates' => sub {
    my $list = mojotodo::Model::TodoList->new(
        owner_user_id => 1,
        title         => 'Inbox',
        archived      => 0,
    );

    isa_ok($list, 'mojotodo::Model::TodoList');
    is($list->owner_user_id, 1, 'owner_user_id set');
    is($list->title, 'Inbox', 'title set');
    is($list->archived, 0, 'archived default/coercion works');
};

subtest 'TodoList and User relation methods exist' => sub {
    ok(mojotodo::Model::TodoList->can('user'), 'TodoList has belongs_to user accessor');
    ok(mojotodo::Model::User->can('todo_lists'), 'User has has_many todo_lists accessor');
    ok(mojotodo::Model::TodoList->can('tasks'), 'TodoList has has_many tasks accessor');
    ok(mojotodo::Model::Task->can('todo_list'), 'Task has belongs_to todo_list accessor');
};

done_testing;
