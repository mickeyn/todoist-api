package Todoist::API::Premium;

use Moo::Role;

use Carp;
use Try::Tiny;
use JSON::MaybeXS qw( decode_json encode_json );

my $re_num = qr/^[0-9]+$/;

sub archive_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    my $result = $self->ua->get(
        sprintf("%s/archiveProject?token=%s&project_id=%d",
                $self->base_url, $self->token, $args->{id})
    );

    my $archived;
    try   { $archived = decode_json $result->{content} }
    catch { croak 'archiving project failed' };

    return $archived;
}

sub unarchive_project {
    my $self = shift;
    my $args = shift;
    ref $args eq 'HASH' or return;

    $self->_project_add_id_if_name($args);

    my $id = $args->{id};

    ( $id and $id =~ /$re_num/ ) or return;

    my $result = $self->ua->get(
        sprintf("%s/unarchiveProject?token=%s&project_id=%d",
                $self->base_url, $self->token, $id)
    );

    my $archived;
    try   { $archived = decode_json $result->{content} }
    catch { croak 'archiving project failed' };

    return $archived;
}

sub get_archived_projects {
    my $self = shift;

    my $result = $self->ua->get(
        $self->base_url . "/getArchived?token=" . $self->token
    );

    my $archived;
    try   { $archived = decode_json $result->{content} }
    catch { croak 'getting archived projects failed' };

    return $archived;
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

    my $result = $self->ua->post_form(
        $self->base_url . "/getAllCompletedItems",
        {
            token      => $self->token,
          ( from_date  => $from_date )x!! $from_date,
          ( js_date    => $js_date   )x!! $js_date,
          ( project_id => $pid       )x!! ($pid and !ref $pid and $pid =~ /$re_num/),
          ( limit      => $limit     )x!! ($limit and !ref $limit and $limit =~ /$re_num/ ),
        }
    );

    my $completed;
    try   { $completed = decode_json( $result->{content} ) }
    catch { croak 'failed to get all completed tasks'      };

    return $completed;
}

1;
