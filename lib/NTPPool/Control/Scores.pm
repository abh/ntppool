package NTPPool::Control::Scores;
use strict;
use base qw(NTPPool::Control);
use Apache::Constants qw(OK);

sub render {
  my $self = shift;

  return $self->redirect('/scores/') if ($self->request->uri =~ m!^/s/?$!);

  if ($self->request->uri =~ m!^/s/([^/]+)!) {
    my $server = NTPPool::Server->find_server($1) or return 404;
    return $self->redirect('/scores/' . $server->ip);
  }

  if (my $ip = ($self->req_param('ip') || $self->req_param('server_ip'))) {
      my $server = NTPPool::Server->find_server($ip) or return 404;
      return $self->redirect('/scores/' . $server->ip) if $server;
  }

  if ($self->request->uri =~ m!^/scores/(.+)?!) {
      my $p = $1;
      if ($p) {
          my ($server) = NTPPool::Server->find_server($p);
          return 404 unless $server;
          return $self->redirect('/scores/' . $server->ip) unless $p eq $server->ip;
          return OK, $server->log_scores_csv(500), 'text/plain' if $self->req_param('log');
          $self->tpl_param('server' => $server);
      }
  }
  return OK, $self->evaluate_template('tpl/server.html');
}

1;
