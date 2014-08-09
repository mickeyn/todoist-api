#!perl

use strict;
use warnings;

use Test::More tests => 9;
use Todoist::API;

{
    my $t = Todoist::API->new();
    isa_ok( $t,     'Todoist::API' );
    can_ok( $t,     'ua'           );
    isa_ok( $t->ua, 'HTTP::Tiny'   );
}

{
    my $t = Todoist::API->new(
        username => 'hello',
        password => 'mypass',
    );

    isa_ok( $t, 'Todoist::API'              );
    can_ok( $t, qw<email username password> );

    is(
        $t->email,
        $t->username,
        'Attributes email/username match',
    );
}

{
    my $t = Todoist::API->new( {
        email    => 'hello',
        password => 'mypass',
    } );

    isa_ok( $t, 'Todoist::API'              );
    can_ok( $t, qw<email username password> );

    is(
        $t->email,
        $t->username,
        'Attributes email/username match',
    );
}

