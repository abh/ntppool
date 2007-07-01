package NTPPool::Control::Static;
use strict;
use Apache::Constants qw(DECLINED);
use base qw(NTPPool::Control::Basic);

sub render {
    my $self = shift;

    my $uri = $self->request->uri;

    if ($uri =~ s!^(/.*)\.v[0-9.]+\.(js|css|gif|png|jpg|ico)$!$1.$2!) {
        my $max_age = 315360000; # ten years
        $self->request->header_out('Expires', HTTP::Date::time2str( time() + $max_age ));
        $self->request->header_out('Cache-Control', "max-age=${max_age},public");
        $self->request->uri($uri);
    }

    $self->SUPER::render(@_);

}


1;
