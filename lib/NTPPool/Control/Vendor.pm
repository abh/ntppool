package NTPPool::Control::Vendor;
use strict;
use base qw(NTPPool::Control::Manage);
use NP::Model;
use Apache::Constants qw(OK NOT_FOUND);
use Email::Simple;
use Email::Simple::Creator;
use Sys::Hostname qw(hostname);

sub manage_dispatch {
    my $self = shift;

    return $self->render_form if $self->request->uri =~ m!^/manage/vendor/new$!;

    if ($self->request->uri =~ m!^/manage/vendor/zone$!) {
        return $self->render_edit if ($self->request->method eq 'post');
        return $self->render_zone($self->req_param('id'))
    }

    return $self->render_submit
      if ($self->request->uri =~ m!^/manage/vendor/submit$!
          and $self->request->method eq 'post');

    return $self->redirect('/manage/vendor/new') unless @{$self->user->vendor_zones};
    return OK, $self->evaluate_template('tpl/vendor.html') if $self->request->uri =~ m!^/manage/vendor/?$!;
    return NOT_FOUND;
}

sub render_form {
    my $self = shift;
    my $vz   = shift;
    $self->tpl_param('vz', $vz) if ($vz);
    return OK, $self->evaluate_template('tpl/vendor/form.html');
}

sub render_zone {
    my ($self, $id, $mode) = @_;

    $mode ||= '';

    my $vz = NP::Model->vendor_zone->fetch(id => $id);

    return $self->redirect("/manage/vendor") unless $vz and $vz->can_view($self->user);

    $self->tpl_param('vz', $vz);

    return OK, $self->evaluate_template('tpl/vendor/show.html')
      if $mode eq 'show' or !$vz->can_edit($self->user);

    return OK, $self->evaluate_template('tpl/vendor/form.html');

}

sub render_submit {
    my $self = shift;
    my $id = $self->req_param('id');

    my $vz = $id && NP::Model->vendor_zone->fetch(id => $id);

    return $self->render_zone($vz->id)
      unless $vz->can_edit($self->user) and $vz->status eq 'New';

    unless ($vz->validate) {
        my $errors = $vz->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->render_form($vz);
    }
    
    $vz->status('Pending');
    $vz->save;

    $self->tpl_param('vz', $vz);

    my $msg = $self->evaluate_template('tpl/vendor/submit_email.txt');
    my $email = Email::Simple->new(ref $msg ? $$msg : $msg); # until we decide what eval_tpl should return :)
    $email->header_set('Message-ID' => join("-", int(rand(1000)), $$, time) . '@' . hostname);
    $email->header_set('Date'       => Email::Date::format_date);
    my $return = send SMTP => $email, 'localhost';
    warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg amil return)]);

    return OK, $self->evaluate_template('tpl/vendor/submitted.html');
}



sub render_edit {
    my $self = shift;

    my $id = $self->req_param('id');
    $id = 0 if $id and $id eq 'new';

    my $vz = $id ? NP::Model->vendor_zone->fetch(id => $id) : undef;

    if ($vz) {
        return $self->render_zone($vz->id) unless $vz->can_edit($self->user);
    }

    my $zone_name = lc ($self->req_param('zone_name') || '');
    $zone_name =~ s/[^a-z0-9-]+//g;

    if ($vz) {
        $vz->zone_name($zone_name);
        for my $f (qw(organization_name request_information contact_information device_count)) {
            $vz->$f( $self->req_param($f) || '' );
        }
    }
    else {
        $vz = NP::Model->vendor_zone->create
          ( zone_name => $zone_name,
            user_id   => $self->user->id,
            (map { $_ => ($self->req_param($_) || '')
               } qw(organization_name request_information contact_information device_count)
            )
          );
    }

    unless ($vz->validate) {
        my $errors = $vz->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->render_form($vz);
    }

    $vz->save;

    return $self->render_zone($vz->id, 'show');

}

1;
