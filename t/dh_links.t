use Test::More tests => 9;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/links";

# Test if debian/build_modules are created
spawn(
    exec       => [ 'dh_auto_configure', '--buildsystem=nodejs' ],
    wait_child => 1
);
foreach (qw(@a/a b)) {
    ok( -l "node_modules/$_", "Link node_modules/$_" );
}
ok( readlink 'node_modules/@a/a' eq '../../debian/build_modules/@a/a',
    'Link node_modules/@a/a is good' );
ok( readlink 'node_modules/b' eq '../debian/build_modules/b',
    'Link node_modules/b is good' );
foreach (qw(@a/b c)) {
    ok( !-l "node_modules/$_", "No link to node_modules/$_" );
}

# Test if debian/tests/test_modules are created
# (link test is done during test)
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
foreach (qw(@a/b c)) {
    ok( !-l "node_modules/$_",
        "Link to node_modules/$_ was removed after test" );
}
spawn(
    exec       => [ 'dh_auto_clean', '--buildsystem=nodejs' ],
    wait_child => 1
);
spawn( exec => ['dh_clean'], wait_child => 1 );
ok( !-d 'node_modules', 'node_modules is removed' )
  or diag( "node_modules content:\n" . `ls -alR node_modules` );
chdir $pwd;
