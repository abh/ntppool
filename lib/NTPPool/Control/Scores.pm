package NTPPool::Control::Scores;
use strict;
use base qw(NTPPool::Control);
use Combust::Constant qw(OK DECLINED);
use Combust::Gearman::Client ();
use NP::Model;
use Imager ();
use List::Util qw(min);

BEGIN {
  die "Imager module needs to be compiled with png support"
      unless grep { $_ eq 'png' } Imager->write_types;
}

my $gearman = Combust::Gearman::Client->new;

sub render {
  my $self = shift;

  $self->cache_control('s-maxage=1800');

  return $self->redirect('/scores/') if ($self->request->uri =~ m!^/s/?$!);

  if ($self->request->uri =~ m!^/s/([^/]+)!) {
    my $server = NP::Model->server->find_server($1) or return 404;
    $self->cache_control('max-age=14400, s-maxage=7200');
    return $self->redirect('/scores/' . $server->ip);
  }

  if (my ($id, $mode) = ($self->request->uri =~ m!^/scores/graph/(\d+)-(score|offset).png!)) {
    my $server = NP::Model->server->find_server($id) or return 404;
    $self->cache_control('max-age=14400, s-maxage=7200');
    return $self->redirect('/scores/' . $server->ip . "/graph/${mode}.png");
  }

  if (my $ip = ($self->req_param('ip') || $self->req_param('server_ip'))) {
      my $server = NP::Model->server->find_server($ip) or return 404;
      return $self->redirect('/scores/' . $server->ip) if $server;
  }

  if (my ($p, $mode) = $self->request->uri =~ m!^/scores/([^/]+)(?:/(\w+))?!) {
      $mode ||= '';
      if ($p) {
          my ($server) = NP::Model->server->find_server($p);
          return 404 unless $server;
          return $self->redirect('/scores/' . $server->ip) unless $p eq $server->ip;

          if ($mode eq 'log' or $self->req_param('log')) {
              my $limit = $self->req_param('limit') || 0;
              $limit = 50 unless $limit and $limit !~ m/\D/;
              $limit = 5000 if $limit > 5000;
              return OK, $server->log_scores_csv($limit), 'text/plain';
          }
          elsif ($mode eq 'rrd') {
              # TODO: check that rrd is up-to-date
              my $path = $server->rrd_path;
              open my $fh, $path or warn "Could not open $path: $!" and return 403;
              $self->request->header_out('Content-disposition', sprintf('attachment; filename=%s.rrd', $server->ip));
              $self->request->update_mtime((stat($fh))[9]);
              return OK, $fh, 'application/octet-stream';
          }
          elsif ($mode eq 'graph') {
            my ($type) = ($self->request->uri =~ m{/(offset|score)\.png$});
            eval {
                $gearman->do_task('update_graphs', $server->id,
                    {uniq => 'graphs-' . $server->id});
            };
            my $ttl = $@ ? 10 : 1800;
            my $path = $server->graph_path($type);
            open my $fh, $path
              or warn "Could not open $path: $!" and return 403;

            my $mtime = (stat($fh))[9];
            $self->request->update_mtime($mtime);

            $self->cache_control('max-age=2700, s-maxage=1800');
            return OK, $fh, 'image/png';
          }
          elsif ($mode eq 'spark') {
              return OK, $self->history_sparkline_png($server), 'image/png';
          }
          elsif ($mode eq '') {
              $self->tpl_param('graph_explanation' => 1) if $self->req_param('graph_explanation');
              $self->tpl_param('server' => $server);
          }
          else {
              return $self->redirect('/scores/' . $server->ip);
          }
      }
  }
  return OK, $self->evaluate_template('tpl/server.html');
}

sub history_sparkline_png {
    my ($self, $server) = @_;

    $self->cache_control('s-maxage=5400');

    my $width  = 160;
    my $height = 64;

    my $history = $server->history(80);
    my @d;
    
    # @d = (0,1,2.1,3.2,4.4,5.5,7,8.5,10,11.5,13,15,16,11,6,1,-4,-3,-2,-1);

    @$history = reverse @$history;

    my $score_count = @$history;

    my $min = min(-5,map { $_->score } @$history);

    $score_count ||= 1;

    my $x_scale = $width / $score_count;
    my $left_x = 0 + ($width - $score_count * $x_scale);

    my $y_scale = $height / (20 - $min);

    my $img = Imager->new(xsize => $width, ysize => $height);
    $img->box(color => [255,255,255], filled => 1);

    $img->line(color => [192,192,192],
               x1 => 0,
               x2 => $width,
               y1 => 15 * $y_scale,
               y2 => 15 * $y_scale, 
               aa => 1,
               endp => 0, 
              );

    my $left_h = shift @$history;
    my $left_y = $y_scale * ($left_h ? _calc_y($left_h) : 1);

    for my $h (@$history) {

        my $y = $y_scale * _calc_y($h);
        my $x = $left_x + $x_scale;

        my $colors = [ [0,180,0], 'green' ];
        $colors = [ [0, 128,128], 'yellow' ] if $h->step < .5;
        $colors = [ [180, 0,0 ], 'red' ]     if $h->step < -0.5;

        $img->line(color => $colors->[0],
                   x1 => $left_x,
                   x2 => $x,
                   y1 => $left_y,
                   y2 => $y, 
                   aa => 1,
                   endp => 0 );

        $img->setpixel(x => $x, y => $y, color => $colors->[1]);

        $left_h = $h;
        $left_x = $x;
        $left_y = $y;
    }

    my $output;
    $img->scale(scalefactor => .25)->
          filter(type=>'autolevels', usat => 0.001, lsat => 0.001)->
          write(data => \$output, type => 'png');

    return $output;

}

sub _calc_y {
    my $h = shift;
    (($h->score - 20) * -1) + 1;
}


1;
