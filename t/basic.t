#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use Test2::V0;
use Test::Mojo;

my $db_path = File::Spec->catfile('t', 'test.db');
unlink $db_path if -e $db_path;

$ENV{MOJOTODO_DBNAME} = $db_path;
delete $ENV{MOJOTODO_DSN};
$ENV{MOJO_MODE} = 'development';
$ENV{MOJOTODO_CODE_PEPPER} = 'test-pepper';

my $t = Test::Mojo->new('mojotodo');

$t->get_ok('/')
    ->status_is(302)
    ->header_like('Location', qr{/login});

$t->get_ok('/login')
    ->status_is(200);

done_testing;
