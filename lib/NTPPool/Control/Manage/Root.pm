package NTPPool::Control::Manage::Root;
use strict;
use base qw(NTPPool::Control::Manage);
use Combust::Constant qw(OK NOT_FOUND);

sub render {
    my $self = shift;
    if ($self->request->path eq '/') {
        return $self->redirect('/manage');
    }
    return NOT_FOUND;
}

1;
