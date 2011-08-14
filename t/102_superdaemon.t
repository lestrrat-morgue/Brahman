use strict;
use Test::More;
use AnyEvent;
use File::Temp ();
use_ok "Brahman::Superdaemon";

subtest 'basic' => sub {
    my $state_dir = File::Temp::tempdir( CLEANUP => 1 );
    my $config_file = File::Temp->new( SUFFIX => ".ini" );
    my $program = "hoge";
    print $config_file <<EOM;
[program:$program]
command=$^X -e1

EOM
    $config_file->flush;

    my $cv = AE::cv;

    # create a timer that will fail this test, if triggered.
    # this avoid a deadlocked test
    my $t = AE::timer 10, 0, sub {
        fail( "Timeout reached" );
        $cv->send;
    };

    # I want triggers for testing, so do some MOP hackary
    my $sdclass = Mouse::Meta::Class->create(
        undef,
        superclasses => [ 'Brahman::Superdaemon' ],
    );
    $sdclass->add_after_method_modifier( register_supervisor => sub {
        $cv->end;
    } );

    my $superdaemon = $sdclass->new_object(
        state_dir => $state_dir,
        config_file => $config_file,
    );
    ok $superdaemon;

    $cv->begin;
    $superdaemon->run;

    $cv->cb( sub { $superdaemon->stop } );
    $cv->recv;

    my $children = $superdaemon->children;
    is scalar keys %$children, 1;
    is ( (values %$children)[0], "hoge", "hoge exists" );

    $superdaemon->stop;
};

done_testing;

