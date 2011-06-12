package Brahman::JSONRPC::Handler::Daemon;
use Mouse;

extends 'Brahman::JSONRPC::Handler';

sub stop {
    my ($self, $ctxt, $args) = @_;

    $ctxt->stop;

    return { message => "Sent stop request" }
}

1;