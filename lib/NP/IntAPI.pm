package NP::IntAPI;
use strict;
use warnings;
use NP::UA qw();
use LWP::UserAgent;
use JSON::XS   ();
use Data::Dump ();
use HTTP::Request;
use URI;

use Exporter 'import';
our @EXPORT_OK = qw(
    int_api
);

my $json = JSON::XS->new->utf8;

my $api_base = $ENV{'api-internal'} || 'http://api-internal/';
$api_base =~ s{/$}{};

# ua returns a user agent object with the correct headers for the internal API,
# it should be called for every request
sub ua {
    my $ua = $NP::UA::ua;

    # todo: add global headers for api authentication
    return $ua;
}

sub int_api {
    return _int_api(@_);
}

sub _int_api {
    my ($method, $function, $data) = @_;

    my %r;

    $function =~ s{^/}{};
    my $url = "${api_base}/int/$function";

    warn "calling internal api: $url";

    my $res;

    my $user = delete $data->{user};
    my $auth = "";
    if ($user) {
        $auth = "Bearer $user";
    }

    my $ua = ua();

    if ($method eq 'get') {
        if ($data) {
            my $uri = URI->new($url);
            my $o   = $uri->query_form_hash();
            $uri->query_form_hash({%$o, %$data});
            $url = $uri->as_string();
        }
        $res = $ua->$method($url, 'Authorization' => $auth);
    }
    elsif ($method eq 'post') {
        $res = $ua->$method(
            $url,
            'Authorization' => $auth,
            Content         => $data
        );
    }
    elsif ($method eq 'patch') {

        # For PATCH, $data should contain the JSON body and auth parameters
        my $json_body = delete $data->{data} || '{}';

        # Add auth parameters to URL like GET requests
        if ($data && %$data) {
            my $uri = URI->new($url);
            my $o   = $uri->query_form_hash();
            $uri->query_form_hash({%$o, %$data});
            $url = $uri->as_string();
        }

        $res = $ua->request(
            HTTP::Request->new(
                'PATCH', $url,
                [   'Authorization' => $auth,
                    'Content-Type'  => 'application/json',
                ],
                $json_body
            )
        );
    }
    else {
        warn qq[unknown method "$method" for _int_api];
    }

    warn $res->status_line,     "\n";
    warn $res->decoded_content, "\n";

    if ($res->code >= 300) {
        warn "api-internal response code $function call: ", $res->status_line;
        %r = _parse_message($res, "error");
    }
    elsif ($res->code >= 200) {
        warn "api-internal response code $function call: ", $res->status_line;
        %r = _parse_message($res, "message");
    }
    $r{code}        ||= $res->code;
    $r{status_line} ||= $res->status_line;
    $r{trace_id}    ||= $res->header('TraceID');

    warn "Data: ", Data::Dump::pp(\%r);

    return \%r;
}

sub _parse_message {
    my $res  = shift;
    my $type = shift;

    my %r;
    if ($res->content_type =~ m{^application/json}) {
        $r{data} = $json->decode($res->decoded_content) || {};
        my $message = $r{message} || $res->status_line;
        if ($type eq 'error') {
            $r{error} = "internal api: $message";
        }
        else {
            $r{$type} = $message;
        }
    }
    else {
        $r{$type} = $res->decoded_content || $res->status_line;
    }

    return %r;
}

sub _int_api_get {
    _int_api('get', @_);
}

sub _int_api_post {
    _int_api('post', @_);
}

sub get_monitoring_registration_data {
    my $validation_token = shift;
    my $user_cookie      = shift;
    my $account_token    = shift;

    my $data = _int_api_get(
        "monitor/registration/data",
        {   token => $validation_token,
            user  => $user_cookie,
            a     => $account_token,
        }
    );
    return $data;
}

sub accept_monitoring_registration {
    my $validation_token = shift;
    my $user_cookie      = shift;
    my $account_token    = shift;
    my $location         = shift;

    my $data = _int_api_post(
        "monitor/registration/accept",
        {   token    => $validation_token,
            user     => $user_cookie,
            a        => $account_token,
            location => $location,

        }
    );
    return $data;
}

1;
