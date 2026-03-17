#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use Test2::V0;
use Test::Mojo;

use mojotodo::Model::User;
use mojotodo::Model::TodoList;
use mojotodo::Model::Task;

my $db_path = File::Spec->catfile('t', 'test.db');
unlink $db_path if -e $db_path;

$ENV{MOJOTODO_DBNAME} = $db_path;
delete $ENV{MOJOTODO_DSN};
$ENV{MOJO_MODE} = 'development';
$ENV{MOJOTODO_CODE_PEPPER} = 'test-pepper';

my $t = Test::Mojo->new('mojotodo');

subtest 'list sharing endpoints' => sub {
    my $owner_email = 'owner@example.com';
    my $collab_email = 'collab@example.com';

    $t->post_ok('/api/auth/request-code' => json => { email => $owner_email })
        ->status_is(202);
    my $owner_code = $t->tx->res->json('/code');
    diag("Owner code: $owner_code");

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $owner_email,
        code  => $owner_code,
    })->status_is(200)
      ->content_like(qr/authenticated/);

    $t->post_ok('/api/lists' => json => { title => 'My List' })
        ->status_is(201);
    my $list_id = $t->tx->res->json('/list/id');

    $t->post_ok('/api/auth/request-code' => json => { email => $collab_email })
        ->status_is(202);
    my $collab_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $collab_email,
        code  => $collab_code,
    })->status_is(200);

    # Re-authenticate as owner before sharing
    $t->post_ok('/api/auth/request-code' => json => { email => $owner_email })
        ->status_is(202);
    $owner_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $owner_email,
        code  => $owner_code,
    })->status_is(200);

    $t->post_ok("/api/lists/$list_id/share" => json => { email => $collab_email })
        ->status_is(201);
    my $share_id = $t->tx->res->json('/share/id');

    $t->get_ok("/api/lists/$list_id/share")
        ->status_is(200);
    my $collaborators = $t->tx->res->json('/collaborators');
    is(scalar @$collaborators, 1, 'one collaborator');
    is($collaborators->[0]{email}, $collab_email, 'collaborator email matches');

    $t->post_ok('/api/logout')->status_is(200);

    $t->post_ok('/api/auth/request-code' => json => { email => $collab_email })
        ->status_is(202);
    $collab_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $collab_email,
        code  => $collab_code,
    })->status_is(200);

    $t->get_ok("/api/lists/$list_id")
        ->status_is(200);

    $t->post_ok('/api/logout')->status_is(200);

    $t->post_ok('/api/auth/request-code' => json => { email => $owner_email })
        ->status_is(202);
    $owner_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $owner_email,
        code  => $owner_code,
    })->status_is(200);

    $t->delete_ok("/api/lists/$list_id/share/$share_id")
        ->status_is(200);

    $t->get_ok("/api/lists/$list_id/share")
        ->status_is(200);
    $collaborators = $t->tx->res->json('/collaborators');
    is(scalar @$collaborators, 0, 'no collaborators after delete');
};

subtest 'task assignment endpoints' => sub {
    my $owner_email = 'task-owner@example.com';
    my $other_email = 'other-user@example.com';

    $t->post_ok('/api/auth/request-code' => json => { email => $owner_email })
        ->status_is(202);
    my $owner_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $owner_email,
        code  => $owner_code,
    })->status_is(200);

    $t->post_ok('/api/lists' => json => { title => 'Source List' })
        ->status_is(201);
    my $source_list_id = $t->tx->res->json('/list/id');

    $t->post_ok('/api/lists' => json => { title => 'Target List' })
        ->status_is(201);
    my $target_list_id = $t->tx->res->json('/list/id');

    $t->post_ok("/api/lists/$source_list_id/tasks" => json => { title => 'Test Task' })
        ->status_is(201);
    my $task_id = $t->tx->res->json('/task/id');

    $t->post_ok('/api/auth/request-code' => json => { email => $other_email })
        ->status_is(202);
    my $other_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $other_email,
        code  => $other_code,
    })->status_is(200);

    # Re-authenticate as owner before sharing target list with other user
    $t->post_ok('/api/auth/request-code' => json => { email => $owner_email })
        ->status_is(202);
    $owner_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $owner_email,
        code  => $owner_code,
    })->status_is(200);

    $t->post_ok("/api/lists/$target_list_id/share" => json => { email => $other_email })
        ->status_is(201);

    # Re-authenticate as owner before assigning
    $t->post_ok('/api/auth/request-code' => json => { email => $owner_email })
        ->status_is(202);
    $owner_code = $t->tx->res->json('/code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $owner_email,
        code  => $owner_code,
    })->status_is(200);

    $t->post_ok("/api/tasks/$task_id/assign" => json => { target_list_id => $target_list_id })
        ->status_is(201);
    my $assignment_id = $t->tx->res->json('/assignment/id');

    $t->get_ok("/api/tasks/$task_id/assign")
        ->status_is(200);
    my $assignments = $t->tx->res->json('/assignments');
    is(scalar @$assignments, 1, 'one assignment');
    is($assignments->[0]{target_list_id}, $target_list_id, 'target list matches');

    $t->delete_ok("/api/tasks/$task_id/assign/$assignment_id")
        ->status_is(200);

    $t->get_ok("/api/tasks/$task_id/assign")
        ->status_is(200);
    $assignments = $t->tx->res->json('/assignments');
    is(scalar @$assignments, 0, 'no assignments after delete');
};

done_testing;
