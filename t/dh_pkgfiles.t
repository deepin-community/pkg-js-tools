use Test::More tests => 11;
use Dpkg::IPC;

my $pwd = `pwd`;
chdir "t/pkgfiles";
spawn( exec => [ 'dh_auto_test', '--buildsystem=nodejs' ], wait_child => 1 );
ok( -e 'foo', 'File "foo" created' ) or diag `ls -l`;
unlink('foo');
spawn(
    exec       => [ 'fakeroot', 'dh_auto_install', '--buildsystem=nodejs' ],
    wait_child => 1
);

foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/package.json
    debian/foo/usr/share/nodejs/foo/index.js
    )
  )
{
    ok( -f $_, "$_ installed" );
}
foreach (
    qw(
    debian/foo/usr/share/nodejs/foo/Changelog.txt
    debian/foo/usr/share/nodejs/foo/copying
    debian/foo/usr/share/nodejs/foo/LICENSE
    debian/foo/usr/share/nodejs/foo/README.md
    debian/foo/usr/share/nodejs/foo/.prettierrc.js
    debian/foo/usr/share/nodejs/foo/dontinstall.js
    debian/foo/usr/share/nodejs/foo/bad1.js
    debian/foo/usr/share/nodejs/foo/bad2.js
    )
  )
{
    ok( !-f $_, "$_ not installed" );
}
spawn( exec => [ 'dh_auto_clean', '--buildsystem=nodejs' ], wait_child => 1 );
spawn( exec => ['dh_clean'],                                wait_child => 1 );
chdir $pwd;
