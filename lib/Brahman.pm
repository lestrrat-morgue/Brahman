package Brahman;
our $VERSION = '0.01';

1;

__END__

=head1 SYNOPSIS

    # in your server
    brahmand -c /path/to/config.ini

    # to control
    brahmanctl list 
    brahmanctl kill [$process_id ...]
    brahmanctl activate [$name ... ]
    brahmanctl deactivate [$name ... ]
    branmanctl stop

=cut