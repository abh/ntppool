package NP::Model::AccountSubscription;
use strict;

sub live_subscription {
    my $self = shift;
    return 1 if $self->status =~ m{^(active|incomplete|trialing)$};
    return 0;
}

sub limits_exceeded {
    my $self = shift;
    my $new_devices = shift || 0;

    my $existing_device_count = 0;
    my $existing_zone_count   = 0;
    
    
    my $active_zones = NP::Model->vendor_zone->get_objects(query => [account => $self->account->id, status => ['Approved']]);
    if ($active_zones) {
        map { $existing_device_count += $_->device_count } @$active_zones;
        $existing_zone_count = scalar @$active_zones;
    }

    warn "existing device count: $existing_device_count";
    warn "existing zone count  : $existing_zone_count";

        if ($existing_zone_count + 1 > $self->max_zones) {
        return "too many zones";
    }


    if ($existing_device_count + $new_devices > $self->max_devices) {
        return "Too many devices for the subscription plan";
    }

    return 0;
}


1;
