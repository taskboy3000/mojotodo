package mojotodo;
use Mojo::Base 'Mojolicious', -signatures;

use Digest::SHA qw(sha256_hex);
use Mojo::Util qw(secure_compare trim);

use Durance::Schema;
use mojotodo::DB;
use mojotodo::Model::AuthChallenge;
use mojotodo::Model::User;
use mojotodo::Model::TodoList;
use mojotodo::Model::Task;
use mojotodo::Model::ListShare;

our $VERSION = '0.01';

sub _app_secret ($config) {
    return $config->{secrets}[0] if ref($config->{secrets}) eq 'ARRAY' && @{ $config->{secrets} };
    return $ENV{MOJO_SECRET} if $ENV{MOJO_SECRET};
    return 'mojotodo-dev-secret-change-me';
}

sub _auth_config ($config) {
    return $config->{auth} // {};
}

sub _normalize_email ($email) {
    $email //= '';
    $email = trim($email);
    return lc $email;
}

sub _random_hex ($bytes) {
    my $out = '';
    open my $fh, '<:raw', '/dev/urandom' or die "Unable to open /dev/urandom: $!";
    my $read = read($fh, $out, $bytes);
    close $fh;
    die 'Unable to read random bytes' unless defined $read && $read == $bytes;
    return unpack('H*', $out);
}

sub _generate_code ($digits) {
    my $bytes = '';
    open my $fh, '<:raw', '/dev/urandom' or die "Unable to open /dev/urandom: $!";
    my $read = read($fh, $bytes, 4);
    close $fh;
    die 'Unable to read random bytes' unless defined $read && $read == 4;

    my $num = unpack('N', $bytes);
    my $max = 10**$digits;
    my $val = $num % $max;
    return sprintf("%0${digits}d", $val);
}

sub _code_hash ($salt, $code, $pepper) {
    return sha256_hex(join(':', $salt, $code, $pepper));
}

sub _json_error ($c, $status, $message) {
    return $c->render(status => $status, json => { error => $message });
}

sub _current_user_id ($c) {
    return $c->session->{user_id};
}

sub _user_has_list_access ($user_id, $list_id) {
    return 0 unless $user_id && $list_id;

    my $list = mojotodo::Model::TodoList->find($list_id);
    return 1 if $list && $list->owner_user_id == $user_id;

    my $share = mojotodo::Model::ListShare->where({
        todo_list_id => $list_id,
        user_id     => $user_id,
    })->first;
    return 1 if $share;

    return 0;
}

sub startup ($self) {
    # Load configuration
    my $config = $self->plugin('Config' => { default => {} });

    my $db_dsn = $config->{database}{dsn} // 'dbi:SQLite:dbname=app.db';
    $mojotodo::DB::gDSN = $db_dsn;

    my ($dsn_ok, $dsn_error) = mojotodo::DB->isDSNValid;
    die "Database DSN is invalid: $dsn_error" unless $dsn_ok;

    my $secret = _app_secret($config);
    $self->secrets([$secret]);

    my $schema = Durance::Schema->new(dbh => mojotodo::DB->new->dbh);
    my $user_model = mojotodo::Model::User->new(db => mojotodo::DB->new);
    my $challenge_model = mojotodo::Model::AuthChallenge->new(db => mojotodo::DB->new);
    my $todo_list_model = mojotodo::Model::TodoList->new(db => mojotodo::DB->new);
    my $task_model = mojotodo::Model::Task->new(db => mojotodo::DB->new);
    if ($self->mode eq 'development') {
        $schema->sync_table($user_model);
        $schema->sync_table($challenge_model);
        $schema->sync_table($todo_list_model);
        $schema->sync_table($task_model);
    } else {
        $schema->ensure_schema_valid($user_model);
        $schema->ensure_schema_valid($challenge_model);
        $schema->ensure_schema_valid($todo_list_model);
        $schema->ensure_schema_valid($task_model);
    }

    # Documentation browser under "/perldoc"
    if ($self->mode eq 'development') {
        eval { $self->plugin('PODRenderer') };
    }

    # Router
    my $r = $self->routes;

    # Basic route
    $r->get('/')->to(cb => sub ($c) {
        $c->render(json => {
            app     => 'MojoTodo',
            version => $VERSION,
            status  => 'ok'
        });
    });

    $r->post('/api/auth/request-code')->to(cb => sub ($c) {
        my $payload = $c->req->json // {};
        my $email = _normalize_email($payload->{email});

        return _json_error($c, 400, 'Email is required') if !$email;

        my $auth = _auth_config($config);
        my $ttl = $auth->{code_ttl_seconds} // 600;
        my $cooldown = $auth->{resend_cooldown} // 30;
        my $digits = $auth->{code_digits} // 6;
        my $pepper = $ENV{MOJOTODO_CODE_PEPPER} // ($auth->{code_pepper} // 'dev-pepper');

        my @recent = mojotodo::Model::AuthChallenge->where({ email => $email })
            ->order('id DESC')->limit(10)->all;
        my $now = time;
        my ($active) = grep {
            (!defined $_->used_epoch || $_->used_epoch == 0)
                && $_->expires_epoch
                && $_->expires_epoch >= $now
        } @recent;

        if ($active && $active->created_epoch) {
            my $elapsed = $now - $active->created_epoch;
            if ($elapsed < $cooldown) {
                return _json_error($c, 429, 'Please wait before requesting another code');
            }
        }

        my $code = _generate_code($digits);
        my $salt = _random_hex(8);
        my $hash = _code_hash($salt, $code, $pepper);
        my $expires = $now + $ttl;

        my $user = mojotodo::Model::User->where({ email => $email })->first;

        my $challenge = mojotodo::Model::AuthChallenge->create({
            user_id       => $user ? $user->id : undef,
            email         => $email,
            code_hash     => $hash,
            code_salt     => $salt,
            created_epoch => $now,
            expires_epoch => $expires,
            used_epoch    => 0,
            attempt_count => 0,
        });

        $self->log->info("Auth code for $email is $code (challenge=" . $challenge->id . ' )');

        my %resp = ( status => 'code_sent' );
        if ($self->mode eq 'development' && ($auth->{dev_return_code} // 0)) {
            $resp{code} = $code;
        }

        return $c->render(status => 202, json => \%resp);
    });

    $r->post('/api/auth/verify-code')->to(cb => sub ($c) {
        my $payload = $c->req->json // {};
        my $email = _normalize_email($payload->{email});
        my $code = trim($payload->{code} // '');

        return _json_error($c, 400, 'Email is required') if !$email;
        return _json_error($c, 400, 'Code is required') if !$code;

        my $auth = _auth_config($config);
        my $max_attempts = $auth->{max_verify_attempts} // 5;
        my $pepper = $ENV{MOJOTODO_CODE_PEPPER} // ($auth->{code_pepper} // 'dev-pepper');
        my $now = time;

        my @challenges = mojotodo::Model::AuthChallenge->where({ email => $email })
            ->order('id DESC')->limit(20)->all;
        my ($challenge) = grep {
            (!defined $_->used_epoch || $_->used_epoch == 0)
                && $_->expires_epoch
                && $_->expires_epoch >= $now
        } @challenges;

        return _json_error($c, 401, 'Invalid code') if !$challenge;
        return _json_error($c, 401, 'Invalid code') if ($challenge->attempt_count // 0) >= $max_attempts;

        my $candidate = _code_hash($challenge->code_salt, $code, $pepper);
        if (!secure_compare($candidate, $challenge->code_hash)) {
            my $attempts = ($challenge->attempt_count // 0) + 1;
            $challenge->attempt_count($attempts);
            if ($attempts >= $max_attempts) {
                $challenge->used_epoch($now);
            }
            $challenge->update;
            return _json_error($c, 401, 'Invalid code');
        }

        my $user = mojotodo::Model::User->where({ email => $email })->first;
        if (!$user) {
            $user = mojotodo::Model::User->create({
                email     => $email,
                is_active => 1,
            });
        }

        $challenge->user_id($user->id);
        $challenge->used_epoch($now);
        $challenge->update;

        $c->session(expires => 1);
        $c->session(user_id => $user->id);
        $c->session(email => $user->email);
        $c->session(expires => ($config->{session}{expires} // 86400));

        return $c->render(status => 200, json => {
            status => 'authenticated',
            user   => {
                id    => $user->id,
                email => $user->email,
            },
        });
    });

    $r->post('/api/logout')->to(cb => sub ($c) {
        $c->session(expires => 1);
        return $c->render(status => 200, json => { status => 'logged_out' });
    });

    $r->get('/api/lists/:list_id/tasks')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list_id = $c->param('list_id');
        my $hide_assigned_out = $c->param('hide_assigned_out') // 0;

        my $list = mojotodo::Model::TodoList->find($list_id);
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list_id);

        my $opts = {};
        $opts->{hide_assigned_out} = 1 if $hide_assigned_out eq '1';

        my $tasks = mojotodo::Model::Task->list_view($list_id, $opts);

        return $c->render(status => 200, json => { tasks => $tasks });
    });

    $r->get('/api/lists')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my @owned = mojotodo::Model::TodoList->where({ owner_user_id => $user_id })
            ->order('id DESC')->all;

        my @shared_ids = map { $_->todo_list_id }
            mojotodo::Model::ListShare->where({ user_id => $user_id })->all;

        my @shared;
        for my $list_id (@shared_ids) {
            my $list = mojotodo::Model::TodoList->find($list_id);
            push @shared, $list if $list;
        }

        my @all = (@owned, @shared);
        my @resp = map { $_->to_hash } @all;

        return $c->render(status => 200, json => { lists => \@resp });
    });

    $r->get('/api/lists/:id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list = mojotodo::Model::TodoList->find($c->param('id'));
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list->id);

        return $c->render(status => 200, json => { list => $list->to_hash });
    });

    $r->post('/api/lists')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $payload = $c->req->json // {};
        my $title = trim($payload->{title} // '');

        return _json_error($c, 400, 'Title is required') unless $title;

        my $list = mojotodo::Model::TodoList->create({
            owner_user_id => $user_id,
            title         => $title,
            archived      => 0,
        });

        return $c->render(status => 201, json => { list => $list->to_hash });
    });

    $r->patch('/api/lists/:id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list = mojotodo::Model::TodoList->find($c->param('id'));
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless $list->owner_user_id == $user_id;

        my $payload = $c->req->json // {};
        if (defined $payload->{title}) {
            $list->title(trim($payload->{title}));
        }
        if (defined $payload->{archived}) {
            $list->archived($payload->{archived} ? 1 : 0);
        }
        $list->update;

        return $c->render(status => 200, json => { list => $list->to_hash });
    });

    $r->delete('/api/lists/:id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list = mojotodo::Model::TodoList->find($c->param('id'));
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless $list->owner_user_id == $user_id;

        $list->delete;

        return $c->render(status => 200, json => { status => 'deleted' });
    });
}

1;

=head1 NAME

mojotodo - Lightweight collaborative todo list application

=head1 SYNOPSIS

    # Start the application
    morbo script/mojotodo
    
    # Or in production
    hypnotoad script/mojotodo

=head1 DESCRIPTION

MojoTodo is a lightweight single-page web application for collaborative todo list management.

=head1 FEATURES

=over 4

=item * Multi-user support

=item * Multiple todo lists per user

=item * Task sharing between users

=item * Deadline tracking with visual indicators

=item * RESTful API for mobile clients

=back

=head1 AUTHOR

Your Name

=head1 LICENSE

This software is licensed under the same terms as Perl itself.

=cut
