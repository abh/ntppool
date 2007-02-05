package NTPPool::Control;
use strict;
use Apache::Constants qw(OK);
use base qw(Combust::Control Combust::Control::Bitcard);
use HTML::Prototype;

$Combust::Control::Bitcard::cookie_name = 'npuid';

my $prototype = HTML::Prototype->new;
sub prototype {
  $prototype;
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
      my ($email_user) = NTPPool::Admin->search({ email => $bc_user->{email} });
#      ($email_user) = NTPPool::Admin->search({ username => $bc_user->{username} })
#        unless $email_user;
      my ($user) = NTPPool::Admin->search({ bitcard_id => $bc_user->{id} });
      $user = $email_user if ($email_user and !$user);
      if ($user and $email_user and $user->id != $email_user->id) {
	my @servers = NTPPool::Server->search( admin => $email_user );
	for my $server (@servers) {
	  $server->admin($user);
	  $server->update;
	}
	$email_user->delete;
      }
      unless ($user) {
	($user) = NTPPool::Admin->create({ bitcard_id => $bc_user->{id} });
      }
      my $uid = $user->id;
      $user->username($bc_user->{username});
      $user->email($bc_user->{email});
      $user->name($bc_user->{name});
      $user->bitcard_id($bc_user->{id});
      $user->update;
      $self->cookie($Combust::Control::Bitcard::cookie_name, $uid);
      $self->user($user);
    }
  }

  if ($self->is_logged_in) {
      $self->r->user( $self->user->username );
  }

  return OK;
}

sub is_logged_in {
  my $self = shift;
  my $user_info = $self->user;
  return 1 if $user_info and $user_info->username;
  return 0;
}

sub bc_user_class {
    'NTPPool::Admin';
}

sub bc_info_required {
    'username,email';
}

sub count_by_continent {
    my $self = shift;
    my $global = NP::Model->zone->fetch(name => '@');
    my @zones = sort { $a->description cmp $b->description } $global->zones;
    push @zones, $global;
    my $total =  NP::Model->zone->fetch(name => '.');
    push @zones, $total;
    \@zones
}

package NTPPool::Control::Basic;
use base qw(NTPPool::Control Combust::Control::Basic);

sub servers_with_urls {
    my $self = shift;
    my @servers = NTPPool::Server->search_urls;
    \@servers;
}

package NTPPool::Control::Error;
use base qw(NTPPool::Control Combust::Control::Error);

1;
