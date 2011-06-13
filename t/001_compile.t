use strict;
use Test::More;
use File::Find;

my $dir = "lib";
find( {
    no_chdir => 1,
    wanted   => sub {
        my $file = $File::Find::name;
        return 1 unless -f $file;

        $file =~ s/$dir\/?//;
        $file =~ s/\//::/g;
        $file =~ s/\.pm$//;
        use_ok $file;
    }
}, $dir );

done_testing;
