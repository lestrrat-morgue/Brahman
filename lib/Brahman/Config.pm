package Brahman::Config;
use strict;
use Config::INI::Reader;

our %SEEN;
sub read_file {
    my ($class, $file) = @_;
    local %SEEN = ();
    $class->_read_file_recursive($file);
}

sub _read_file_recursive {
    my ($class, $file) = @_;
    my $config = Config::INI::Reader->read_file( $file );
    $SEEN{ $file }++;

    while ( my $include = delete $config->{include} ) {
        my @incconfig;
        foreach my $incfile (map { glob($_) } split /\s+/, $include->{files}) {
            next if $SEEN{ $incfile }++;

            push @incconfig, $class->read_file( $incfile );
        }
        $config = { %$config, map { %$_ } @incconfig };
    }
    return $config;
}

1;
