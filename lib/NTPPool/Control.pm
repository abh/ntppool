package NTPPool::Control;
use strict;
use Apache::Constants qw(OK);
use base qw(Combust::Control Combust::Control::Bitcard);

use Class::Accessor::Class;
use base qw(Class::Accessor::Class);

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
                        nl => { name => "Nederlands", },
                        da => { name => "Danish",
                                testing => 1,
                              },
                       );

NP::I18N::add_directory( $config->root_local . '/i18n' );
NP::I18N::loc_lang('en');


my $prototype = HTML::Prototype->new;
sub prototype {
  $prototype;
}

my $ctemplate;
sub tt {
    $ctemplate ||= Combust::Template->new
      ( filters => { l => [\&loc_filter, 1] }
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

  my @lang = $self->languages;
  NP::I18N::loc_lang( $lang[0] );

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
    my ($language) = $self->languages;

    # Always use the 'en' file as last resort. Maybe this should come
    # in before "shared" etc...
    if ($language ne 'en') {
        push @$path, $path->[0] . "en";
    }

    # try the $language version first
    unshift @$path, $path->[0] . "$language/";

    $path;
}

sub current_language {
    my $self = shift;
    return ($self->languages)[0];
}

# TODO: make this actually return a list of possible languages rather
# than just one
sub languages {
    my $self = shift;
    return $self->{_lang} if $self->{_lang}; 
    my $language = first { $valid_languages{$_} } $self->detect_languages;
    return $self->{_lang} = $language || 'en';
}

sub valid_languages {
    \%NTPPool::Control::valid_languages;
}

sub detect_languages {
    my $self = shift;

    my $path_language = $self->request->notes('lang');
    if ($path_language) {
        $self->cookie('lang', $path_language);
        return $path_language;
    }

    my $lang_cookie = $self->cookie('lang');
    return $lang_cookie if $lang_cookie;

    $ENV{REQUEST_METHOD}       = $self->request->method;
    $ENV{HTTP_ACCEPT_LANGUAGE} = $self->request->header_in('Accept-Language') || '';
    my @lang = implicate_supers( I18N::LangTags::Detect::detect() );
    @lang;
}

*loc = \&localize;
sub localize {
    my $self = shift;
    my $lang = $self->languages;
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

package NTPPool::Control::Basic;
use base qw(NTPPool::Control Combust::Control::Basic);

sub render {
    my $self = shift;
    $self->force_template_processing(1) if $self->request->uri =~ m!^/robots.txt$!;
    return $self->SUPER::render(@_);
}

sub servers_with_urls {
    my $self = shift;

    # local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $servers = NP::Model->server->get_servers
        (query => [ or =>
                    [ 'in_pool' => 1,
                      'in_server_list' => 1,
                     ],
                    'score_raw' => { gt => 0 },
                   ],
         require_objects => ['server_urls'],
         sort_by         => 'id',
         );
    $servers;
}

package NTPPool::Control::Error;
use base qw(NTPPool::Control Combust::Control::Error);

1;
