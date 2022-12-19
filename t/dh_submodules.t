use Test::More tests => 24;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/submodules";

# Configure step
spawn(
    exec       => [ 'dh_auto_configure', '--buildsystem=nodejs' ],
    wait_child => 1
);
ok( !-l 'node_modules/comp-one',                        'comp-one/nolink' );
ok( -l 'node_modules/comp_two',                         'Main link' );
ok( readlink('node_modules/comp_two') eq '../comp-two', ' good link' )
  or diag "Expect: ../comp-two\nGet: " . readlink('node_modules/comp_two');
ok( -l 'node_modules/comp-three',                           'Main link' );
ok( -l 'comp-three/node_modules/comp_two',                  'component_links' );
ok( readlink('node_modules/comp-three') eq '../comp-three', ' good link' )
  or diag "Expect: ../comp-three\nGet: " . readlink('node_modules/comp-three');

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
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/index.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/package.json
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/index.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp_two/package.json
    debian/foo/usr/share/nodejs/foo/node_modules/comp_two/index.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp-three/index.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp-three/package.json
    debian/foo/usr/share/nodejs/foo/node_modules/comp-three/test.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp-four/package.json
    debian/foo/usr/share/nodejs/foo/node_modules/comp-four/index.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
foreach (qw(one two four)) {
    open my $f, "debian/foo/usr/share/nodejs/foo/node_modules/comp-$_/index.js" or next;
    my $line = <$f>;
    ok($line =~ /$_/, "index.js is good") or diag "$_: $line";
    close $f;
}
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/node_modules/comp-one/test.js
    debian/foo/usr/share/nodejs/foo/node_modules/comp_two/tests.js
    )
  )
{
    ok( !-f $_, "$_ not installed" );
}
mkdir 'node_modules/.cache';
open F, '>', 'node_modules/.cache/foo';
print F 'z';
close F;

spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'], wait_child => 1 );
ok( ( !-e 'node_modules/.cache/foo' and !-e 'node_modules/.cache' ),
    'Cache deleted' );
chdir $pwd;
