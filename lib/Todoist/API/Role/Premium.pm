package Todoist::API::Role::Premium;

use Moo::Role;
use Carp;

my $re_num = qr/^[0-9]+$/;

sub archive_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    return $self->GET({
        token  => $self->api_token,
        cmd    => 'archiveProject',
        params => { project_id => $args->{id} },
    });
}

sub unarchive_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    my $id = $args->{id};

    ( $id and $id =~ /$re_num/ ) or return;

    return $self->GET({
        token  => $self->api_token,
        cmd    => 'unarchiveProject',
        params => { project_id => $id },
    });
}

sub get_archived_projects {
    my $self = shift;

    return $self->GET({
        token => $self->api_token,
        cmd   => 'getArchived'
    });
}

sub get_all_completed_tasks {
    my $self = shift;
    my $args = shift;
    $args and ref $args ne 'HASH' and return;

    $self->_project_add_id_if_name($args);

    my $pid       = $args->{project_id};
    my $limit     = $args->{limit};
    my $from_date = $args->{from_date};
    my $js_date   = $args->{js_date};

    my $params = {
      ( from_date  => $from_date )x!! $from_date,
      ( js_date    => $js_date   )x!! $js_date,
      ( project_id => $pid       )x!! ($pid and !ref $pid and $pid =~ /$re_num/),
      ( limit      => $limit     )x!! ($limit and !ref $limit and $limit =~ /$re_num/ ),
    };

    return $self->POST({
        token  => $self->api_token,
        cmd    => 'getAllCompletedItems',
        params => $params,
    });
}


1;
