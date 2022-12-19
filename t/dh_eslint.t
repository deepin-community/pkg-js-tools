use Test::More tests => 10;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/eslint";
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');
spawn( exec => [ 'dh_auto_install', '--buildsystem=nodejs' ], wait_child => 1 );
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/lib/index.js
    debian/foo/usr/share/nodejs/foo/lib/a/index.js
    debian/foo/usr/share/nodejs/foo/lib/b/index.js
    debian/foo/usr/share/nodejs/foo/lib/b/.eslintrc.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/Makefile
    debian/foo/usr/share/nodejs/foo/lib/.eslintrc.js
    debian/foo/usr/share/nodejs/foo/lib/Makefile
    debian/foo/usr/share/nodejs/foo/lib/a/.eslintrc.js
    )
  )
{
    ok( !-f $_, "$_ not installed" );
}
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'], wait_child => 1 );
chdir $pwd;
