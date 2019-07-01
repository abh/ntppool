package NTPPool;

our $VERSION = '3.0';

use NTPPool::Control;
use NTPPool::Control::Basic;
use NTPPool::Control::Scores;
use NTPPool::Control::DNSStatus;
use NTPPool::Control::Manage;
use NTPPool::Control::Vendor;
use NTPPool::Control::Manage::Account;
use NTPPool::Control::Manage::Server;
use NTPPool::Control::Manage::Equipment;
use NTPPool::Control::Zone;
use NTPPool::Control::UserProfile;

use Template::Plugin::Number::Format;

1;
