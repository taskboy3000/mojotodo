package mojotodo;
use Mojo::Base 'Mojolicious', -signatures;

use Digest::SHA qw(sha256_hex);
use Mojo::Util qw(secure_compare trim);
use Mojo::JSON qw(encode_json);

use Durance::Schema;

sub _html_escape ($text) {
    return '' unless defined $text;
    my $out = $text;
    $out =~ s/&/&amp;/g;
    $out =~ s/</&lt;/g;
    $out =~ s/>/&gt;/g;
    $out =~ s/"/&quot;/g;
    $out =~ s/'/&#39;/g;
    return $out;
}
use mojotodo::DB;
use mojotodo::Model::AuthChallenge;
use mojotodo::Model::User;
use mojotodo::Model::TodoList;
use mojotodo::Model::Task;
use mojotodo::Model::ListShare;
use mojotodo::Model::TaskAssignment;
use mojotodo::Model::Notification;

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

sub _sanitize ($text) {
    return '' unless defined $text;
    my $copy = $text;
    $copy =~ s/&/&amp;/g;
    $copy =~ s/</&lt;/g;
    $copy =~ s/>/&gt;/g;
    $copy =~ s/"/&quot;/g;
    $copy =~ s/'/&#39;/g;
    return $copy;
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

    my $conf_file = $self->home->child('mojotodo.conf')->to_string;
    $self->log->info("Configuration file: $conf_file");
    $self->log->info('Loaded config: ' . encode_json($config));

    if ($ENV{MOJOTODO_FAKE_AUTH}) {
        warn "WARNING: MOJOTODO_FAKE_AUTH is enabled - authentication bypass is active!\n";
        warn "DO NOT use this in production!\n";
    }

    my $auth = _auth_config($config);
    if ($auth->{dev_return_code}) {
        if ($self->mode eq 'production') {
            die "FATAL: dev_return_code is enabled in production mode. This leaks OTP codes. Set auth.dev_return_code to false or use development mode.";
        }
        warn "WARNING: dev_return_code is enabled - OTP codes will be returned in API responses.\n";
        warn "DO NOT use this in production!\n";
    }

    my $db_dsn = $config->{database}{dsn} // 'dbi:SQLite:dbname=app.db';
    $mojotodo::DB::gDSN = $db_dsn;

    my ($dsn_ok, $dsn_error) = mojotodo::DB->isDSNValid;
    die "Database DSN is invalid: $dsn_error" unless $dsn_ok;

    my $secret = _app_secret($config);
    $self->secrets([$secret]);

    my $max_json_size = 64 * 1024;
    $self->hook(before_dispatch => sub ($c) {
        my $len = $c->req->headers->content_length // 0;
        if ($len > $max_json_size) {
            return $c->render(
                status => 413,
                json   => { error => 'Payload too large' }
            );
        }
    });

    # CSRF protection for state-changing requests (skip in development for easier testing)
    $self->hook(before_dispatch => sub ($c) {
        return if $self->mode eq 'development';
        return if $c->req->method eq 'GET';
        return if $c->req->method eq 'HEAD';
        
        # Skip CSRF for auth endpoints (login flow)
        my $path = $c->req->url->path;
        return if $path =~ qr{^/api/auth/};
        
        # Skip CSRF for logout
        return if $path eq '/api/logout';
        
        # Generate CSRF token if not present
        unless ($c->session('csrf_token')) {
            $c->session(csrf_token => _random_hex(16));
        }
        
        my $header_token = $c->req->headers->header('X-CSRF-Token');
        my $session_token = $c->session('csrf_token');
        
        if ($header_token && $session_token) {
            return if secure_compare($header_token, $session_token);
        }
        
        return $c->render(status => 403, json => { error => 'Invalid CSRF token' });
    });

    my $schema = Durance::Schema->new(dbh => mojotodo::DB->new->dbh);
    my $user_model = mojotodo::Model::User->new(db => mojotodo::DB->new);
    my $challenge_model = mojotodo::Model::AuthChallenge->new(db => mojotodo::DB->new);
    my $todo_list_model = mojotodo::Model::TodoList->new(db => mojotodo::DB->new);
    my $task_model = mojotodo::Model::Task->new(db => mojotodo::DB->new);
    my $list_share_model = mojotodo::Model::ListShare->new(db => mojotodo::DB->new);
    my $task_assignment_model = mojotodo::Model::TaskAssignment->new(db => mojotodo::DB->new);
    my $notification_model = mojotodo::Model::Notification->new(db => mojotodo::DB->new);
    if ($self->mode eq 'development') {
        $schema->sync_table($user_model);
        $schema->sync_table($challenge_model);
        $schema->sync_table($todo_list_model);
        $schema->sync_table($task_model);
        $schema->sync_table($list_share_model);
        $schema->sync_table($task_assignment_model);
        $schema->sync_table($notification_model);
    } else {
        $schema->ensure_schema_valid($user_model);
        $schema->ensure_schema_valid($challenge_model);
        $schema->ensure_schema_valid($todo_list_model);
        $schema->ensure_schema_valid($task_model);
        $schema->ensure_schema_valid($list_share_model);
        $schema->ensure_schema_valid($task_assignment_model);
        $schema->ensure_schema_valid($notification_model);
    }

    # Initialize mailer if configured
    eval {
        require mojotodo::Mailer;
        my $mail_config = $config->{mail};
        if ($mail_config) {
            mojotodo::Mailer::configure($mail_config);
            $self->helper(_mailer => sub { return 'mojotodo::Mailer'; });
        }
    };

    # Documentation browser under "/perldoc"
    if ($self->mode eq 'development') {
        eval { $self->plugin('PODRenderer') };
    }

    # Rate limiting storage (persists across requests within same process)
    our %RATE_LIMIT_STORAGE;

    # Rate limiting middleware for state-changing endpoints
    my $rate_limit_config = {
        limits => [
            {
                path   => qr{^/api/auth/request-code$},
                method => 'POST',
                limit  => 5,
                window => 900,  # 5 requests per 15 minutes
            },
            {
                path   => qr{^/api/auth/verify-code$},
                method => 'POST',
                limit  => 20,
                window => 900,  # 20 requests per 15 minutes
            },
            {
                path   => qr{^/api/account/request-phone-code$},
                method => 'POST',
                limit  => 5,
                window => 900,  # 5 requests per 15 minutes
            },
            {
                path   => qr{^/api/lists/(?!\w+/tasks)},
                method => qr{^(POST|PATCH|DELETE)$},
                limit  => 10,
                window => 60,  # 10 requests per minute
            },
            {
                path   => qr{^/api/lists/\w+/tasks$},
                method => 'POST',
                limit  => 30,
                window => 60,  # 30 task creates per minute
            },
            {
                path   => qr{^/api/lists/\w+/tasks/\w+$},
                method => qr{^(PATCH|DELETE)$},
                limit  => 20,
                window => 60,  # 20 task updates/deletes per minute
            },
            {
                path   => qr{^/api/lists/\w+/share$},
                method => 'POST',
                limit  => 5,
                window => 60,  # 5 shares per minute
            },
            {
                path   => qr{^/api/tasks/\w+/assign$},
                method => 'POST',
                limit  => 10,
                window => 60,  # 10 assignments per minute
            }
        ]
    };

    $self->hook(before_dispatch => sub {
        my $c = shift;
        my $path = $c->req->url->path;
        my $method = $c->req->method;

        # Check each rate limit rule
        for my $rule (@{$rate_limit_config->{limits}}) {
            next unless $path =~ $rule->{path};
            next unless $method =~ $rule->{method};

            my $user_id = $c->session->{user_id};

            # For auth endpoints, extract email from request body if no session
            if (!$user_id && ($path eq '/api/auth/request-code' || $path eq '/api/auth/verify-code')) {
                my $payload = $c->req->json // {};
                $user_id = $payload->{email} // 'anonymous';
            }

            $user_id //= 'anonymous';
            my $ip = $c->tx->remote_address // 'unknown';
            my $key = "$method:$path:$user_id:$ip";
            my $now = time;
            my $window_start = $now - $rule->{window};

            # Get or initialize request timestamps from persistent storage
            my $timestamps = $RATE_LIMIT_STORAGE{$key} // [];
            @$timestamps = grep { $_ > $window_start } @$timestamps;

            if (@$timestamps >= $rule->{limit}) {
                return $c->render(
                    status => 429,
                    json   => { error => 'Rate limit exceeded. Try again later.' }
                );
            }

            push @$timestamps, $now;
            $RATE_LIMIT_STORAGE{$key} = $timestamps;
            last;
        }
    });

    # Router
    my $r = $self->routes;

    # Basic route
    $r->get('/')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        if ($user_id) {
            $c->redirect_to('/lists');
        } else {
            $c->redirect_to('/login');
        }
    });

    $r->get('/login')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        if ($user_id) {
            $c->redirect_to('/lists');
            return;
        }
        $c->render(template => 'pages/login');
    });

    $r->get('/logout')->to(cb => sub ($c) {
        $c->session(expires => 1);
        $c->redirect_to('/login');
    });

    $r->get('/lists')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        if (!$user_id) {
            $c->redirect_to('/login');
            return;
        }
        $c->render(template => 'pages/lists');
    });

    $r->post('/api/auth/request-code')->to(cb => sub ($c) {
        my $payload = $c->req->json // {};
        my $email = _normalize_email($payload->{email});
        my $code_type = $payload->{code_type} // 'email';

        if ($code_type eq 'sms') {
            return _json_error($c, 400, 'Email is required') if !$email;

            my $user = mojotodo::Model::User->where({ email => $email })->first;
            if (!$user || !$user->phone || !$user->phone_verified) {
                return _json_error($c, 400, 'Unable to send code via SMS');
            }

            my $phone = $user->phone;
            my $auth = _auth_config($config);
            my $ttl = $auth->{code_ttl_seconds} // 600;
            my $cooldown = $auth->{resend_cooldown} // 30;
            my $digits = $auth->{code_digits} // 6;
            my $pepper = $ENV{MOJOTODO_CODE_PEPPER} // ($auth->{code_pepper} // 'dev-pepper');

            my @recent = mojotodo::Model::AuthChallenge->where({ phone => $phone, code_type => 'sms' })
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

            mojotodo::Model::AuthChallenge->create({
                user_id       => $user->id,
                phone         => $phone,
                code_type     => 'sms',
                code_hash     => $hash,
                code_salt     => $salt,
                created_epoch => $now,
                expires_epoch => $expires,
                used_epoch    => 0,
                attempt_count => 0,
            });

            my $mailer_enabled = eval { mojotodo::Mailer::is_enabled(); };
            if ($mailer_enabled) {
                eval { mojotodo::Mailer::send_sms($phone, "Your MojoTodo verification code is: $code"); };
                if ($@) {
                    $self->log->error("Failed to send SMS: $@");
                    return _json_error($c, 500, 'Failed to send SMS');
                }
            }

            $self->log->info("Auth SMS code sent for $email (phone ending in " . substr($phone, -4) . ")");

            my %resp = ( status => 'code_sent' );
            if ($self->mode eq 'development' && ($auth->{dev_return_code} // 0)) {
                $resp{code} = $code;
            }

            return $c->render(status => 202, json => \%resp);
        }

        return _json_error($c, 400, 'Email is required') if !$email;

        my $auth = _auth_config($config);
        my $ttl = $auth->{code_ttl_seconds} // 600;
        my $cooldown = $auth->{resend_cooldown} // 30;
        my $digits = $auth->{code_digits} // 6;
        my $pepper = $ENV{MOJOTODO_CODE_PEPPER} // ($auth->{code_pepper} // 'dev-pepper');

        my @recent = mojotodo::Model::AuthChallenge->where({ email => $email, code_type => 'email' })
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
            code_type     => 'email',
            code_hash     => $hash,
            code_salt     => $salt,
            created_epoch => $now,
            expires_epoch => $expires,
            used_epoch    => 0,
            attempt_count => 0,
        });

        my $mailer_enabled = eval { mojotodo::Mailer::is_enabled(); };
        if ($mailer_enabled) {
            eval {
                mojotodo::Mailer::send_email(
                    $email,
                    'Your MojoTodo Verification Code',
                    "Your verification code is: $code\n\nThis code expires in 10 minutes."
                );
            };
            if ($@) {
                $self->log->error("Failed to send email: $@");
            }
        } else {
            $self->log->info("Mailer is not enabled");
        }

        $self->log->info("Auth code for $email (challenge=" . $challenge->id . ')');

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
        my $code_type = $payload->{code_type} // 'email';

        return _json_error($c, 400, 'Email is required') if !$email;
        return _json_error($c, 400, 'Code is required') if !$code;

        if ($ENV{MOJOTODO_FAKE_AUTH}) {
            my $user = mojotodo::Model::User->where({ email => $email })->first;
            if (!$user) {
                $user = mojotodo::Model::User->create({
                    email     => $email,
                    is_active => 1,
                });
                mojotodo::Model::TodoList->create_default_list($user->id);
            }
            $c->session(user_id => $user->id);
            $c->session(email => $user->email);
            return $c->render(status => 200, json => {
                status => 'authenticated',
                user   => {
                    id    => $user->id,
                    email => $user->email,
                },
            });
        }

        my $auth = _auth_config($config);
        my $max_attempts = $auth->{max_verify_attempts} // 5;
        my $pepper = $ENV{MOJOTODO_CODE_PEPPER} // ($auth->{code_pepper} // 'dev-pepper');
        my $now = time;

        my @challenges = mojotodo::Model::AuthChallenge->where({ email => $email, code_type => $code_type })
            ->order('id DESC')->limit(20)->all;
        $self->log->info("Verify: found " . scalar(@challenges) . " challenges for $email, code_type=$code_type");

        my ($challenge) = grep {
            (!defined $_->used_epoch || $_->used_epoch == 0)
                && $_->expires_epoch
                && $_->expires_epoch >= $now
        } @challenges;

        if (!$challenge) {
            $self->log->info("Verify: no valid challenge found, now=$now");
            for my $c (@challenges) {
                $self->log->info("Verify: challenge id=" . $c->id . ", used=" . ($c->used_epoch // 0) . ", expires=" . $c->expires_epoch);
            }
        }
        return _json_error($c, 401, 'Invalid code') if !$challenge;
        return _json_error($c, 401, 'Invalid code') if ($challenge->attempt_count // 0) >= $max_attempts;

        my $candidate = _code_hash($challenge->code_salt, $code, $pepper);
        $self->log->info("Verify: email=$email, code=$code, salt=" . $challenge->code_salt);
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
            mojotodo::Model::TodoList->create_default_list($user->id);
        }

        $challenge->user_id($user->id);
        $challenge->used_epoch($now);
        $challenge->update;

        $c->session(user_id => $user->id);
        $c->session(email => $user->email);

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

    $r->delete('/api/account')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $success = mojotodo::Model::User->delete_account($user_id);
        if (!$success) {
            return _json_error($c, 500, 'Failed to delete account');
        }

        $c->session(expires => 1);
        return $c->render(status => 200, json => { status => 'account_deleted' });
    });

    $r->get('/api/account')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $user = mojotodo::Model::User->find($user_id);
        return _json_error($c, 404, 'User not found') unless $user;

        my %resp = (
            id                       => $user->id,
            email                    => $user->email,
            phone_verified           => $user->phone_verified ? 1 : 0,
            preferred_contact_method => $user->preferred_contact_method // 'email',
        );

        if ($user->phone) {
            $resp{phone} = $user->mask_phone // '';
        }

        return $c->render(status => 200, json => \%resp);
    });

    $r->patch('/api/account')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $user = mojotodo::Model::User->find($user_id);
        return _json_error($c, 404, 'User not found') unless $user;

        my $payload = $c->req->json // {};
        my $phone = $payload->{phone};
        my $preferred = $payload->{preferred_contact_method};

        if (defined $phone && $phone ne '') {
            my $normalized = mojotodo::Model::User->normalize_phone($phone);
            return _json_error($c, 400, 'Invalid phone number') unless $normalized;
            $user->phone($normalized);
            $user->phone_verified(0);
        }

        if (defined $preferred && ($preferred eq 'email' || $preferred eq 'sms')) {
            if ($preferred eq 'sms' && !$user->phone_verified) {
                return _json_error($c, 400, 'Must verify phone number before selecting SMS');
            }
            $user->preferred_contact_method($preferred);
        }

        $user->update;

        my %resp = (
            id                       => $user->id,
            email                    => $user->email,
            phone_verified           => $user->phone_verified ? 1 : 0,
            preferred_contact_method => $user->preferred_contact_method // 'email',
        );

        if ($user->phone) {
            $resp{phone} = $user->mask_phone // '';
        }

        return $c->render(status => 200, json => \%resp);
    });

    $r->post('/api/account/request-phone-code')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $user = mojotodo::Model::User->find($user_id);
        return _json_error($c, 404, 'User not found') unless $user;

        my $phone = $user->phone;
        return _json_error($c, 400, 'No phone number on file') unless $phone;

        my $auth = _auth_config($config);
        my $ttl = $auth->{code_ttl_seconds} // 600;
        my $cooldown = $auth->{resend_cooldown} // 30;
        my $digits = $auth->{code_digits} // 6;
        my $pepper = $ENV{MOJOTODO_CODE_PEPPER} // ($auth->{code_pepper} // 'dev-pepper');

        my @recent = mojotodo::Model::AuthChallenge->where({ phone => $phone, code_type => 'sms' })
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

        mojotodo::Model::AuthChallenge->create({
            user_id       => $user->id,
            phone         => $phone,
            code_type     => 'sms',
            code_hash     => $hash,
            code_salt     => $salt,
            created_epoch => $now,
            expires_epoch => $expires,
            used_epoch    => 0,
            attempt_count => 0,
        });

        my $mailer_enabled = eval { mojotodo::Mailer::is_enabled(); };
        if ($mailer_enabled) {
            eval { mojotodo::Mailer::send_sms($phone, "Your MojoTodo verification code is: $code"); };
            if ($@) {
                $self->log->error("Failed to send SMS: $@");
                return _json_error($c, 500, 'Failed to send SMS');
            }
        }

        $self->log->info("Phone verification code sent for user $user_id");

        return $c->render(status => 202, json => { status => 'code_sent' });
    });

    $r->post('/api/account/verify-phone')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $user = mojotodo::Model::User->find($user_id);
        return _json_error($c, 404, 'User not found') unless $user;

        my $phone = $user->phone;
        return _json_error($c, 400, 'No phone number on file') unless $phone;

        my $payload = $c->req->json // {};
        my $code = trim($payload->{code} // '');
        return _json_error($c, 400, 'Code is required') if !$code;

        my $auth = _auth_config($config);
        my $pepper = $ENV{MOJOTODO_CODE_PEPPER} // ($auth->{code_pepper} // 'dev-pepper');

        my @recent = mojotodo::Model::AuthChallenge->where({ phone => $phone, code_type => 'sms' })
            ->order('id DESC')->limit(5)->all;
        my $now = time;
        my ($challenge) = grep {
            $_->expires_epoch >= $now
                && (!$_->used_epoch || $_->used_epoch == 0)
        } @recent;

        return _json_error($c, 400, 'Invalid or expired code') unless $challenge;

        my $expected_hash = _code_hash($challenge->code_salt, $code, $pepper);
        if ($expected_hash ne $challenge->code_hash) {
            $challenge->attempt_count($challenge->attempt_count + 1);
            $challenge->update;
            return _json_error($c, 400, 'Invalid code');
        }

        $challenge->used_epoch($now);
        $challenge->update;
        $user->phone_verified(1);
        $user->update;

        return $c->render(status => 200, json => { status => 'phone_verified' });
    });

    $r->get('/api/lists/:list_id/tasks')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list_id = $c->param('list_id');
        my $hide_assigned_out = $c->param('hide_assigned_out') // 0;
        my $page = $c->param('page') // 1;
        my $limit = $c->param('limit') // 20;
        $limit = 100 if $limit > 100;
        $limit = 1 if $limit < 1;
        $page = 1 if $page < 1;
        my $offset = ($page - 1) * $limit;

        my $list = mojotodo::Model::TodoList->find($list_id);
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list_id);

        my $opts = {
            hide_assigned_out => ($hide_assigned_out eq '1') ? 1 : 0,
            limit             => $limit,
            offset           => $offset,
            include_count     => 1,
        };

        my $result = mojotodo::Model::Task->list_view($list_id, $opts);

        return $c->render(status => 200, json => {
            tasks => $result->{rows},
            page  => $page,
            limit => $limit,
            total => $result->{total},
        });
    });

    $r->post('/api/lists/:list_id/tasks/reorder')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list_id = $c->param('list_id');
        my $list = mojotodo::Model::TodoList->find($list_id);
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list_id);

        my $payload = $c->req->json // {};
        my $task_ids = $payload->{task_ids} // [];

        return _json_error($c, 400, 'task_ids is required') unless ref $task_ids eq 'ARRAY';

        my $dbh = mojotodo::DB->new->dbh;
        $dbh->begin_work;

        eval {
            my $pos = 0;
            for my $task_id (@$task_ids) {
                my $task = mojotodo::Model::Task->find($task_id);
                next unless $task;
                next unless $task->todo_list_id == $list_id;
                $task->position($pos++);
                $task->update;
            }
            $dbh->commit;
        };

        if ($@) {
            $dbh->rollback;
            return _json_error($c, 500, 'Failed to reorder tasks');
        }

        return $c->render(status => 200, json => { status => 'reordered' });
    });

    $r->post('/api/lists/:list_id/tasks')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list_id = $c->param('list_id');
        my $list = mojotodo::Model::TodoList->find($list_id);
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list_id);

        my $payload = $c->req->json // {};
        my $title = trim($payload->{title} // '');

        return _json_error($c, 400, 'Title is required') unless $title;

        my $task = mojotodo::Model::Task->create({
            todo_list_id       => $list_id,
            title            => _sanitize($title),
            description      => _sanitize($payload->{description} // ''),
            status           => $payload->{status} // 'open',
            due_at           => $payload->{due_at},
            created_by_user_id => $user_id,
        });

        return $c->render(status => 201, json => { task => $task->to_hash });
    });

    $r->get('/api/lists/:list_id/tasks/:id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list_id = $c->param('list_id');
        my $list = mojotodo::Model::TodoList->find($list_id);
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list_id);

        my $task = mojotodo::Model::Task->find($c->param('id'));
        return _json_error($c, 404, 'Task not found') unless $task;
        return _json_error($c, 404, 'Task not found') unless $task->todo_list_id == $list_id;

        return $c->render(status => 200, json => { task => $task->to_hash });
    });

    $r->patch('/api/lists/:list_id/tasks/:id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list_id = $c->param('list_id');
        my $list = mojotodo::Model::TodoList->find($list_id);
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list_id);

        my $task = mojotodo::Model::Task->find($c->param('id'));
        return _json_error($c, 404, 'Task not found') unless $task;
        return _json_error($c, 404, 'Task not found') unless $task->todo_list_id == $list_id;

        my $payload = $c->req->json // {};
        if (defined $payload->{title}) {
            $task->title(_sanitize(trim($payload->{title})));
        }
        if (defined $payload->{description}) {
            $task->description(_sanitize($payload->{description}));
        }
        if (defined $payload->{status}) {
            $task->status($payload->{status});
        }
        if (defined $payload->{due_at}) {
            $task->due_at($payload->{due_at});
        }
        if (defined $payload->{completed_at}) {
            $task->completed_at($payload->{completed_at});
        }
        $task->update;

        return $c->render(status => 200, json => { task => $task->to_hash });
    });

    $r->delete('/api/lists/:list_id/tasks/:id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list_id = $c->param('list_id');
        my $list = mojotodo::Model::TodoList->find($list_id);
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 404, 'List not found') unless _user_has_list_access($user_id, $list_id);

        my $task = mojotodo::Model::Task->find($c->param('id'));
        return _json_error($c, 404, 'Task not found') unless $task;
        return _json_error($c, 404, 'Task not found') unless $task->todo_list_id == $list_id;

        $task->delete;

        return $c->render(status => 200, json => { status => 'deleted' });
    });

    $r->get('/api/lists')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $page = $c->param('page') // 1;
        my $limit = $c->param('limit') // 20;
        $limit = 100 if $limit > 100;
        $limit = 1 if $limit < 1;
        $page = 1 if $page < 1;
        my $offset = ($page - 1) * $limit;

        my @owned = mojotodo::Model::TodoList->where({ owner_user_id => $user_id })
            ->order('position ASC, id DESC')->all;
        my @shares = mojotodo::Model::ListShare->where({ user_id => $user_id })->all;
        my @shared = map { $_->todo_list } @shares;
        my @all = (@owned, @shared);

        if ($c->param('default')) {
            @all = grep { $_->title eq 'My Tasks' } @all;
            $limit = 1;
            $offset = 0;
        }

        my $total = scalar @all;
        my @paginated = splice(@all, $offset, $limit);
        my @resp = map { $_->to_hash } @paginated;

        return $c->render(status => 200, json => {
            lists   => \@resp,
            page    => $page,
            limit   => $limit,
            total   => $total,
        });
    });

    $r->post('/api/lists/reorder')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $payload = $c->req->json // {};
        my $list_ids = $payload->{list_ids} // [];

        return _json_error($c, 400, 'list_ids is required') unless ref $list_ids eq 'ARRAY';

        my $dbh = mojotodo::DB->new->dbh;
        $dbh->begin_work;

        eval {
            my $pos = 0;
            for my $list_id (@$list_ids) {
                my $list = mojotodo::Model::TodoList->find($list_id);
                next unless $list;
                next unless _user_has_list_access($user_id, $list_id);
                $list->position($pos++);
                $list->update;
            }
            $dbh->commit;
        };

        if ($@) {
            $dbh->rollback;
            return _json_error($c, 500, 'Failed to reorder lists');
        }

        return $c->render(status => 200, json => { status => 'reordered' });
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
            title         => _sanitize($title),
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
            $list->title(_sanitize(trim($payload->{title})));
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

    # POST /api/lists/:id/share - Share a list with a user
    $r->post('/api/lists/:id/share')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list = mojotodo::Model::TodoList->find($c->param('id'));
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 403, 'Forbidden') unless $list->owner_user_id == $user_id;

        my $payload = $c->req->json // {};
        my $email = _normalize_email($payload->{email});
        return _json_error($c, 400, 'Email is required') unless $email;

        my $target_user = mojotodo::Model::User->where({ email => $email })->first;
        return _json_error($c, 404, 'User not found') unless $target_user;
        return _json_error($c, 400, 'Cannot share with yourself') if $target_user->id == $user_id;

        my $existing = mojotodo::Model::ListShare->where({
            todo_list_id => $list->id,
            user_id      => $target_user->id,
        })->first;
        return _json_error($c, 400, 'List already shared with this user') if $existing;

        my $share = mojotodo::Model::ListShare->create({
            todo_list_id       => $list->id,
            user_id            => $target_user->id,
            created_by_user_id => $user_id,
        });

        return $c->render(status => 201, json => { share => $share->to_hash });
    });

    # GET /api/lists/:id/share - Get collaborators for a list
    $r->get('/api/lists/:id/share')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list = mojotodo::Model::TodoList->find($c->param('id'));
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 403, 'Forbidden') unless _user_has_list_access($user_id, $list->id);

        my @shares = mojotodo::Model::ListShare->where({ todo_list_id => $list->id })->all;
        my @collaborators = map {
            {
                id         => $_->id,
                user_id    => $_->user_id,
                email      => $_->user->email,
                created_at => $_->created_at,
            }
        } @shares;

        return $c->render(status => 200, json => { collaborators => \@collaborators });
    });

    # DELETE /api/lists/:id/share/:share_id - Revoke sharing
    $r->delete('/api/lists/:id/share/:share_id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $list = mojotodo::Model::TodoList->find($c->param('id'));
        return _json_error($c, 404, 'List not found') unless $list;
        return _json_error($c, 403, 'Forbidden') unless $list->owner_user_id == $user_id;

        my $share = mojotodo::Model::ListShare->find($c->param('share_id'));
        return _json_error($c, 404, 'Share not found') unless $share;
        return _json_error($c, 403, 'Share does not belong to this list') unless $share->todo_list_id == $list->id;

        $share->delete;

        return $c->render(status => 200, json => { status => 'deleted' });
    });

    # POST /api/tasks/:id/assign - Assign a task to another list
    $r->post('/api/tasks/:id/assign')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $task = mojotodo::Model::Task->find($c->param('id'));
        return _json_error($c, 404, 'Task not found') unless $task;

        my $source_list = mojotodo::Model::TodoList->find($task->todo_list_id);
        return _json_error($c, 403, 'Forbidden') unless _user_has_list_access($user_id, $source_list->id);

        my $payload = $c->req->json // {};
        my $target_list_id = $payload->{target_list_id};
        my $assigned_to_email = _normalize_email($payload->{assigned_to_email});

        return _json_error($c, 400, 'target_list_id or assigned_to_email is required')
            unless $target_list_id || $assigned_to_email;

        my $target_list;
        if ($target_list_id) {
            $target_list = mojotodo::Model::TodoList->find($target_list_id);
            return _json_error($c, 404, 'Target list not found') unless $target_list;
        } elsif ($assigned_to_email) {
            my $target_user = mojotodo::Model::User->where({ email => $assigned_to_email })->first;
            return _json_error($c, 404, 'User not found') unless $target_user;

            my @owned_lists = mojotodo::Model::TodoList->where({ owner_user_id => $target_user->id })->all;
            return _json_error($c, 404, 'User has no lists') unless @owned_lists;
            $target_list = $owned_lists[0];
        }

        return _json_error($c, 403, 'No access to target list') unless _user_has_list_access($user_id, $target_list->id);

        my $existing = mojotodo::Model::TaskAssignment->where({
            task_id       => $task->id,
            target_list_id => $target_list->id,
        })->first;
        return _json_error($c, 400, 'Task already assigned to this list') if $existing;

        my $assignment = mojotodo::Model::TaskAssignment->create({
            task_id            => $task->id,
            source_list_id     => $source_list->id,
            target_list_id     => $target_list->id,
            assigned_by_user_id => $user_id,
            assigned_to_user_id => $target_list->owner_user_id,
        });

        my $assignee = mojotodo::Model::User->find($target_list->owner_user_id);
        if ($assignee && $assignee->id != $user_id) {
            mojotodo::Model::Notification->create({
                user_id         => $assignee->id,
                type            => 'task_assigned',
                title           => 'Task assigned to you',
                body            => "A task has been assigned to your list: " . $task->title,
                reference_type  => 'task',
                reference_id    => $task->id,
            });
        }

        return $c->render(status => 201, json => { assignment => $assignment->to_hash });
    });

    # GET /api/tasks/:id/assign - Get assignments for a task
    $r->get('/api/tasks/:id/assign')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $task = mojotodo::Model::Task->find($c->param('id'));
        return _json_error($c, 404, 'Task not found') unless $task;

        my $source_list = mojotodo::Model::TodoList->find($task->todo_list_id);
        return _json_error($c, 403, 'Forbidden') unless _user_has_list_access($user_id, $source_list->id);

        my @assignments = mojotodo::Model::TaskAssignment->where({ task_id => $task->id })->all;
        my @resp = map { $_->to_hash } @assignments;

        return $c->render(status => 200, json => { assignments => \@resp });
    });

    # DELETE /api/tasks/:id/assign/:assignment_id - Remove assignment
    $r->delete('/api/tasks/:id/assign/:assignment_id')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $task = mojotodo::Model::Task->find($c->param('id'));
        return _json_error($c, 404, 'Task not found') unless $task;

        my $source_list = mojotodo::Model::TodoList->find($task->todo_list_id);
        return _json_error($c, 403, 'Forbidden') unless _user_has_list_access($user_id, $source_list->id);

        my $assignment = mojotodo::Model::TaskAssignment->find($c->param('assignment_id'));
        return _json_error($c, 404, 'Assignment not found') unless $assignment;
        return _json_error($c, 403, 'Assignment does not belong to this task') unless $assignment->task_id == $task->id;

        my $target_list = mojotodo::Model::TodoList->find($assignment->target_list_id);
        my $can_delete = $source_list->owner_user_id == $user_id
            || $target_list->owner_user_id == $user_id
            || $assignment->assigned_by_user_id == $user_id;
        return _json_error($c, 403, 'Forbidden') unless $can_delete;

        $assignment->delete;

        return $c->render(status => 200, json => { status => 'deleted' });
    });

    # GET /api/notifications - List user's notifications
    $r->get('/api/notifications')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $page = $c->param('page') // 1;
        my $limit = $c->param('limit') // 20;
        $limit = 100 if $limit > 100;
        $limit = 1 if $limit < 1;
        $page = 1 if $page < 1;
        my $offset = ($page - 1) * $limit;

        my $notifications = mojotodo::Model::Notification->inbox($user_id, {
            limit  => $limit,
            offset => $offset,
        });

        my @all = mojotodo::Model::Notification->where({ user_id => $user_id })->all;
        my $total = scalar @all;
        my $unread = mojotodo::Model::Notification->unread_count($user_id);

        return $c->render(status => 200, json => {
            notifications => $notifications,
            unread_count => $unread,
            page         => $page,
            limit        => $limit,
            total        => $total,
        });
    });

    # POST /api/notifications/:id/read - Mark notification as read
    $r->post('/api/notifications/:id/read')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my $notification = mojotodo::Model::Notification->find($c->param('id'));
        return _json_error($c, 404, 'Notification not found') unless $notification;
        return _json_error($c, 403, 'Forbidden') unless $notification->user_id == $user_id;

        $notification->read_epoch(time);
        $notification->update;

        return $c->render(status => 200, json => { status => 'read' });
    });

    # POST /api/notifications/read-all - Mark all notifications as read
    $r->post('/api/notifications/read-all')->to(cb => sub ($c) {
        my $user_id = _current_user_id($c);
        return _json_error($c, 401, 'Unauthorized') unless $user_id;

        my @unread = mojotodo::Model::Notification->where({
            user_id     => $user_id,
            read_epoch  => undef,
        })->all;

        my $now = time;
        for my $n (@unread) {
            $n->read_epoch($now);
            $n->update;
        }

        return $c->render(status => 200, json => { 
            status      => 'read',
            count       => scalar @unread,
        });
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
