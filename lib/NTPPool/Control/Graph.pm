package NTPPool::Control::Graph;
use strict;
use parent            qw(NTPPool::Control);
use Combust::Constant qw(OK DECLINED);
use NP::Model;
use LWP::UserAgent qw();

my $ua = LWP::UserAgent->new(
    ssl_opts => {
        SSL_verify_mode => 0x02,
        SSL_ca_file     => Mozilla::CA::SSL_ca_file()
    }
);

sub render {
    my $self = shift;

#    $self->set_span_name("graph");

    $self->cache_control('s-maxage=1800');

    my ($p, $type) = ($self->request->uri =~ m!^/graph/([^/]+)/(\w+).png!);

    # people breaking the varnish cache by adding query parameters
    if (keys %{$self->request->query_parameters}) {
        return $self->redirect($self->request->uri, 301);
    }

    return 404 unless $type and $type =~ m!^(offset|score)$!;

    my ($server) = $p && NP::Model->server->find_server($p);
    return 404 unless $server;
    return 404 if $server->deleted;

    # we only have one graph type now
    $type = 'offset';

    return $self->redirect('/graph/' . $server->ip . "/$type", 301)
      unless $p eq $server->ip;

    my $graph = eval { get_graph($server) };
    my $err   = $@ || !$graph;
    warn "update_graphs error: $err" if $err;
    my $ttl = $err || length($graph) == 0 ? 15 : 1800;

    my $mtime = time;
    $self->request->update_mtime($mtime);

    $self->cache_control(sprintf('max-age=%i, s-maxage=%i', $ttl, $ttl * 0.75));

    if ($err) {
        return 500, "Server error\n", "text/plain";
    }

    return OK, $graph, 'image/png';
}

sub get_graph {
    my $server = shift;
    my $url    = URI->new(Combust::Config->new->base_url('ntppool'));

    # if the site doesn't require TLS and can't be reached
    # from inside kubernetes on the external hostname, this might
    # work.
    # my $url = URI->new("http://web/");
    $url->path($server->url);
    $url->query_form(graph_only => 1);

    # my $data = JSON::encode_json(
    #     {   url              => $url->as_string(),
    #         timeout          => 10,
    #         viewport         => "501x233",
    #         height           => 233,
    #         resource_timeout => 5,
    #         wait             => 0.5,
    #         scale_method     => "vector",
    #     }
    # );

    my $screensnap = $ENV{screensnap_service} || 'screensnap';
    my $resp       = $ua->get(
        "http://${screensnap}/image/offset/" . $server->ip,

        # "Content-Type" => "application/json",
        # Content        => $data,
    );

    unless ($resp->is_success) {
        warn "could not get splash render: ", $resp->code;
        warn "resp: ",                        $resp->decoded_content();
        return undef;
    }
    return $resp->decoded_content();
}

1;
