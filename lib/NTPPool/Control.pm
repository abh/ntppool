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
use NP::I18N;
use NP::Version;

my $version = NP::Version->new;
my $config  = Combust::Config->new;

our %valid_languages = (
    bg => {name => "Български", testing => 1},
    ca => {name => "Català",    testing => 1},
    da => {name => "Dansk"},
    de => {name => "Deutsch"},
    en => {name => "English",},
    es => {name => "Español"},
    fi => {name => "Suomi"},
    fr => {name => "Français",},
    hi => {name => "हिन्दी"},
    it => {name => "Italiano"},
    ja => {name => "日本語"},
    ko => {name => "한국어",},
    kz => {name => "Қазақша",   testing => 1},
    nl => {name => "Nederlands",},
    no => {name => "Norsk"},
    pl => {name => "Język",     testing => 1},
    pt => {name => "Português"},
    ro => {name => "Română",    testing => 1},
    rs => {name => "српски srpski"},
    ru => {name => "Русский"},
    sv => {name => "Svenska"},
    tr => {name => "Türkçe"},
    uk => {name => "Українська"},
    zh => {name => "中文（简体）"},
);

NP::I18N::loc_lang('en');

my $ctemplate;

sub tt {
    $ctemplate ||= Combust::Template->new(
        filters => {
            l   => [\&loc_filter, 1],
            loc => [\&loc_filter, 1],
            email => [\&email_address_filter, 0],
        }
    ) or die "Could not initialize Combust::Template object: $Template::ERROR";
}

sub init {
    my $self = shift;

    NP::Model->db->ping;

    if ($self->site ne 'manage') {

        # delete combust cookie from non-manage sites
        if ($self->plain_cookie('c')) {
            $self->plain_cookie('c', '', {expires => '-1'});
        }
    }

    if ($config->site->{$self->site}->{ssl_only}) {
        if (($self->request->header_in('X-Forwarded-Proto') || 'http') eq 'http') {
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

        # :: is for ipv6 "null" addresses in /scores urls
        return $self->redirect($path, 301);
    }

    $self->tpl_param('pool_domain' => Combust::Config->new->site->{ntppool}->{pool_domain}
          || 'pool.ntp.org');

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
    my $language = $self->path_language || $self->detect_language;
    return $self->{_lang} = $language || 'en';
}

sub valid_language {
    my $self      = shift;
    my @languages = @_;
    return first { $valid_languages{$_} } @languages;
}

sub valid_languages {
    \%NTPPool::Control::valid_languages;
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

    my $language_choice = $self->request->header_in('X-Varnish-Accept-Language');
    return $language_choice if $self->valid_language($language_choice);

    $ENV{REQUEST_METHOD} = $self->request->method;
    $ENV{HTTP_ACCEPT_LANGUAGE} = $self->request->header_in('Accept-Language') || '';
    my @lang = implicate_supers(I18N::LangTags::Detect::detect());
    my $lang = $self->valid_language(@lang);

    return $lang;
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
        and $self->request->uri !~ m{^/(manage|static)}
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
    return $self->_url('manage', @_);
}

sub count_by_continent {
    my $self = shift;
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

    my @headers = (

        # report-uri.com headers
        [   'Report-To' =>
              '{"group":"default","max_age":31536000,"endpoints":[{"url":"https://ntp.report-uri.com/a/d/g"}],"include_subdomains":true}'
        ],
        ['NEL' => '{"report_to":"default","max_age":31536000,"include_subdomains":true}'],
        [   'Content-Security-Policy-Report-Only' =>
              q[default-src 'none'; form-action 'none'; frame-ancestors 'none'; connect-src 'self' 8ll7xvh0qt1p.statuspage.io; font-src fonts.gstatic.com; img-src 'self' st.pimg.net *.mapper.ntppool.org; script-src 'self' 'unsafe-inline' cdn.statuspage.io st.pimg.net www.mapper.ntppool.org; style-src 'self' fonts.googleapis.com st.pimg.net; report-uri https://ntp.report-uri.com/r/d/csp/wizard]
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
