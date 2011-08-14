use strict;
use Test::More;

use_ok "Brahman::Program";

subtest 'basic' => sub {
    my $program = Brahman::Program->new(
        name => "hoge",
        command => $^X,
    );
    ok $program;

    ok $program->want_start(0), "0 should start";
    ok ! $program->want_start( $program->numprocs ), "numprocs should not start";

    $program->is_active(0);
    ok ! $program->want_start(0), "0 should not start when inactive";
    ok ! $program->want_start( $program->numprocs ), "numprocs should not start when inactive";

};

done_testing;