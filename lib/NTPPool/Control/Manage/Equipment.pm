package NTPPool::Control::Manage::Equipment;
use strict;
use base qw(NTPPool::Control::Manage);
use Apache::Constants qw(OK NOT_FOUND);
use Email::Send 'SMTP';
use Sys::Hostname qw(hostname);
use Email::Date qw();

use NP::Model;

sub manage_dispatch {
    my $self = shift;

    return $self->render_form if $self->request->uri =~ m!^/manage/equipment/new$!;

    if ($self->request->uri =~ m!^/manage/equipment/application$!) {
        return $self->render_edit if ($self->request->method eq 'post');
        return $self->render_application($self->req_param('id'))
    }

    return $self->render_admin if $self->request->uri =~ m!^/manage/equipment/admin$!;

    return $self->redirect('/manage/equipment/new') unless @{$self->user->user_equipment_applications};
    return OK, $self->evaluate_template('tpl/equipment.html') if $self->request->uri =~ m!^/manage/equipment/?$!;
    return NOT_FOUND;
}

sub render_form {
    my $self = shift;
    my $ea   = shift;
    $self->tpl_param('ea', $ea) if $ea;
    return OK, $self->evaluate_template('tpl/equipment/form.html');
}

sub render_application {
    my ($self, $id, $mode) = @_;

    return $self->redirect('/manage/equipment') unless $id;

    $mode ||= '';

    my $ea = NP::Model->user_equipment_application->fetch(id => $id);

    return $self->redirect("/manage/equipment") unless $ea and $ea->can_view($self->user);

    $self->tpl_param('ea', $ea);

    return OK, $self->evaluate_template('tpl/equipment/show.html')
      if $mode eq 'show' or !$ea->can_edit($self->user);

    return OK, $self->evaluate_template('tpl/equipment/form.html');
}


sub render_edit {
    my $self = shift;

    my $id = $self->req_param('id');
    $id = 0 if $id and $id eq 'new';

    my $ea = $id ? NP::Model->user_equipment_application->fetch(id => $id) : undef;

    if ($ea) {
        return $self->render_application($ea->id) unless $ea->can_edit($self->user);

        if (my $status = $self->req_param('status_change')) {
            if ($ea->status eq 'New' and $status eq 'Pending') {
                $ea->status($status);
                $ea->save;
            }
        }
        else {
            for my $f (qw(application contact_information)) {
                $ea->$f( $self->req_param($f) || '' );
            }
        }
    }
    else {
        $ea = NP::Model->user_equipment_application->create
          ( user_id   => $self->user->id,
            (map { $_ => ($self->req_param($_) || '')
               } qw(application contact_information)
            )
          );
    }

    unless ($ea->validate) {
        my $errors = $ea->validation_errors;
        $self->tpl_param('errors', $errors);
        return $self->render_form($ea);
    }

    $ea->save;

    return $self->render_application($ea->id, 'show');

}

sub render_admin {
    my $self = shift;
    return $self->redirect("/manage/vendor") unless 
       $self->user->privileges->vendor_admin;

    if (my $id = $self->req_param('id')) {
      my $vz = $id ? NP::Model->vendor_zone->fetch(id => $id) : undef;
      return 404 unless $vz;
    
      if ($self->req_param('show')) {
          return $self->render_zone($id, 'show');
      }
      
      if (my $status = $self->req_param('status_change')) {
          if ($vz->status eq 'Pending' and $status =~ m/^Reject/) {
              $vz->status('Rejected');
              $vz->save;
              $self->tpl_param("msg" => $vz->zone_name . ' rejected');
          }
          elsif ($vz->status =~ m/(Pending|Rejected)/ and $status =~ m/^Approved/) {
              $vz->status('Approved');
              $vz->save;

              $self->tpl_param('vz' => $vz); 

              my $msg = $self->evaluate_template('tpl/vendor/approved_email.txt');
              my $email = Email::Simple->new(ref $msg ? $$msg : $msg); # until we decide what eval_tpl should return :)
              $email->header_set('Message-ID' => join("-", int(rand(1000)), $$, time) . '@' . hostname);
              $email->header_set('Date'       => Email::Date::format_date);
              my $sender = Email::Send->new({ mailer => 'SMTP' });
              $sender->mailer_args([Host => 'localhost']);
              my $return = $sender->send($email);
              warn Data::Dumper->Dump([\$msg, \$email, \$return], [qw(msg amil return)]);

              $self->tpl_param("msg" => $vz->zone_name . ' approved');

          }
      }
    }

    my $pending = NP::Model->vendor_zone->get_vendor_zones
      ( query => [ status => 'Pending' ],
      );
    
    $self->tpl_param(pending_zones => $pending);

    return OK, $self->evaluate_template('tpl/vendor/admin.html');
}

1;
