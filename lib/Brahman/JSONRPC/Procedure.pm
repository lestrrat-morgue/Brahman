package Brahman::JSONRPC::Procedure;
use Mouse;

has $_ => ( is => 'rw' ) for (qw(id method params));

no Mouse;

1;
