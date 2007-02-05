package NTPPool::Zone;
use strict;
use base qw(NTPPool::DBI);

__PACKAGE__->set_up_table('zones');
__PACKAGE__->has_a('parent' => 'NTPPool::Zone');
__PACKAGE__->has_many('locations' => 'NTPPool::Location' );
__PACKAGE__->has_many('children'  => 'NTPPool::Zone' => 'parent', { order_by => 'description' });
__PACKAGE__->has_many('servers'   => [ 'NTPPool::Location' => 'server' ]);
__PACKAGE__->has_many('_stats' => 'NTPPool::Zone::Stats', { order_by => 'date' } );

__PACKAGE__->columns(Essential => __PACKAGE__->columns);



