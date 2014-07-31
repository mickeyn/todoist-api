package Todoist::Utils;
use parent qw(Exporter);

use Term::ReadKey;

our @EXPORT = qw( read_password );

sub read_password {
    my $pass = _read_password();

    while ( length($pass) < 5 ) {
        warn "password too short!\n";
        $pass = _read_password();
    }

    return $pass;
}

sub _read_password {
    my $pass = '';

    print 'password: ';

    ReadMode('noecho');
    ReadMode('raw');
    ReadMode('cbreak');

    while (1) {
        my $chr;
        1 until defined($chr = ReadKey(-1));
        $chr eq "\n" and last;
        $pass .= $chr;
        print "*";
    }

    ReadMode('restore');

    print "\n";
    return $pass;
}


1;
