package Debian::PkgJs::Dependencies;

use strict;
use Debian::PkgJs::Cache;
use Debian::PkgJs::Utils;
use Dpkg::IPC;
use Exporter 'import';

our @EXPORT = qw(&availableModules &installedModules &downloadAndInstall);

my $availableModules = {};

sub availableModules {
    return $availableModules if %$availableModules;
    my $cache = $main::cache || Debian::PkgJs::Cache->new(%main::opt);
    return $availableModules
      if ( $availableModules = $cache->get('available') );
    open my $out, '-|', 'apt-file search /nodejs/' or die $!;
    while (<$out>) {
        $availableModules->{$2} = $1
          if
m#^(.*?): /usr/.*?/nodejs/([^/]+|\@[^/]+/[^/]+)/package\.(?:json|yaml)#;
    }
    close $out;
    $cache->set( 'available', $availableModules, CACHEDELAY );
    return $availableModules;
}

my $installedModules = {};
my @npaths =
  ( '/usr/share/nodejs', '/usr/lib/nodejs', glob("/usr/lib/*/nodejs") );

sub installedModules {
    my ($reset) = @_;
    $installedModules = {} if $reset;
    return $installedModules if %$installedModules;
    foreach my $path (@npaths) {
        my $dir;
        opendir $dir, $path;
        my @list = grep { /\w/ } readdir $dir;
        closedir $dir;
        while ( my $m = shift @list ) {
            next unless $m =~ /\w/;
            if ( $m =~ /^@/ ) {
                my $lpath = "$path/$m";
                my $ldir;
                opendir $ldir, $lpath;
                while ( my $s = readdir $ldir ) {
                    next unless $s =~ /\w/;
                    $installedModules->{"$m/$s"} = "$lpath/$s";
                }
                closedir $ldir;
            }
            elsif ( not -d "$path/$m" ) {
                my $tmp = $m;
                $tmp =~ s/\.(?:[cm])?js$//;
                $installedModules->{$tmp} = "$path/$m";
            }
            else {
                $installedModules->{$m} = "$path/$m";
            }
        }
    }
    return $installedModules;
}

sub downloadAndInstall {
    my ( $dest, $url, $name, $nocache ) = @_;
    my $pipe = IO::Handle->new;
    $name //= 'make-fetch-happen';
    open my $null, '>', '/dev/null';
    spawn( exec => [ 'rm', '-rf', $dest ], wait_child => 1, );
    unless ( $url =~ m#^https?://# ) {
        if ( -e $url ) {
            mkdir 'node_modules';
            my @count = ( $dest =~ m#(/)#g );
            symlink '../' x ( scalar(@count) ) . $url, $dest;
        }
        else {
            print STDERR "Bad url $url\n";
        }
        return;
    }
    spawn( exec => [ 'mkdir', '-p', $dest ], wait_child => 1, );
    my $getPid;
    if ( $name and !$nocache and -e "$ENV{HOME}/.npm/_cacache" ) {
        spawn(
            exec => [ 'getFromNpmCache', '-q', "$name:request-cache:$url" ],
            wait_child => 1,
            nocheck    => 1,
        );
        unless($?) {
            $getPid = spawn(
                exec       => [ 'getFromNpmCache', "$name:request-cache:$url" ],
                to_pipe    => $pipe,
                wait_child => 0,
            );
        }
    }
    unless ($getPid) {
        $getPid = spawn(
            exec       => [ 'GET', $url ],
            to_pipe    => $pipe,
            wait_child => 0,
        );
    }
    my $tarPid = spawn(
        exec            => [ qw(tar xzf - -C), $dest, qw(--strip 1) ],
        from_handle     => $pipe,
        wait_child      => 1,
        error_to_handle => $null,
    );
    wait_child( $getPid, cmdline => 'GET' );
    my $pjson = pjson($dest);
    if ( my $bins = $pjson->{bin} ) {
        my $cont = $dest;
        $bins = { $pjson->{name} => $bins } unless ref $bins;
        if ( $cont =~ s#node_modules/.*?$#node_modules# ) {
            mkdir "$cont/.bin" unless -d "$cont/.bin";
            foreach my $bin ( keys %$bins ) {
                my @pathEls = split m#/#, $dest;
                my $name    = pop @pathEls;
                if ( $pathEls[$#pathEls] =~ /^\@/ ) {
                    $name = "$pathEls[$#pathEls]/$name";
                }
                $name =~ s#.*/(?=\@)##;
                unlink "$cont/.bin/$bin";
                symlink "../$name/$bins->{$bin}", "$cont/.bin/$bin";
                chmod 0755, "$cont/$name/$bins->{$bin}";
            }
        }
    }
    if ( $pjson->{scripts}
        and my $postinstall = $pjson->{scripts}->{postinstall} )
    {
        my $dir = $dest;
        $dir =~ s#/[^/]+/?$##;
        spawn(
            exec       => [ 'pkgjs-run', $postinstall ],
            wait_child => 1,
            nocheck    => 1,
            ( $dir ? ( chdir => $dir ) : () ),
        );
    }
}

1;
