package mojotodo::Model::AuthChallenge;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'auth_challenges';

column id            => ( is => 'rw', isa => 'Int', primary_key => 1 );
column user_id       => ( is => 'rw', isa => 'Int' );
column email         => ( is => 'rw', isa => 'Str', required => 1, length => 254 );
column code_hash     => ( is => 'rw', isa => 'Str', required => 1, length => 64 );
column code_salt     => ( is => 'rw', isa => 'Str', required => 1, length => 32 );
column created_epoch => ( is => 'rw', isa => 'Int', required => 1 );
column expires_epoch => ( is => 'rw', isa => 'Int', required => 1 );
column used_epoch    => ( is => 'rw', isa => 'Int' );
column attempt_count => ( is => 'rw', isa => 'Int', default => 0 );
column created_at    => ( is => 'rw', isa => 'Timestamp' );
column updated_at    => ( is => 'rw', isa => 'Timestamp' );

belongs_to user => (
    is          => 'rw',
    isa         => 'mojotodo::Model::User',
    foreign_key => 'user_id',
);

validates email => ( format => qr/^[^\s\@]+\@[^\s\@]+\.[^\s\@]+$/ );

1;
