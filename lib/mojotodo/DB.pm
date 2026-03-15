package mojotodo::DB;
use strict;
use warnings;

use Moo;
extends 'Durance::DB';

our $gDSN;

sub _build_dsn {
    my ($self) = @_;
    return $ENV{MOJOTODO_DSN} if $ENV{MOJOTODO_DSN};
    if ($ENV{MOJOTODO_DBNAME}) {
        return 'dbi:SQLite:dbname=' . $ENV{MOJOTODO_DBNAME};
    }
    return $gDSN if defined $gDSN && length $gDSN;
    return 'dbi:SQLite:dbname=app.db';
}

1;
