package NTPPool::Control::Manage::UserProfile;
use strict;
use NTPPool::Control::Manage;
use NTPPool::Control::UserProfile;

# No methods of its own: the manage-site layout (navigation_sidebar.html)
# calls combust.user_is_staff, combust.monitor_eligibility and
# combust.current_url, which only NTPPool::Control::Manage provides.
use parent qw(NTPPool::Control::UserProfile NTPPool::Control::Manage);

1;
