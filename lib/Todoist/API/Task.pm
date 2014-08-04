package Todoist::API::Task;

use Moo;
use Carp;

my @fields = qw/ assigned_by_uid checked children collapsed content date_added
                 date_string due_date due_date_utc has_notifications id indent
                 in_history is_archived is_deleted item_order labels priority
                 project_id responsible_uid sync_id user_id /;

for ( @fields ) {
    has $_ => ( is  => 'rw' );
}


1;
