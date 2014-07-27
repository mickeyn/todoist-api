package Todoist::API::Task;

use Moo::Role;

use Carp;
use Try::Tiny;
use List::Util    qw( first );
use JSON::MaybeXS qw( decode_json encode_json );

my $re_num = qr/^[0-9]+$/;

sub tasks_by_id {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $ids = $args->{ids};
    ref $ids eq 'ARRAY'       or return;
    grep { !/$re_num/ } @$ids and return;

    my $result = $self->ua->post_form(
        $self->base_url . "/getItemsById",
        {
            token => $self->token,
            ids   => encode_json $ids,
        }
    );

    my $tasks;
    try   { $tasks = decode_json( $result->{content} ) }
    catch { return };

    return $tasks;
}

sub add_task {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    exists $args->{content} or return;

    my $pid = $args->{project_id};
    if ( ! $pid ) {
        $args->{project_name} ||= 'Inbox';
        $pid = $self->project_name2id( $args->{project_name} );
    }

    my $params = {
        token      => $self->token,
        content    => $args->{content},
        project_id => $pid,
        $self->_optional_task_params($args),
    };

    my $result = $self->ua->post_form(
        $self->base_url . "/addItem",
        $params
    );

    my $add;
    try   { $add = decode_json( $result->{content} ) }
    catch { return +{} };

    $result->{status} == 200 and
        $self->_refresh_project_tasks({ id => $pid });

    return $add->{id};
}

sub delete_task {
    my $self = shift;
    my $id   = shift;

    ( !ref $id and $id =~ /$re_num/ ) or return;

    return $self->delete_tasks([ $id ]);
}

sub delete_tasks {
    my $self = shift;
    my $ids  = shift;

    ( ref $ids eq 'ARRAY' and @$ids > 0 ) or return;

    # find matching pids for later update
    my @pnames;
    for ( @$ids ) {
        my $pname = first { $_ } keys %{ $self->_pname2tasks };
        push @pnames => $pname;
    }

    my $result = $self->ua->post_form(
        $self->base_url . "/deleteItems",
        {
            token => $self->token,
            ids   => encode_json $ids,
        }
    );

    for ( @pnames ) {
        $self->_refresh_project_tasks({ name => $_ });
    }

    return $result->{status};
}

sub update_task {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    exists $args->{id} or return;

    my $params = {
        token => $self->token,
        id    => $args->{id},
      ( content => $args->{content} )x!! $args->{content},
        $self->_optional_task_params($args),
    };

    my $result = $self->ua->post_form(
        $self->base_url . "/updateItem",
        $params
    );

    my $update;
    try   { $update = decode_json( $result->{content} ) }
    catch { return +{} };

    $result->{status} == 200 and
        $self->_refresh_project_tasks({ id => $update->{project_id} });

    return $update->{id};
}

sub move_tasks {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $to   = $args->{to}   || return;
    my $from = $args->{from} || return;

    $to =~ /$re_num/ or $to = $self->project_name2id($to) or return;

    for my $f ( keys %{ $from } ) {
        ref $from->{$f} eq 'ARRAY' or return;
        if ( $f !~ /$re_num/ ) {
            my $k = $self->project_name2id($f) or return;
            $from->{$k} = delete $from->{$f};
        }
    }

    my $result = $self->ua->post_form(
        $self->base_url . "/moveItems",
        {
            token         => $self->token,
            project_items => encode_json $from,
            to_project    => $to,
        }
    );

    if ( $result->{status} == 200 ) {
        for ( $to, keys %{ $from } ) {
            $self->_refresh_project_tasks({ id => $_ });
        }
    }

    return $result->{status};
}

sub update_tasks_order {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    my $ids = $args->{item_id_list};
    ref $ids eq 'ARRAY' and @$ids > 0 or return;

    my $result = $self->ua->post_form(
        $self->base_url . "/updateOrders",
        {
            token        => $self->token,
            project_id   => $args->{project_id},
            item_id_list => encode_json $ids,
        }
    );

    if ( $result->{status} == 200 ) {
        $self->_refresh_project_tasks({ id => $args->{project_id} });
    }

    return $result->{status};
}

sub update_tasks_recurring_date {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $ids = $args->{ids};
    ref $ids eq 'ARRAY' and @$ids > 0 or return;

    my $result = $self->ua->post_form(
        $self->base_url . "/updateRecurringDate",
        {
            token   => $self->token,
            ids     => encode_json $ids,
          ( js_date => $args->{js_date} )x!! $args->{js_date},
        }
    );

    my $update;
    try   { $update = decode_json( $result->{content} ) }
    catch { croak "failed to update recurring date tasks" };

    return $update;
}

sub complete_task {
    my $self = shift;
    my $id   = shift;
    $id =~ /$re_num/ or return;

    return $self->complete_tasks({ ids => [$id] });
}

sub uncomplete_task {
    my $self = shift;
    my $id   = shift;
    $id =~ /$re_num/ or return;

    return $self->uncomplete_tasks({ ids => [$id] });
}

sub complete_tasks {
    return shift->_complete_tasks(@_, 'completeItems');
}

sub uncomplete_tasks {
    return shift->_complete_tasks(@_, 'uncompleteItems');
}

sub _complete_tasks {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $cmd = shift;

    my $ids = $args->{ids};
    ref $ids eq 'ARRAY' or return;

    for ( @$ids ) {
        /$re_num/ or $_ = $self->project_name2id($_) or return;
    }

    my $result = $self->ua->post_form(
        $self->base_url . "/$cmd",
        {
            token => $self->token,
            ids   => encode_json $ids,
        }
    );

    if ( $result->{status} == 200 ) {
        $self->_refresh_all_projects_tasks();
    }

    return $result->{status};
}

sub _optional_task_params {
    my $self = shift;
    my $args = shift;


    return (
      ( date_string => $args->{date_string} )x!! $args->{date_string},
      ( priority    => $args->{priority}    )x!! $args->{priority},
      ( indent      => $args->{indent}      )x!! $args->{indent},
      ( item_order  => $args->{item_order}  )x!! $args->{item_order},
    );
}


1;
