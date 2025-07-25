package NTPPool::Control::Basic;
use parent            qw(NTPPool::Control Combust::Control::Basic);
use Combust::Constant qw(OK NOT_FOUND);
use HTTP::Date;

sub init {
    my $self = shift;
    return 200 if $self->request->path =~ m!^/static!;
    return $self->SUPER::init(@_);
}

sub render {
    my $self = shift;

    # avoid "no providers for template prefix 'xx'" error
    if ($self->request->path =~ m!^/[^/]+:!) {
        return NOT_FOUND;
    }

    if ($self->request->path =~ m!^/static/(js|css|build)!) {
        $self->request->header_out('Access-Control-Allow-Origin' => '*');
        $self->request->header_out('Vary', 'Origin');
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

    # Only set cache headers if not already set by fixup_static_version
    unless ($self->cache_control) {
        if ($self->request->uri =~ m{\.v[0-9a-zA-Z._-]+\.(css|js|gif|png|jpg|png|ico)$}) {
            $self->cache_control('s-maxage=1209600,max-age=31536000');
        }
        else {
            $self->cache_control('s-maxage=1800,max-age=3600');
        }
    }

    return $self->SUPER::render(@_);
}

sub fixup_static_version {
    my $self = shift;
    my $uri  = $self->request->path;

    warn "DEBUG: fixup_static_version called with URI: '$uri'\n";

    # Check if this is a versioned file in the build directory
    if ($uri =~ m!^/static/build/.*\.v[0-9a-zA-Z._-]+\.(js|css|gif|png|jpg|svg|htc|ico)$!)
    {
        warn "DEBUG: Matched build directory versioned file pattern\n";

        # Check if the versioned file exists on disk
        my $file = $uri;
        substr($file, 0, 1) = "";    # trim leading slash
        my $data = $self->tt->provider->expand_filename($file);

        warn "DEBUG: Looking for file: '$file'\n";

        my $include_paths = $self->get_include_path;
        warn "DEBUG: Include paths: " . join(", ", @$include_paths) . "\n";

        warn "DEBUG: Template provider result: "
          . ($data->{path} ? "found at '$data->{path}'" : "not found") . "\n";

        # Also check if file exists directly on filesystem
        my $full_path   = "docs/shared/$file";
        my $file_exists = -f $full_path;
        warn "DEBUG: Direct filesystem check '$full_path': "
          . ($file_exists ? "exists" : "not found") . "\n";

        if ($data->{path}) {
            warn "DEBUG: File found via template provider, setting 10-year cache\n";

            # Versioned file exists, keep the version and set cache headers
            $self->cache_control('s-maxage=1209600,max-age=31536000');

            # You can add application-specific logic here based on the versioned filename
            return;
        }
        else {
            warn
              "DEBUG: File not found via template provider, stripping version and setting 10-minute cache\n";

            # Versioned file doesn't exist in build directory
            # Strip version ourselves and use short cache time
            if ($uri
                =~ s!^(/.*)\.v[0-9a-zA-Z._-]+\.(js|css|gif|png|jpg|svg|htc|ico)$!$1.$2!)
            {
                warn "DEBUG: Stripped version from URI, new path: '$uri'\n";
                $self->request->path($uri);

                # Set short cache headers (10 minutes instead of 10 years)
                $self->cache_control('s-maxage=600,max-age=600');
            }
            return;
        }
    }

    warn "DEBUG: Not a build directory versioned file, calling parent\n";

    # Fall back to parent's behavior for all other cases
    return $self->SUPER::fixup_static_version(@_);
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
