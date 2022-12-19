use Test::More tests => 19;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/only_components";

# Configure step
spawn(
    exec       => [ 'dh_auto_configure', '--buildsystem=nodejs' ],
    wait_child => 1
);
ok( !-l 'node_modules/comp-one', 'comp-one/nolink' );
ok( -l 'node_modules/comp_two',  'Main link' );
ok( readlink('node_modules/comp_two') eq '../packages/comp-two', ' good link' );
ok( -l 'node_modules/comp-three',                                'Main link' );
ok( -l 'packages/comp-three/node_modules/comp_two', 'component_links' );
ok(
    readlink('packages/comp-three/node_modules/comp_two') eq
      '../../../packages/comp-two',
    ' good link'
);

# Build step
spawn( exec => [ 'dh_auto_build', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'comp-one/a', 'build creates comp-one/a' );
unlink 'comp-one/a';

# Test step
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');

# Install step
spawn( exec => [ 'dh_auto_install', '--buildsystem=nodejs' ], wait_child => 1 );
unlink('comp-one/bar');

foreach (
    qw(
    debian/foo/usr/share/nodejs/comp-one/package.json
    debian/foo/usr/share/nodejs/comp-one/index.js
    debian/foo/usr/share/nodejs/comp_two/package.json
    debian/foo/usr/share/nodejs/comp_two/index.js
    debian/foo/usr/share/nodejs/comp-three/index.js
    debian/foo/usr/share/nodejs/comp-three/package.json
    debian/foo/usr/share/nodejs/comp-three/test.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/index.js
    debian/foo/usr/share/nodejs/comp-one/test.js
    debian/foo/usr/share/nodejs/comp_two/tests.js
    )
  )
{
    ok( !-f $_, "$_ not installed" );
}

spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'], wait_child => 1 );
chdir $pwd;
