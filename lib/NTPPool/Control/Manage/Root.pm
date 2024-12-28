package NTPPool::Control::Manage::Root;
use strict;
use Combust::Constant qw(OK NOT_FOUND);

# Be a simpler "Basic" controller than the main website one
# to let manage be it's own templated site
use base qw(NTPPool::Control NTPPool::Control::Manage Combust::Control::Basic);

sub render {
    my $self = shift;

    if ($self->request->path eq '/') {

        # manage controller, login page
        $self->cache_control('private');
        return $self->SUPER::render(@_);
    }

    if ($self->is_logged_in) {
        $self->cache_control('private');
    }
    return NOT_FOUND;
}

1;
