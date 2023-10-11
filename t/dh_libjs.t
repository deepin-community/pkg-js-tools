use Test::More tests => 6;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/libjs";
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');
spawn(
    exec       => [ 'fakeroot', 'dh_auto_install', '--buildsystem=nodejs' ],
    wait_child => 1
);
spawn( exec => [ 'fakeroot', 'dh_install' ], wait_child => 1 );

foreach (
    qw(
    debian/node-foo/usr/share/nodejs/foo/package.json
    debian/node-foo/usr/share/nodejs/foo/index.js
    debian/node-foo/usr/share/nodejs/foo/node_modules/comp-one/package.json
    debian/node-foo/usr/share/nodejs/foo/node_modules/comp-one/index.js
    debian/libjs-foo/usr/share/javascript/foo/index.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}

spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
chdir $pwd;
