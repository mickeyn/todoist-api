package Todoist::Utils;
use parent qw(Exporter);

use Term::ReadKey;

our @EXPORT = qw( read_password );

sub read_password {
    my $pass = '';

    print 'password: ';

    ReadMode('noecho');
    ReadMode('raw');

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
