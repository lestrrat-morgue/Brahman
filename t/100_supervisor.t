use strict;
use Test::More;
use File::Temp ();

use_ok "Brahman::Supervisor";

subtest 'create' => sub {
    my $tempdir = File::Temp::tempdir( CLEANUP => 1 );
    my $config_file = File::Temp->new( SUFFIX => ".ini" );

    my $program = "hoge";
    print $config_file <<EOM;
[program:hoge]
command=$^X -e1

EOM
    $config_file->flush;

    my $supervisor = Brahman::Supervisor->new(
        name => "hoge",
        state_dir => $tempdir,
        config_file => $config_file,
    );
    ok $supervisor;

    $supervisor->run;

    ok -f $supervisor->state_file, "state file exists";

    my $state_json = do {
        open my $fh, '<', $supervisor->state_file
            or die "Failed top open " . $supervisor->state_file . ": $!";
        local $/;
        scalar <$fh>
    };
    if ( ok !$@, "no errors reading state" ) {
        my $state = JSON->new->utf8->decode( $state_json );
        if (isa_ok $state, 'HASH') {
            foreach my $key (qw( pid processes publish_connect publish_listen subscribe_connect subscribe_listen) ) {
                ok exists $state->{$key}, "key $key exists in state";
            }
        }
    }
};

done_testing;