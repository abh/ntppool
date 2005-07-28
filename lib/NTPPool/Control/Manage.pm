package NTPPool::Control::Manage;
use strict;
use base qw(NTPPool::Control);
use NTPPool::Server;
use Apache::Constants qw(OK);

sub render {
  my $self = shift;
  
  if ($self->request->uri =~ m!^/manage/logout!) {
    $self->cookie($NTPPool::Control::cookie_name, 0);
    $self->redirect( $self->bitcard->logout_url( r => $self->config->base_url('ntppool') ));
  }
  
  return $self->login unless $self->user;


  return OK, $self->evaluate_template('tpl/manage.html');
}

1;
