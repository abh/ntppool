package NTPPool::Control::Basic;
use base qw(NTPPool::Control Combust::Control::Basic);

sub init {
    my $self = shift;
    return 200 if $self->request->path =~ m!^/static!;
    return $self->SUPER::init(@_);
}

sub render {
    my $self = shift;

    if ($self->request->path =~ m!^/static/(js|css)!) {
        $self->request->header_out('Access-Control-Allow-Origin' => '*');
    }

    if ($self->request->path =~ m!^/manage! and $self->site ne 'manage') {
        return $self->redirect($self->manage_url($self->request->path));
    }

    if ($self->request->uri =~ m!^/robots.txt$!) {
        $self->force_template_processing(1);
    }
    else {
        my @r = $self->localize_url;
        if (@r) {
            $self->set_span_name("localize redirect");
            return @r;
        }
    }

    $self->cache_control('s-maxage=1800,max-age=3600');

    return $self->SUPER::render(@_);
}

sub servers_with_urls {
    my $self = shift;

    # local $Rose::DB::Object::Debug = $Rose::DB::Object::Manager::Debug = 1;

    my $servers = NP::Model->server->get_servers(
        query => [
            or => [
                'in_pool'        => 1,
                'in_server_list' => 1,
            ],
            'deletion_on' => undef,
            'score_raw'   => {gt => 0},
        ],
        require_objects => ['server_urls'],
        sort_by         => 'id',
    );
    $servers;
}

1;
