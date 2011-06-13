package Brahman::JSONRPC::Handler::Program;
use Mouse;
use JSON ();

extends 'Brahman::JSONRPC::Handler';

sub list {
    my ($self, $ctxt, $args) = @_;

    my $children = $ctxt->children;
    my @programs;
    foreach my $pid (keys %$children) {
        my $name = $children->{$pid};
        my $state_file = File::Spec->catfile( $ctxt->state_dir, "$name.json" );
        my $state = do {
            open my $fh, '<', $state_file or die;
            local $/;
            JSON::decode_json(scalar <$fh>);
        };
        next unless $state;

        push @programs, {
            supervisor => $state,
            name => $name,
        };
    }
    return \@programs;
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