package NTPPool::Control;
use strict;
use utf8;
use Combust::Constant qw(OK);
use base qw(Combust::Control Combust::Control::Bitcard);

use HTML::Prototype;
use Carp qw(cluck);
use Storable qw(retrieve);
use Combust::StaticFiles qw(-force :all);
use I18N::LangTags qw(implicate_supers);
use I18N::LangTags::Detect ();
use List::Util qw(first);
use NP::I18N;

$Combust::Control::Bitcard::cookie_name = 'npuid';

my $config = Combust::Config->new;

our %valid_languages = (
                        en => { name => "English", },
                        fr => { name => "Français", },
                        #nl => { name => "Nederlands", },
                        ru => { name => "русский", },  
                        pl => { name => "Polish",
                                testing => 1 },
                        da => { name => "Danish",
                                testing => 1,
                              },
                       );

NP::I18N::loc_lang('en');

my $prototype = HTML::Prototype->new;
sub prototype {
  $prototype;
}

my $ctemplate;
sub tt {
    $ctemplate ||= Combust::Template->new
      ( filters => { l   => [\&loc_filter, 1],
                     loc => [\&loc_filter, 1],
                   }
      )
      or die "Could not initialize Combust::Template object: $Template::ERROR";
}

sub init {
  my $self = shift;

  if ($self->req_param('sig') or $self->req_param('bc_id')) {
    my $bc = $self->bitcard;
    my $bc_user = eval { $bc->verify($self->r) };
    warn $@ if $@;
    unless ($bc_user) {
      warn $bc->errstr;
    }
    if ($bc_user and $bc_user->{id} and $bc_user->{username}) {
      my ($email_user) = NP::Model->user->fetch(email => $bc_user->{email});
      my ($user) = NP::Model->user->fetch(bitcard_id => $bc_user->{id});
      $user = $email_user if ($email_user and !$user);
      if ($user and $email_user and $user->id != $email_user->id) {
	my @servers = NP::Model->server->get_servers(query => [ admin => $email_user ]);
	for my $server (@servers) {
	  $server->admin($user);
	  $server->save;
	}
	$email_user->delete;
      }
      unless ($user) {
	($user) = NP::Model->user->create(bitcard_id => $bc_user->{id});
      }
      my $uid = $user->id;
      $user->username($bc_user->{username});
      $user->email($bc_user->{email});
      $user->name($bc_user->{name});
      $user->bitcard_id($bc_user->{id});
      $user->save;
      $self->cookie($Combust::Control::Bitcard::cookie_name, $uid);
      $self->user($user);
    }
  }

  if ($self->is_logged_in) {
      $self->r->user( $self->user->username );
  }

  my $lang = $self->language;
  NP::I18N::loc_lang( $lang );

  return OK;
}

sub loc_filter {
    my $tt   = shift;
    my @args = @_;
    return sub { NP::I18N::loc($_[0], @args) };
}


sub is_logged_in {
  my $self = shift;
  my $user_info = $self->user;
  return 1 if $user_info and $user_info->username;
  return 0;
}

sub bc_user_class {
    NP::Model->user;
}

sub bc_info_required {
    'username,email';
}

sub get_include_path {
    my $self = shift;
    my $path = $self->SUPER::get_include_path;
    my ($language) = $self->language;

    # Always use the 'en' file as last resort. Maybe this should come
    # in before "shared" etc...
    if ($language ne 'en') {
        push @$path, $path->[0] . "en";
    }

    # try the $language version first
    unshift @$path, $path->[0] . "$language/";

    $path;
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
    my $self = shift;
    my @languages = @_;
    return first { $valid_languages{$_} } @languages;
}

sub valid_languages {
    \%NTPPool::Control::valid_languages;
}

sub path_language {
    my $self = shift;
    my $path_language = $self->request->notes('lang');
    return $path_language;
}

sub detect_language {
    my $self = shift;

    my $language_choice = $self->plain_cookie('lang')
      || $self->request->header_in('X-Language') 
      || $self->cookie('lang');

    if (my $old_cookie = $self->cookie('lang')) {
        $self->plain_cookie('lang', $old_cookie);
        $self->cookie('lang', undef);
    }
    return $language_choice if $self->valid_language($language_choice);

    $ENV{REQUEST_METHOD}       = $self->request->method;
    $ENV{HTTP_ACCEPT_LANGUAGE} = $self->request->header_in('Accept-Language') || '';
    my @lang = implicate_supers( I18N::LangTags::Detect::detect() );
    my $lang = $self->valid_language(@lang);

    $self->plain_cookie('lang', $lang) if $lang;

    return $lang;
}

*loc = \&localize;
sub localize {
    my $self = shift;
    my $lang = $self->language;
}

sub localize_url {
    my $self = shift;
    if (!$self->path_language
        and $self->request->method =~ m/^(head|get)$/ 
        and $self->request->uri !~ m{^/manage}
       ) {
        my $lang = $self->language;
        
        my $uri =
          URI->new($self->config->base_url('ntppool')
                   . $self->request->uri
                   . ($self->request->args ? '?' . $self->request->args : ''));
        
        $uri->path("/$lang" . $uri->path);
        $self->request->header_out('Vary', 'Accept-Language');
        $self->cache_control('s-maxage=900, maxage=3600');
        die $self->redirect($uri->as_string);
    }
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
    my $total =  NP::Model->zone->fetch(name => '.');
    push @zones, $total;
    \@zones
}

sub cache_control {
    my $self   = shift;
    return $self->{cache_control} unless @_;
    return $self->{cache_control} = shift;
}

sub post_process {
    my $self = shift;

    # Tell IE8 that standards mode is what we want
    # http://farukat.es/journal/2009/05/245-ie8-and-the-x-ua-compatible-situation
    $self->request->header_out('X-UA-Compatible', 'IE=8');

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

    return $ocookie unless $value;
    return $ocookie if $value eq $ocookie;

    $args->{path}   ||= '/';
    $args->{expires} = '+30d' unless defined $args->{expires};

    return $self->request->cookie($cookie, $value, $args);
}




1;
