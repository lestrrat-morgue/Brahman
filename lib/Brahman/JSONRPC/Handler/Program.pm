package Brahman::JSONRPC::Handler::Program;
use Mouse;

extends 'Brahman::JSONRPC::Handler';

sub list {
    my ($self, $ctxt, $args) = @_;
    my $programs = [ map { +{ %$_ } } values %{ $ctxt->programs } ];
    return $programs;
}

sub activate {
    my ($self, $ctxt, $args) = @_;

    foreach my $name (@$args) {
        if ( my $program = $ctxt->programs->{$name} ) {
            $program->is_active(1);
        }
    }
}

sub deactivate {
    my ($self, $ctxt, $args) = @_;

    foreach my $name (@$args) {
        if ( my $program = $ctxt->programs->{$name} ) {
            $program->is_active(0);
            $program->terminate;
        }
    }
}

sub killproc {
    my ($self, $ctxt, $args) = @_;

    foreach my $pid (@$args) {
        $ctxt->killproc($pid);
    }

    return { "message" => "Sent request to terminate processes" }
}

1;