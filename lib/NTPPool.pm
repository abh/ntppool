package NTPPool;

our $VERSION = '2.00';

use NTPPool::Control;
use NTPPool::Control::Basic;
use NTPPool::Control::Scores;
use NTPPool::Control::DNSStatus;
use NTPPool::Control::Manage;
use NTPPool::Control::Vendor;
use NTPPool::Control::Manage::Equipment;
use NTPPool::Control::Zone;
use NTPPool::Control::UserProfile;
use NTPPool::Control::LanguagePath;

use Template::Plugin::Number::Format;

1;
