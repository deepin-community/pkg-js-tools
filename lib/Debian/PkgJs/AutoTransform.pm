package Debian::PkgJs::AutoTransform;

use strict;
use Debian::PkgJs::Utils;
use Dpkg::IPC;
use Exporter 'import';
use File::Copy;
use JSON;

use constant BUNDLE => './dhnodejsBundle.cjs';

our @EXPORT = ('run');

sub run {
    my $pkg = pjson(main_package) or die 'Unable to open package.json';
    die "Package isn't 'type:module', aborting"
      unless $pkg->{type} eq 'module';
    my $entryPoint = $ENV{ENTRY_POINT} || $pkg->{module} || $pkg->{exports};
    $entryPoint = './index.js' if !$entryPoint && -e 'index.js';
    die 'Unable to find entry point. Set it in env vars (ENTRY_POINT)'
      if ref $entryPoint;
    my @links;
    foreach my $type ( grep { $pkg->{$_} } (qw(dependencies peerDependencies devDependencies)) )
    {
        foreach
          my $dep ( grep { !-e "node_modules/$_" } keys %{ $pkg->{$type} } )
        {
            eval { ln($dep); };
            push @links, $dep unless $@;
        }
    }
    spawn(
        exec       => [ qw(mjs2cjs -b -o ), BUNDLE, $entryPoint ],
        wait_child => 1,
    );
    spawn(
        exec => [qw(perl -i -pe ), q{s/(["'])node:/$1/g}, BUNDLE],
        wait_child => 1,
    );
    foreach (@links) {
        unlink "node_modules/$_";
        rmdir "node_modules/$_" if s#/.*?$##;
    }

    # Transform package.json
    if ( $pkg->{files} ) {
        push @{ $pkg->{files} }, BUNDLE;
    }
    $pkg->{module} ||= $entryPoint;
    my $mainCjs = BUNDLE;
    if ( -e 'debian/index.cjs' ) {
        copy('debian/index.cjs','index.cjs');
        push @{ $pkg->{files} }, 'index.cjs';
        $mainCjs = './index.cjs';
    }
    $pkg->{exports} = { "import" => $pkg->{exports} } unless ref $pkg->{exports};
    $pkg->{exports}->{require} = $mainCjs;

    open PKG, '>', 'package.json' or die $?;
    print PKG JSON->new->pretty->canonical->encode($pkg);
    close PKG;
}

1;
