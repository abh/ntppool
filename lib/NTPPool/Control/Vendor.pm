package NTPPool::Control::Vendor;
use strict;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Apache::Constants qw(OK NOT_FOUND);

sub manage_dispatch {
    my $self = shift;

    return $self->render_form   if $self->request->uri =~ m!^/manage/vendor/new$!;

    return $self->redirect('/manage/vendor/new') unless @{$self->user->vendor_zones};
    
    return OK, $self->evaluate_template('tpl/vendor.html') if $self->request->uri =~ m!^/manage/vendor/?$!;
    return NOT_FOUND;
}

sub render_form {
    my $self = shift;

    return OK, $self->evaluate_template('tpl/vendor/form.html');
    
}

1;
