#!/usr/bin/env perl
use strict;
use warnings;

use Test2::V0;

use mojotodo::Model::ListShare;

subtest 'ListShare model instantiates' => sub {
    my $share = mojotodo::Model::ListShare->new(
        todo_list_id       => 10,
        user_id            => 20,
        created_by_user_id => 1,
    );

    isa_ok($share, 'mojotodo::Model::ListShare');
    is($share->todo_list_id, 10, 'todo_list_id set');
    is($share->user_id, 20, 'user_id set');
    is($share->created_by_user_id, 1, 'created_by_user_id set');
};

subtest 'ListShare relation methods exist' => sub {
    ok(mojotodo::Model::ListShare->can('todo_list'), 'belongs_to todo_list accessor exists');
    ok(mojotodo::Model::ListShare->can('user'), 'belongs_to user accessor exists');
    ok(mojotodo::Model::ListShare->can('created_by_user'), 'belongs_to created_by_user accessor exists');
};

done_testing;
