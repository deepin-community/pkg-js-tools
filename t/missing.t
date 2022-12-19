use Test::More tests => 1;
use Test::Output;
use File::Temp 'tempdir';
use File::Copy;

my $pwd = `pwd`;
chomp $pwd;

my $command =
  -e 'tools/github-debian-upstream'
  ? "sh $pwd/tools/github-debian-upstream"
  : 'github-debian-upstream';
my $tmp = tempdir( 'pkg-js-XXXX', TMPDIR => 1, CLEANUP => 1 );

mkdir "$tmp/debian";
copy "t/old/debian/copyright",       "$tmp/debian";
copy "tools/github-debian-upstream", $tmp;

chdir $tmp;
`git init`;
our $sub;
combined_like(
    sub {
        print `$command`;
    },
    qr#Archive: GitHub.*Bug-Database: https://github.com/foo/bar/issues#s
);
chdir $pwd;
