#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use Test2::V0;
use Test::Mojo;

use mojotodo::Model::User;

my $db_path = File::Spec->catfile('t', 'test.db');
unlink $db_path if -e $db_path;

$ENV{MOJOTODO_DBNAME} = $db_path;
delete $ENV{MOJOTODO_DSN};
$ENV{MOJO_MODE} = 'development';
$ENV{MOJOTODO_CODE_PEPPER} = 'test-pepper';

my $t = Test::Mojo->new('mojotodo');

subtest 'request-code requires email' => sub {
    $t->post_ok('/api/auth/request-code' => json => {})
        ->status_is(400)
        ->json_is('/error', 'Email is required');
};

subtest 'request-code sends code and verify creates user' => sub {
    my $email = 'new-user@example.com';

    ok(!mojotodo::Model::User->where({ email => $email })->first,
        'user does not exist before challenge verification');

    $t->post_ok('/api/auth/request-code' => json => { email => $email })
        ->status_is(202)
        ->json_is('/status', 'code_sent');

    my $code = $t->tx->res->json('/code');
    ok($code, 'development response returns code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => '000000',
    })->status_is(401)
      ->json_is('/error', 'Invalid code');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => $code,
    })->status_is(200)
      ->json_is('/status', 'authenticated')
      ->json_is('/user/email', $email);

    ok(mojotodo::Model::User->where({ email => $email })->first,
        'user auto-created after successful verification');

    $t->post_ok('/api/auth/verify-code' => json => {
        email => $email,
        code  => $code,
    })->status_is(401)
      ->json_is('/error', 'Invalid code');
};

subtest 'resend cooldown is enforced' => sub {
    my $email = 'cooldown@example.com';

    $t->post_ok('/api/auth/request-code' => json => { email => $email })
        ->status_is(202)
        ->json_is('/status', 'code_sent');

    $t->post_ok('/api/auth/request-code' => json => { email => $email })
        ->status_is(429)
        ->json_is('/error', 'Please wait before requesting another code');
};

subtest 'logout endpoint works' => sub {
    $t->post_ok('/api/logout')
        ->status_is(200)
        ->json_is('/status', 'logged_out');
};

done_testing;
