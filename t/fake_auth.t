#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use Test2::V0;
use Test::Mojo;

my $db_path = File::Spec->catfile('t', 'fake_auth_test.db');
unlink $db_path if -e $db_path;

$ENV{MOJOTODO_DBNAME} = $db_path;
delete $ENV{MOJOTODO_DSN};
$ENV{MOJO_MODE} = 'development';
$ENV{MOJOTODO_FAKE_AUTH} = '1';

my $t = Test::Mojo->new('mojotodo');

subtest 'fake auth bypass' => sub {
    my $email = 'fake@example.com';

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => 'any-code-works',
    })->status_is(200)
      ->content_like(qr/authenticated/);

    my $user_id = $t->tx->res->json('/user/id');
    ok($user_id, 'user id returned');
    is($t->tx->res->json('/user/email'), $email, 'email matches');

    $t->get_ok('/api/lists')
        ->status_is(200);
};

subtest 'default list created on first login' => sub {
    my $email = 'newuser@example.com';

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => 'any-code-works',
    })->status_is(200);

    my $user_id = $t->tx->res->json('/user/id');
    ok($user_id, 'user created');

    $t->get_ok('/api/lists?default=1')
        ->status_is(200);

    my $lists = $t->tx->res->json('/lists');
    is(scalar(@$lists), 1, 'one default list created');
    is($lists->[0]{title}, 'My Tasks', 'default list title is "My Tasks"');
    is($lists->[0]{owner_user_id}, $user_id, 'list owned by new user');
};

subtest 'existing user does not get duplicate default list' => sub {
    my $email = 'existing@example.com';

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => 'any-code-works',
    })->status_is(200);

    $t->post_ok('/api/lists' => json => {
        title => 'Second List',
    })->status_is(201);

    $t->get_ok('/api/lists')
        ->status_is(200);

    my $lists = $t->tx->res->json('/lists');
    is(scalar(@$lists), 2, 'user has two lists');

    $t->get_ok('/api/lists?default=1')
        ->status_is(200);

    my $default_lists = $t->tx->res->json('/lists');
    is(scalar(@$default_lists), 1, 'only one default list');
    is($default_lists->[0]{title}, 'My Tasks', 'default list still "My Tasks"');
};

subtest 'delete account unauthenticated' => sub {
    $t->post_ok('/api/logout')->status_is(200);
    $t->delete_ok('/api/account')
        ->status_is(401);
};

subtest 'delete account success' => sub {
    my $email = 'delete_me@example.com';

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => 'any-code-works',
    })->status_is(200);

    my $user_id = $t->tx->res->json('/user/id');
    ok($user_id, 'user created');

    $t->post_ok('/api/lists' => json => { title => 'Test List' })->status_is(201);
    $t->get_ok('/api/lists')->status_is(200);
    my $lists = $t->tx->res->json('/lists');
    is(scalar(@$lists), 2, 'user has two lists (default + new)');

    $t->delete_ok('/api/account')
        ->status_is(200);

    $t->get_ok('/api/lists')
        ->status_is(401);
};

subtest 'email can be reused after account deletion' => sub {
    my $email = 'reusable@example.com';

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => 'any-code-works',
    })->status_is(200);

    my $user_id = $t->tx->res->json('/user/id');
    ok($user_id, 'first user created');

    $t->delete_ok('/api/account')->status_is(200);

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => 'any-code-works',
    })->status_is(200);

    my $new_user_id = $t->tx->res->json('/user/id');
    ok($new_user_id, 'new user created with same email');
    cmp_ok($new_user_id, '!=', $user_id, 'new user has different id');
};

done_testing;
