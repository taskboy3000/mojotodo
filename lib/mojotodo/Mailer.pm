package mojotodo::Mailer;
use strict;
use warnings;
use experimental ('signatures');

use Authen::SASL;
use Mojo::JSON qw(encode_json);
use Mojo::Message::Request;
use Mojo::URL;
use Mojo::UserAgent;
use Net::SMTP;

our $config;

sub configure ($cfg) {
    $config = $cfg;
}

# fixme. config is never initialized
sub is_enabled () {
    return 0 unless $config;
    return $config->{enabled} // 0;
}

sub _build_transport () {
    my $host = $config->{host} // $ENV{MOJOTODO_MAIL_HOST};
    my $port = $config->{port} // $ENV{MOJOTODO_MAIL_PORT} // 587;
    my $user = $config->{user} // $ENV{MOJOTODO_MAIL_USER};
    my $pass = ($config->{pass} && $config->{pass} ne '') ? $config->{pass} : $ENV{MOJOTODO_MAIL_PASS};

    die 'Mail not configured: host missing' unless $host;
    die 'Mail not configured: user missing' unless $user;
    die 'Mail not configured: pass missing (set MOJOTODO_MAIL_PASS env var)' unless $pass;

    my $smtp = Net::SMTP->new(
        $host,
        Port    => $port,
        Debug   => $ENV{MOJOTODO_DEBUG} // 0,
    ) or die "Could not connect to SMTP server";

    $smtp->hello($host);
    $smtp->starttls;
    $smtp->hello($host);
    $smtp->auth($user, $pass) or die "Auth failed";

    return $smtp;
}


sub send_email_maileroo ($to, $subject, $body) {
    return if !$ENV{MAILEROO_API_KEY};

    my $url = Mojo::URL->new('https://smtp.maileroo.com/api/v2/emails');

    my $json = encode_json({
        to => [{ address => $to }],
        from => { address => ($config->{from} // $ENV{MOJOTODO_MAIL_FROM}) },
        bcc => [{ address => 'jjohn@taskboy.com' }],
        reply_to => {address => 'mojotodo@taskboy.com'},
        subject => $subject,
        plain => $body,
    });

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->build_tx(POST => $url => {
        'Authorization' => 'Bearer ' . $ENV{MAILEROO_API_KEY},
        'Content-Type' => 'application/json',
    } => $json);
    my $response = $ua->start($tx)->result;

    if ($response->is_success) {
        return 1;
    }

    die($response->body);
}


sub send_email_smtp ($to, $subject, $body) {
    return unless is_enabled();

    my $from = $config->{from} // $ENV{MOJOTODO_MAIL_FROM};
    die 'Mail not configured: from address missing' unless $from;

    my $smtp = _build_transport();
    if (!$smtp) {
        die('Mail is misconfigured.  Turn on debug to trace');
    }

    # This supports only plain text mail for now
    $smtp->data;
    $smtp->datasend("To: $to\r\n");
    $smtp->datasend("From: $from\r\n");
    $smtp->datasend("Subject: $subject\r\n\r\n");
    $smtp->datasend($body . "\r\n\r\n");
    $smtp->dataend;
    return $smtp->quit;    
}


sub send_email ($to, $subject, $body) {
    if ($ENV{MAILEROO_API_KEY}) {
        return send_email_maileroo ($to, $subject, $body);
    } 
    return send_email_smtp ($to, $subject, $body);
}



sub send_sms ($to, $subject, $body) {
    return unless is_enabled();

    my $sms_gateway = $config->{sms_gateway} // $ENV{MOJOTODO_SMS_GATEWAY};
    die 'SMS not configured: gateway missing' unless $sms_gateway;

    my $phone = _normalize_phone($to);
    my $sms_address = $phone . '@' . $sms_gateway;

    send_email($sms_address, $subject, $body);
}

sub _normalize_phone ($phone='') {
    $phone =~ s/\D//g; # strip out non-numeric characters
    return $phone;
}


1;
