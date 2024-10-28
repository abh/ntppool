package NTPPool::Control;
use strict;
use utf8;
use Combust::Constant qw(OK);
use base qw(Combust::Control Combust::Control::StaticFiles NTPPool::Control::Login);

use Carp qw(cluck);
use Storable qw(retrieve);
use I18N::LangTags qw(implicate_supers);
use I18N::LangTags::Detect ();
use List::Util qw(first);
use Unicode::Collate;
use Data::ULID;
use JSON::XS qw(decode_json);
use Syntax::Keyword::Dynamically;
use OpenTelemetry::Constants qw( SPAN_KIND_SERVER SPAN_STATUS_ERROR SPAN_STATUS_OK );
use OpenTelemetry -all;
use OpenTelemetry::Trace;

use NP::I18N;
use NP::Version;

my $version = NP::Version->new;
my $config  = Combust::Config->new;

our %valid_languages = (
    ar => {name => "اَلْعَرَبِيَّةُ", testing => 1},
    bg => {name => "Български",       testing => 1},
    ca => {name => "Català",          testing => 1},
    da => {name => "Dansk"},
    de => {name => "Deutsch"},
    el => {name => "Ελληνικά"},
    en => {name => "English",},
    es => {name => "Español"},
    eu => {name => "Euskara", testing => 1},
    fa => {name => "فارسی",   testing => 1},
    fi => {name => "Suomi"},
    fr => {name => "Français",},
    he => {name => "עברית", testing => 1},
    hi => {name => "हिन्दी"},
    hu => {name => "Magyar",           testing => 1},
    id => {name => "Bahasa Indonesia", testing => 1},
    it => {name => "Italiano"},
    ja => {name => "日本語"},
    kk => {name => "Қазақша", testing => 1},
    ko => {name => "한국어",},
    nb => {name => "Norsk (bokmål)"},
    nl => {name => "Nederlands",},
    nn => {name => "Norsk (nynorsk)"},
    pl => {name => "Język", testing => 1},
    pt => {name => "Português"},
    ro => {name => "Română", testing => 1},
    ru => {name => "Русский"},
    sr => {name => "Српски"},
    sv => {name => "Svenska"},
    tr => {name => "Türkçe"},
    uk => {name => "Українська"},
    zh_CN => {name => "中文（简体）"},
    zh_TW => {name => "中文（繁體）"},
);

# We unfortunately have dialects to deal with now.
our %language_aliases = (
    'zh' => 'zh_CN',
    'zh_Hans' => 'zh_CN',
    'zh_Hant' => 'zh_TW',
    'zh_HK' => 'zh_TW',
    'zh_MO' => 'zh_TW',
    'zh_SG' => 'zh_CN',
    'zh_MY' => 'zh_CN',
);

NP::I18N::loc_lang('en');

my $uc = Unicode::Collate->new();

my $valid_languages_sorted = [
    sort { $uc->cmp($valid_languages{$a}->{name}, $valid_languages{$b}->{name}) }
      keys %valid_languages
];

my $ctemplate;

sub tt {
    $ctemplate ||= Combust::Template->new(
        filters => {
            l     => [\&loc_filter,           1],
            loc   => [\&loc_filter,           1],
            email => [\&email_address_filter, 0],
        }
    ) or die "Could not initialize Combust::Template object: $Template::ERROR";
}

sub request_id {
    my ($self, $id) = @_;
    $self->{_request_id} = $id if $id;
    return $self->{_request_id};
}

sub init {
    my $self = shift;

    my $span       = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    my $class_name = ref $self;
    $span->set_attribute("class", $class_name);

    # set better name for the outer span
    $class_name =~ s/^NTPPool::Control:://;
    $self->set_span_name($class_name);

    my $request_id = $self->request_id(Data::ULID::ulid());
    $self->request->header_out('Request-ID', $request_id);
    $span->set_attribute("combust.request-id", $request_id);

    for my $h (
        qw(
            X-Forwarded-For
            X-Original-Forwarded-For
            X-Real-IP
            CF-Connecting-IP CF-RAY
            Fastly-Client-IP
        )
      )
    {
        my $d = $self->request->header_in($h);
        $span->set_attribute(lc("http.request.header.$h"), $d) if $d;
    }

    my $tracer = NP::Tracing->tracer;
    my $span   = $tracer->create_span(
        name => "init",

        # kind => SPAN_KIND_SERVER,
        # attributes => {url => $uri,},
    );
    dynamically otel_current_context = otel_context_with_span($span);

    NP::Model->db->ping;

    my $trace_id = $span->context->hex_trace_id;
    $self->request->header_out('Traceparent', $trace_id);

    if ($self->site ne 'manage') {

        # delete combust cookie from non-manage sites
        if ($self->plain_cookie('c')) {
            $self->plain_cookie('c', '', {expires => '-1'});
        }
    }

    if ($config->site->{$self->site}->{ssl_only}) {
        if (($self->request->header_in('X-Forwarded-Proto') || 'http') eq 'http') {
            $span->end();
            return $self->redirect($self->_url($self->site, $self->request->path));
        }
        else {
           # we're setting Strict-Transport-Security with haproxy
           # $self->request->header_out('Strict-Transport-Security', 'max-age=' . (86400 * 7 * 20));
        }
    }

    my $path = $self->request->path;

    if ($path !~ m!(^/static/|\.png|\.json$)!) {
        my $lang = $self->language;
        NP::I18N::loc_lang($lang);
        $self->tpl_param('current_language', $lang);
    }
    else {
        $self->tpl_param('current_language', 'en');
    }

    if ($path !~ m{^/s(cores)?/.*::$} and $path =~ s/[\).:>}]+$//) {

        $span->end();

        # :: is for ipv6 "null" addresses in /scores urls
        return $self->redirect($path, 301);
    }

    $self->tpl_param('pool_domain' => Combust::Config->new->site->{ntppool}->{pool_domain}
          || 'pool.ntp.org');

    $span->end();
    return OK;
}

sub loc_filter {
    my $tt   = shift;
    my @args = @_;
    return sub { NP::I18N::loc($_[0], @args) };
}

sub email_address_filter {

    # static filter
    my $label = shift;
    return NP::Email::address($label);
}

# should be moved to the manage class when sure we don't use is_logged_in on the ntppool site
sub is_logged_in {
    my $self      = shift;
    my $user_info = $self->user;
    return 1 if $user_info and $user_info->username;
    return 0;
}

sub get_include_path {
    my $self = shift;
    my $path = $self->SUPER::get_include_path;

    return $path if $self->request->path =~ m!(^/static/|\.png$)!;

    my ($language) = $self->language;

    # Always use the 'en' file as last resort. Maybe this should come
    # in before "shared" etc...
    if ($language ne 'en') {
        push @$path, $path->[0] . "en";
    }

    # try the $language version first
    unshift @$path, $path->[0] . "$language/";

    return $path;
}

# Because of how the varnish caching works there's just one language
# with fallback to English.  If we ever get more dialects we'll worry
# about that then.
sub language {
    my $self = shift;
    return $self->{_lang} if $self->{_lang};
    my $language = $self->path_language || $self->detect_language || 'en';
    my $span     = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    $span->set_attribute("combust.lang", $language);
    return $self->{_lang} = $language;
}

sub valid_language {
    my $self      = shift;
    my @languages = @_;
    return first {
        s/-/_/g;
        $valid_languages{$_} // $valid_languages{$language_aliases{$_}}
    } @languages;
}

sub valid_languages {
    \%NTPPool::Control::valid_languages;
}

sub valid_languages_sorted {
    return $valid_languages_sorted;
}

sub path_language {
    my $self          = shift;
    my $path_language = $self->request->notes('lang');
    return $path_language;
}

sub detect_language {
    my $self = shift;

    if ($self->plain_cookie('lang')) {
        $self->plain_cookie('lang', '', {expires => '-1'});
    }

    $self->request->header_out('Vary', 'Accept-Language');

    my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    for my $h (qw(X-Varnish-Accept-Language Accept-Language)) {
        my $d = $self->request->header_in($h);
        $span->set_attribute(lc("http.request.header.$h"), $d) if $d;
    }

    my $language_choice = $self->request->header_in('X-Varnish-Accept-Language');
    if ($self->valid_language($language_choice)) {
        $span->set_attribute("combust.lang_detect", $language_choice);
        return $language_choice;
    }

    $ENV{REQUEST_METHOD}       = $self->request->method;
    $ENV{HTTP_ACCEPT_LANGUAGE} = $self->request->header_in('Accept-Language') || '';
    my @lang = implicate_supers(I18N::LangTags::Detect::detect());
    my $lang = $self->valid_language(@lang);

    $span->set_attribute("combust.lang_detect", ($lang || ''));

    return $lang;
}

sub set_span_name {
    my $self = shift;
    my $name = shift or return;
    my $span = OpenTelemetry::Trace->span_from_context(OpenTelemetry::Context->current);
    $span->recording or return;

    if (!$span->can('snapshot')) {
        warn "span does not have snapshot method, can't change name";
        return;
    }

    # set better name for the outer span
    my $span_name = $span->snapshot->name;
    $span_name =~ s/^(\S+).*/$1 ${name}/;    # preserve the http method
    $span->set_name($span_name);

}

*loc = \&localize;

sub localize {
    my $self = shift;
    my $lang = $self->language;
}

sub localize_url {
    my $self = shift;
    if ($self->request->path eq '/'    # this short-circuits some of the rest
        and !$self->path_language
        and $self->request->method =~ m/^(head|get)$/
        and $self->request->uri    !~ m{^/(manage|static)}
      )
    {
        my $lang = $self->language;

        my $uri =
          URI->new($self->config->base_url('ntppool')
              . $self->request->uri
              . ($self->request->args ? '?' . $self->request->args : ''));

        $uri->path("/$lang" . $uri->path);
        $self->request->header_out('Vary', 'Accept-Language');
        $self->cache_control(
            's-maxage=900, max-age=3600, stale-while-revalidate=90, stale-if-error=43200');
        return $self->redirect($uri->as_string);
    }
    return;
}

sub _url {
    my ($self, $site, $url, $args) = @_;
    my $uri = URI->new($config->base_url($site) . $url);
    if ($config->site->{$site}->{ssl_only}) {
        $uri->scheme('https');
    }
    if ($args) {
        if (ref $args) {
            $uri->query_form(%$args);
        }
        else {
            $uri->query($args);
        }
    }
    return $uri->as_string;
}

sub www_url {
    my $self = shift;
    return $self->_url('ntppool', @_);
}

sub manage_url {
    my $self = shift;
    my $url  = shift;
    my $args = shift || {};
    if ($self->user and !$args->{a}) {
        my $account = $self->can('current_account') && $self->current_account;
        $args->{a} = $account->id_token() if $account;
    }

    return $self->_url('manage', $url, $args);
}

sub analytics_hostname {
    my $self       = shift;
    my $sitename   = $self->site;
    my $servername = $config->site->{$sitename}->{servername};
    unless ($servername) {
        cluck "servername not defined for site [$sitename]";
        return;
    }
    return $servername;
}

sub system_setting {
    my $self = shift;
    my $name = shift;

    my $k = "_system_setting_$name";

    return $self->{$k} if $self->{$k};

    my $settings = NP::Model->system_setting->fetch(key => $name);
    if (!$settings) {
        return undef;
    }
    $settings = $settings->value;
    return $self->{$k} = $settings;
}

sub system_feature {
    my $self     = shift;
    my $name     = shift;
    my $features = $self->system_setting('features') or return 0;
    return $features->{$name} ? 1 : 0;
}

sub count_by_continent {
    my $self   = shift;
    my $global = NP::Model->zone->fetch(name => '@');
    unless ($global) {
        warn "zones appear not to be setup, run ./bin/populate_zones!";
        return;
    }
    my @zones = sort { $a->description cmp $b->description } $global->zones;
    push @zones, $global;
    my $total = NP::Model->zone->fetch(name => '.');
    push @zones, $total;
    \@zones;
}

sub redirect {
    my ($self, $url) = (shift, shift);
    $self->post_process;
    return $self->SUPER::redirect($url, @_);
}

sub cache_control {
    my $self = shift;
    return $self->{cache_control} unless @_;
    return $self->{cache_control} = shift;
}

sub post_process {
    my $self = shift;

    my $cspdomains = "st.ntppool.org st.pimg.net news.ntppool.org";

    my @headers = (

        # report-uri.com headers
        [   'Report-To' =>
              '{"group":"default","max_age":31536000,"endpoints":[{"url":"https://ntppool.report-uri.com/a/t/g"}],"include_subdomains":true}'
        ],
        ['NEL' => '{"report_to":"default","max_age":31536000,"include_subdomains":true}'],
        [   'Content-Security-Policy-Report-Only' => join(
                " ",
                qq[default-src 'none'; frame-ancestors 'none';],
                qq[connect-src 'self' www.ntppool.org st.ntppool.org 8ll7xvh0qt1p.statuspage.io;],
                qq[font-src fonts.gstatic.com;],
                qq[form-action 'self' mailform.ntppool.org checkout.stripe.com;],
                qq[img-src 'self' $cspdomains *.mapper.ntppool.org;],
                qq[script-src 'self' 'unsafe-eval' 'unsafe-inline' cdn.statuspage.io $cspdomains www.mapper.ntppool.org js.stripe.com;],
                qq[style-src 'self' fonts.googleapis.com $cspdomains;],

                # qq[child-src 'self' js.stripe.com;],
                qq[report-uri https://ntppool.report-uri.com/r/t/csp/wizard],
            ),
        ],

        # security features
        ['X-Content-Type-Options' => 'nosniff'],
        ['X-Frame-Options'        => 'deny'],
        ['Referrer-Policy'        => 'origin-when-cross-origin'],

        # ntppool version / build
        ['X-NPV' => $version->current_release . " (" . $version->hostname . ")"],
    );

    for my $h (@headers) {
        $self->request->header_out($h->[0], $h->[1]);
    }

    if (my $cache = $self->cache_control) {
        my $req = $self->request;
        $req->header_out('Cache-Control', $cache);
    }

    return OK;
}

sub plain_cookie {
    my $self   = shift;
    my $cookie = shift;
    my $value  = shift || '';
    my $args   = shift || {};

    my $ocookie = $self->request->get_cookie($cookie) || '';

    unless (defined $value and $value ne ($ocookie || '')) {
        return $ocookie;
    }

    $args->{domain} =
         delete $args->{domain}
      || $self->site && $self->config->site->{$self->site}->{cookie_domain}
      || $self->request->uri->host
      || '';

    $args->{path} ||= '/';
    $args->{expires} = time + (30 * 86400) unless defined $args->{expires};
    if ($args->{expires} =~ m/^-/) {
        $args->{expires} = 1;
    }

    $args->{value} = $value;

    return $self->request->response->cookies->{$cookie} = $args;
}

1;
