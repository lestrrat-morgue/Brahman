package Brahman::JSONRPC::Handler;
use Mouse;

sub execute {
    my ($self, $ctxt, $action, $procedure, @args) = @_;
    $self->$action( $ctxt, $procedure->params, $procedure, @args );
}

1;