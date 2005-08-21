package NTPPool::Control;
use strict;
use Apache::Constants qw(OK);
use base qw(Combust::Control);
use NTPPool::Server;

our $cookie_name = 'npuid';

sub init {
  my $self = shift;
  
  #my $lo = \%Class::DBI::Live_Objects;
  #warn Data::Dumper->Dump([\$lo], [qw(lo)]) if defined $lo and %$lo;

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
      $self->cookie($cookie_name, $uid);
      $self->user($user);
    }
  }

  return OK;
}


sub is_logged_in {
  my $self = shift;
  my $user_info = $self->user;
  return 1 if $user_info and $user_info->username;
  return 0;
}

sub user {
  my $self = shift;

  return $self->{_user} if $self->{_user};

  if (@_) {
    return $self->{_user} = $_[0];
  }

  my $uid = $self->cookie($cookie_name) or return;
  my $user = NTPPool::Admin->retrieve($uid);
  return $self->{_user} = $user if $user;
  $self->cookie($cookie_name, '0');
  return;
}

sub bitcard {
  my $self = shift;
  my $bc = $self->SUPER::bitcard(@_);
  $bc->info_required('username,email');
  $bc;
}

sub _here_url {
  my $self = shift;
  my $here = URI->new($self->config->base_url('ntppool')
		      . $self->r->uri 
		      . '?' . $self->r->query_string 
		     );
  $here->as_string;
}

sub login_url {
  my $self = shift;
  my $bc = $self->bitcard;
  #$bc->info_required('email,username');
  $bc->login_url( r => $self->_here_url )
}

sub account_url {
  my $self = shift;
  my $bc = $self->bitcard;
  $bc->account_url( r => $self->_here_url )
}

sub login {
  my $self = shift;
  $self->tpl_param('login_url', $self->login_url);
  return OK, $self->evaluate_template('tpl/login.html');
}


sub count_by_continent {
    my $self = shift;
    my $global = NTPPool::Zone->retrieve_by_name('@');
    my @zones = sort { $a->description cmp $b->description }
      NTPPool::Zone->search(parent => $global);
    push @zones, $global;
    \@zones
}

package NTPPool::Control::Basic;
use base qw(NTPPool::Control Combust::Control::Basic);

package NTPPool::Control::Error;
use base qw(NTPPool::Control Combust::Control::Error);

1;
