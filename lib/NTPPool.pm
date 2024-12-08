package NTPPool;

our $VERSION = '2023';

use NTPPool::Control;
use NTPPool::Control::Basic;
use NTPPool::Control::Scores;
use NTPPool::Control::DNSStatus;
use NTPPool::Control::Manage;
use NTPPool::Control::Vendor;
use NTPPool::Control::Manage::Account;
use NTPPool::Control::Manage::Check;
use NTPPool::Control::Manage::Server;
use NTPPool::Control::Manage::Monitor;
use NTPPool::Control::Manage::UserProfile;
use NTPPool::Control::Zone;
use NTPPool::Control::UserProfile;

use Template::Plugin::Number::Format;

1;
