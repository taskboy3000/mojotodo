package mojotodo::Model::Notification;
use strict;
use warnings;

use Moo;
extends 'Durance::Model';
use Durance::DSL;

tablename 'notifications';

column id               => ( is => 'rw', isa => 'Int', primary_key => 1 );
column user_id           => ( is => 'rw', isa => 'Int', required => 1 );
column type             => ( is => 'rw', isa => 'Str', required => 1, length => 32 );
column title            => ( is => 'rw', isa => 'Str', required => 1, length => 255 );
column body             => ( is => 'rw', isa => 'Text' );
column reference_type   => ( is => 'rw', isa => 'Str', length => 32 );
column reference_id     => ( is => 'rw', isa => 'Int' );
column read_epoch       => ( is => 'rw', isa => 'Int' );
column created_at       => ( is => 'rw', isa => 'Timestamp' );
column updated_at       => ( is => 'rw', isa => 'Timestamp' );

belongs_to user => (
    is          => 'rw',
    isa         => 'mojotodo::Model::User',
    foreign_key => 'user_id',
);

validates type => ( format => qr/^(task_assigned|task_shared|task_completed)$/ );

sub inbox {
    my ($class, $user_id, $opts) = @_;
    $opts //= {};

    my $limit = $opts->{limit} // 20;
    my $offset = $opts->{offset} // 0;

    my @notifications = $class->where({ user_id => $user_id })
        ->order('created_at DESC')
        ->limit($limit)
        ->offset($offset)
        ->all;

    return [map { $_->to_hash } @notifications];
}

sub unread_count {
    my ($class, $user_id) = @_;

    my @unread = $class->where({ 
        user_id     => $user_id,
        read_epoch  => undef,
    })->all;

    return scalar @unread;
}

1;
