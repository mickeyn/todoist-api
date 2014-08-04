package Todoist::API::User;

use Moo;
use Carp;

BEGIN {
    with qw/ Todoist::API::Role::Account
             Todoist::API::Role::Project
             Todoist::API::Role::Task
             Todoist::API::Role::Premium
           /;
}

has api => (
    is       => 'ro',
    isa      => sub { ref $_[0] eq 'Todoist::API' or croak 'wrong api type' },
    required => 1,
    handles  => [qw/ GET POST /],
);

my @fields = qw/ api_token beta business_account_id date_format default_reminder
                 email full_name has_push_reminders id image_id inbox_project
                 is_biz_admin is_dummy is_premium join_date karma karma_trend
                 last_used_ip mobile_host mobile_number next_week premium_until
                 seq_no shard_id sort_order start_day start_page team_inbox
                 time_format timezone token tz_offset
               /;

for ( @fields ) {
    has $_ => ( is  => 'rw' );
}

1;
