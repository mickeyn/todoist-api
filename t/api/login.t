#!perl

use strict;
use warnings;

use Test::More tests => 27;
use Test::Fatal;
use Todoist::API;

{
    no warnings qw<redefine once>;
    sub Todoist::API::User::new {
        my ( $self, $args ) = @_;
        isa_ok( $self, 'Todoist::API::User' );
        isa_ok( $args, 'HASH'               );

        my $api = delete $args->{'api'};
        isa_ok( $api, 'Todoist::API' );

        is_deeply(
            $args,
            { hello => 'world' },
            'Correct parameters to ::User::new',
        );
    }
}

{
    no warnings qw<redefine once>;
    *Todoist::API::POST = sub {
        my $self = shift;
        my $args = shift;

        is_deeply(
            $args,
            {
                cmd    => 'login',
                params => {
                    email    => 'myemail',
                    password => 'mypass',
                },
            },
            'Correct parameters to POST',
        );

        return { hello => 'world' };
    };
}

{
    my $t = Todoist::API->new();
    isa_ok( $t, 'Todoist::API' );
    can_ok( $t, 'login'        );

    like(
        exception { $t->login },
        qr{^Missing username/email and/or password},
        'Missing username/password for login',
    );
}

{

    my $t = Todoist::API->new(
        email => 'myemail', password => 'mypass'
    );

    isa_ok( $t, 'Todoist::API' );
    can_ok( $t, 'login'        );

    is(
        exception { $t->login },
        undef,
        'Login successful with email/password attrs',
    );
}

{

    my $t = Todoist::API->new(
        username => 'myemail', password => 'mypass'
    );

    isa_ok( $t, 'Todoist::API' );
    can_ok( $t, 'login'        );

    is(
        exception { $t->login },
        undef,
        'Login successful with username/password attrs',
    );
}

{

    my $t = Todoist::API->new();

    isa_ok( $t, 'Todoist::API' );
    can_ok( $t, '_login'       );

    is(
        exception {
            $t->_login( 'myemail', 'mypass' )
        },
        undef,
        'Login successful with email/password arguments',
    );
}

