package NTPPool::Control::Scores;
use strict;
use base qw(NTPPool::Control);
use NTPPool::Server;
use Apache::Constants qw(OK);

sub render {
  my $self = shift;

  if ($self->request->uri =~ m!^/s/(\d+)!) {
    my ($server) = NTPPool::Server->find_server($1) or return 404;
    return $self->redirect('/scores/' . $server->ip);
  }

  if (my $ip = $self->req_param('ip')) {
      my ($server) = NTPPool::Server->find_server($ip) or return 404;
      return $self->redirect('/scores/' . $server->ip);
  }

  if ($self->request->uri =~ m!^/scores/(.*)!) {
      my $p = $1;
      my ($server) = NTPPool::Server->find_server($p);
      return $self->redirect('/scores/' . $server->ip) unless $p eq $server->ip;
      $self->tpl_param('server' => $server);
  }
  return OK, $self->evaluate_template('tpl/server.html');
}

1;
