package Todoist::API::Role::Task;

use Moo::Role;
use Carp;

use List::Util    qw( first );
use JSON::MaybeXS qw( encode_json );

my $re_num = qr/^[0-9]+$/;

sub tasks_by_id {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $ids = $args->{ids};
    ref $ids eq 'ARRAY'        or return;
    grep { !/$re_num/ } @$ids and return;

    return $self->POST({
        token  => $self->api_token,
        cmd    => 'getItemsById',
        params => { ids => encode_json $ids },
    });
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
        content    => $args->{content},
        project_id => $pid,
        $self->_optional_task_params($args),
    };

    my $add = $self->POST({
        token  => $self->api_token,
        cmd    => 'addItem',
        params => $params
    });

    ref $add and $self->_refresh_project_tasks({ id => $pid });

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

    my $status = $self->POST({
        token       => $self->api_token,
        cmd         => 'deleteItems',
        params      => { ids => encode_json $ids },
        status_only => 1,
    });

    for ( @pnames ) {
        $self->_refresh_project_tasks({ name => $_ });
    }

    return $status;
}

sub update_task {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    exists $args->{id} or return;

    my $params = {
        id      => $args->{id},
      ( content => $args->{content} )x!! $args->{content},
        $self->_optional_task_params($args),
    };

    my $update = $self->POST({
        token  => $self->api_token,
        cmd    => 'updateItem',
        params => $params,
    });

    ref $update and
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

    my $params = {
        project_items => encode_json $from,
        to_project    => $to,
    };

    my $status = $self->POST({
        token       => $self->api_token,
        cmd         => 'moveItems',
        params      => $params,
        status_only => 1,
    });

    if ( $status == 200 ) {
        for ( $to, keys %{ $from } ) {
            $self->_refresh_project_tasks({ id => $_ });
        }
    }

    return $status;
}

sub update_tasks_order {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    my $ids = $args->{item_id_list};
    ref $ids eq 'ARRAY' and @$ids > 0 or return;

    my $params = {
        project_id   => $args->{project_id},
        item_id_list => encode_json $ids,
    };

    my $status = $self->POST({
        token       => $self->api_token,
        cmd         => 'updateOrders',
        params      => $params,
        status_only => 1,
    });

    $status == 200 and
        $self->_refresh_project_tasks({ id => $args->{project_id} });

    return $status;
}

sub update_tasks_recurring_date {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    my $ids = $args->{ids};
    ref $ids eq 'ARRAY' and @$ids > 0 or return;

    my $params = {
        ids     => encode_json $ids,
      ( js_date => $args->{js_date} )x!! $args->{js_date},
    };

    return $self->POST({
        token  => $self->api_token,
        cmd    => 'updateRecurringDate',
        params => $params,
    });
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

    my $status = $self->POST({
        token       => $self->api_token,
        cmd         => $cmd,
        params      => { ids => encode_json $ids },
        status_only => 1,
    });

    $status == 200 and
        $self->_refresh_all_projects_tasks();

    return $status;
}

sub _optional_task_params {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    return (
      ( date_string => $args->{date_string} )x!! $args->{date_string},
      ( priority    => $args->{priority}    )x!! $args->{priority},
      ( indent      => $args->{indent}      )x!! $args->{indent},
      ( item_order  => $args->{item_order}  )x!! $args->{item_order},
    );
}


1;
