package Todoist::API::Project;

use Moo;
use Carp;

my @fields = qw/ archived_date archived_timestamp cache_count collapsed
                 color id indent is_archived is_deleted item_order last_updated
                 name user_id /;

for ( @fields ) {
    has $_ => ( is  => 'rw' );
}


1;
