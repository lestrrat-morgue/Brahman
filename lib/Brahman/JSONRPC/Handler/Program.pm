package Brahman::JSONRPC::Handler::Program;
use Mouse;

extends 'Brahman::JSONRPC::Handler';

sub list {
    my ($self, $ctxt, $args) = @_;
    my $programs = [ map { +{ %$_ } } values %{ $ctxt->programs } ];
    return $programs;
}

sub killproc {
    my ($self, $ctxt, $args) = @_;

    foreach my $pid (@$args) {
        $ctxt->killproc($pid);
    }

    return { "message" => "Sent request to terminate processes" }
}

1;