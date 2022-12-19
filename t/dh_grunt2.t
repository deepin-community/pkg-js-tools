use Test::More tests => 3;
use Dpkg::IPC;

SKIP: {
    unless ( -x '/usr/bin/grunt' ) {
        skip "grunt is not installed", 3;
    }
    my $pwd = `pwd`;
    chdir "t/grunt2";
    spawn( exec => ['dh_clean'], wait_child => 1 );
    spawn(
        exec       => [ 'dh_auto_configure', '--buildsystem=nodejs' ],
        wait_child => 1
    );
    spawn(
        exec       => [ 'dh_auto_build', '--buildsystem=nodejs' ],
        wait_child => 1
    );
    foreach (qw(dist/index.js)) {
        ok( -f $_, "build creates $_" );
    }
    spawn(
        exec       => [ 'dh_auto_install', '--buildsystem=nodejs' ],
        wait_child => 1
    );
    foreach (
        qw(
        debian/foo/usr/share/nodejs/foo/package.json
        debian/foo/usr/share/nodejs/foo/dist/index.js
        )
      )
    {
        ok( -f $_, "$_ installed" );
    }
    spawn(
        exec       => [ 'dh_auto_clean', '--buildsystem=nodejs' ],
        wait_child => 1
    );
    spawn( exec => ['dh_clean'], wait_child => 1 );
    chdir $pwd;
}
