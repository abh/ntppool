package NTPPool::Control::Scores;
use strict;
use base qw(NTPPool::Control);
use NTPPool::Server;
use Apache::Constants qw(OK);

sub render {
  my $self = shift;
  my $ip = $self->req_param('ip');
  if ($ip) {
    my ($server) = NTPPool::Server->find_server($ip) or return 404;
    $self->tpl_param('server' => $server);
  }


  return OK, $self->evaluate_template('tpl/server.html');

}

1;
