# MojoTodo

A lightweight single-page web application (SPA) for collaborative todo list management built with Mojolicious and SQLite3.

## Features

- Multi-user support with passwordless authentication
- Multiple todo lists per user
- Task sharing between users
- Deadline tracking with visual indicators for late/nearly late tasks
- Email and SMS delivery for verification codes
- RESTful API for potential iOS client integration

## Requirements

- Perl 5.36+
- SQLite3
- libnet-ssleay-perl and libio-socket-ssl-perl (for email/SMS)
- CPAN modules (see cpanfile)

## Installation

```bash
# Install system dependencies (Debian/Ubuntu)
sudo apt-get install libnet-ssleay-perl libio-socket-ssl-perl

# Install Perl dependencies
cpanm --installdeps .

# Run tests
prove -l t/
```

## Configuration

Configuration is loaded from `mojotodo.conf` in the application root.

### Database

The database is configured in the `database` section:

```json
{
    "database": {
        "dsn": "dbi:SQLite:dbname=app.db"
    }
}
```

**DSN Format:** `dbi:SQLite:dbname=PATH_TO_DB`

The database file path can be:
- Relative: `dbname=app.db` (creates `app.db` in the application directory)
- Absolute: `dbname=/var/lib/mojotodo/app.db`

**Environment Variable Override:**

You can override the DSN using the `MOJOTODO_DSN` environment variable:

```bash
export MOJOTODO_DSN="dbi:SQLite:dbname=/var/lib/mojotodo/app.db"
```

### Authentication

The `auth` section configures passwordless authentication:

| Option | Default | Description |
|--------|---------|-------------|
| `code_digits` | 6 | Number of digits in verification code |
| `code_ttl_seconds` | 600 | Time-to-live for codes (10 minutes) |
| `resend_cooldown` | 30 | Seconds between code requests |
| `max_verify_attempts` | 5 | Max failed attempts before code expires |
| `dev_return_code` | 1 | Return code in response (development only) |
| `code_pepper` | "change-me-in-production" | Secret pepper for code hashing |

**Important:** In production, set `dev_return_code` to `0` and change `code_pepper` to a secure random string.

**Environment Variables:**

```bash
export MOJOTODO_CODE_PEPPER="your-secure-random-pepper-string"
export MOJOTODO_FAKE_AUTH=1  # Bypass auth (development only!)
```

### Mailer (Email/SMS)

The `mail` section configures email delivery for verification codes:

```json
{
    "mail": {
        "enabled": 1,
        "host": "smtp.gmail.com",
        "port": 587,
        "user": "your-email@gmail.com",
        "pass": "your-app-password",
        "from": "MojoTodo <your-email@gmail.com>",
        "use_tls": 1,
        "sms_gateway": "txt.att.net"
    }
}
```

| Option | Description |
|--------|-------------|
| `enabled` | Set to 1 to enable mail delivery |
| `host` | SMTP server hostname |
| `port` | SMTP port (typically 587 for TLS) |
| `user` | SMTP username |
| `pass` | SMTP password (or use env var `MOJOTODO_MAIL_PASS`) |
| `from` | From address for emails |
| `use_tls` | Enable TLS (recommended) |
| `sms_gateway` | Email-to-SMS gateway (see below) |

**Gmail Configuration:**

**Important:** Gmail requires an "App Password" - you cannot use your regular Gmail password.

1. Enable 2-Factor Authentication on your Google account
2. Go to https://myaccount.google.com/apppasswords
3. Generate an "App Password" for "Mail" (select "Other" and name it "MojoTodo")
4. Use that 16-character app password as the `pass` value or `MOJOTODO_MAIL_PASS`

**Environment Variable Override:**

Mail configuration can also be set via environment variables:

```bash
export MOJOTODO_MAIL_HOST="smtp.gmail.com"
export MOJOTODO_MAIL_USER="your-email@gmail.com"
export MOJOTODO_MAIL_PASS="your-app-password"
export MOJOTODO_MAIL_FROM="MojoTodo <your-email@gmail.com>"
export MOJOTODO_MAIL_PORT=587
export MOJOTODO_MAIL_USE_TLS=1
export MOJOTODO_SMS_GATEWAY="txt.att.net"
```

### SMS Gateways

To receive verification codes via SMS, configure an email-to-SMS gateway. Common US carriers:

| Carrier | Gateway |
|---------|---------|
| AT&T | `txt.att.net` |
| Verizon | `vtext.com` |
| T-Mobile | `tmomail.net` |
| Sprint | `messaging.sprintpcs.com` |
| US Cellular | `email.uscc.com` |

## Running the Application

### Development Mode

```bash
# Start the development server
./start_debug_server.sh
```

The app will be available at http://0.0.0.0:8080

### Production Mode

```bash
# Using hypnotoad
hypnotoad script/mojotodo
```

Or with environment variables:

```bash
MOJOTODO_DSN="dbi:SQLite:dbname=/var/lib/mojotodo/app.db" \
MOJOTODO_MAIL_PASS="your-password" \
hypnotoad script/mojotodo
```

## API Endpoints

### Authentication

- `POST /api/auth/request-code` - Request verification code
  - Body: `{ "email": "user@example.com", "code_type": "email" }`
  - `code_type` can be "email" or "sms"
- `POST /api/auth/verify-code` - Verify code and login
  - Body: `{ "email": "user@example.com", "code": "123456" }`
- `POST /api/logout` - End session

### Account

- `GET /api/account` - Get account info
- `PATCH /api/account` - Update account (phone, preferred contact method)
- `DELETE /api/account` - Delete account

### Lists

- `GET /api/lists` - List user's lists
- `POST /api/lists` - Create list
- `GET /api/lists/:id` - Get list
- `PATCH /api/lists/:id` - Update list
- `DELETE /api/lists/:id` - Delete list

### Tasks

- `GET /api/lists/:id/tasks` - List tasks (supports `hide_assigned_out`, `page`, `limit`)
- `POST /api/lists/:id/tasks` - Create task
- `PATCH /api/lists/:list_id/tasks/:id` - Update task
- `DELETE /api/lists/:list_id/tasks/:id` - Delete task

### Sharing

- `GET /api/lists/:id/share` - List collaborators
- `POST /api/lists/:id/share` - Share list
- `DELETE /api/lists/:id/share/:share_id` - Remove collaborator

### Assignments

- `GET /api/tasks/:id/assign` - List assignments
- `POST /api/tasks/:id/assign` - Assign task
- `DELETE /api/tasks/:id/assign/:assignment_id` - Remove assignment

## Third-Party Libraries

- **Bootstrap 5** (MIT) - UI framework
- **Bootstrap Icons** (MIT) - Icons
- **SortableJS** (MIT) - Drag and drop reordering

## Deployment

### Systemd Service

A systemd service file is provided for running MojoTodo with hypnotoad:

**File:** `mojotodo.service`

```ini
[Unit]
Description=MojoTodo - Lightweight Todo List Application
After=network.target

[Service]
Type=forking
User=mojotodo
Group=mojotodo
WorkingDirectory=/opt/mojotodo
Environment="MOJOTODO_DSN=dbi:SQLite:dbname=/var/lib/mojotodo/app.db"
Environment="MOJOTODO_CODE_PEPPER=change-this-to-secure-random-string"
ExecStart=/usr/local/bin/hypnotoad /opt/mojotodo/lib/mojotodo.pm
ExecStop=/usr/local/bin/hypnotoad -s /opt/mojotodo/lib/mojotodo.pm
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/mojotodo /var/log/mojotodo

[Install]
WantedBy=multi-user.target
```

**Installation:**

```bash
# Create dedicated user and directories
sudo useradd -r -s /bin/false mojotodo
sudo mkdir -p /var/lib/mojotodo /var/log/mojotodo
sudo chown mojotodo:mojotodo /var/lib/mojotodo /var/log/mojotodo

# Copy application files
sudo cp -r /path/to/mojotodo /opt/mojotodo
sudo chown -R mojotodo:mojotodo /opt/mojotodo

# Copy and enable service
sudo cp mojotodo.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mojotodo
```

**Set secrets via environment file** (`/etc/mojotodo.env`):

```bash
MOJOTODO_MAIL_PASS=your-mail-password
MAILEROO_API_KEY=your-api-key
```

Then update the service file to use `EnvironmentFile=/etc/mojotodo.env`

### Apache2 Reverse Proxy

This configuration proxys HTTPS requests to the MojoTodo application running on port 9090.

**File:** `/etc/apache2/sites-available/mojotodo.conf`

```apache
<VirtualHost *:80>
  ServerName www.mojotodo.com
  ServerAlias mojotodo.com
  Redirect permanent / https://www.mojotodo.com/
</VirtualHost>

<IfModule mod_ssl.c>
ProxyRequests Off
<VirtualHost *:443>
  ServerName www.mojotodo.com
  ServerAlias mojotodo.com

  CustomLog /var/log/apache2/mojotodo_access.log combined
  ErrorLog /var/log/apache2/mojotodo_error.log

  <Location />
     ProxyPass http://localhost:9090/
     ProxyPassReverse http://localhost:9090/
     ProxyPreserveHost On
     RequestHeader set X-Forwarded-Proto https
  </Location>

  Include /etc/letsencrypt/options-ssl-apache.conf
  SSLCertificateFile /etc/letsencrypt/live/www.mojotodo.com/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/www.mojotodo.com/privkey.pem
</VirtualHost>
</IfModule>
```

**Enable the site:**

```bash
sudo a2enmod proxy proxy_http headers ssl
sudo cp mojotodo.apache2.conf /etc/apache2/sites-available/mojotodo.conf
sudo aensite mojotodo
sudo systemctl reload apache2
```

**Note:** Update the `SSLCertificateFile` and `SSLCertificateKeyFile` paths to match your certificate location.
