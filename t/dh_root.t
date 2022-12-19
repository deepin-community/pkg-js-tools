use Test::More tests => 8;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir 't/root';
spawn( exec => ['dh_prep'], wait_child => 1 );
spawn( exec => [ 'dh_auto_install', '--buildsystem=nodejs' ], wait_child => 1 );

for my $c ('comp_two') {
    ok( !-d "debian/foo/usr/share/nodejs/foo/node_modules/$c",
        "$c is not installed as sub module" );
    ok( -d "debian/foo/usr/share/nodejs/$c", "$c is installed as root module" );
}
for my $c ( 'comp-one', 'comp-three' ) {
    ok( -d "debian/foo/usr/share/nodejs/foo/node_modules/$c",
        "$c is installed as sub module" );
    ok(
        !-d "debian/foo/usr/share/nodejs/$c",
        "$c is not installed as root module"
    );
}

spawn( exec => [ 'fakeroot', 'dh_gencontrol' ], wait_child => 1 );
if ( ok( -e 'debian/foo/DEBIAN/control', 'control generated' ) ) {
    my $f;
    open $f, 'debian/foo/DEBIAN/control';
    ok( grep { /Provides: node-comp-two \(= 0.1\)/ } <$f>, 'Provides field' )
      or diag "control content\n" . `cat debian/foo/DEBIAN/control`;
}

spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'], wait_child => 1 );
chdir $pwd;
