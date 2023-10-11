package Lintian::Check::PkgJs::Repo;

use strict;
use warnings;
use Dpkg::IPC;
use Debian::PkgJs::Utils;
use Moo;
use namespace::clean;

with 'Lintian::Check';

sub source {
    my ($self) = @_;
    my ( $out, $err );
    $self->pkgjsScan('debian/build_modules');
    $self->pkgjsScan('debian/tests/test_modules');
    return unless ( -e 'package.json' or -e 'package.yaml' );
    spawn(
        exec            => ['debcheck-node-repo'],
        to_string       => \$out,
        error_to_string => \$err,
        wait_child      => 1,
        nocheck         => 1
    );
    $self->hint('inconsistency-debian-watch') if $?;
}

sub visit_installed_files {
    my ( $self, $item ) = @_;
    return
      if $item->is_dir;

    return
      if $self->processable->name =~ /-dbg$/;

    my $txt;
    $self->hint( 'nodejs-package-vulnerable', $txt )
      if $item->name =~ m{/package\.(?:json|yaml)$}
      and $txt = vulnerable( $item->unpacked_path );
}

sub pkgjsScan {
    my ( $self, $dir, $prefix ) = @_;
    return unless -d $dir;
    $prefix //= '';
    my $dh;
    opendir $dh, $dir;
    map {
        if ( !-d "$dir/$_" or /^\./ ) {
        }
        elsif (/^\@/) {
            pkgjsScan( "$dir/$_", $_ );
        }
        else {
            my $out;
            my $module_name = ( $prefix ? "$prefix/" : '' ) . $_;
            spawn(
                exec       => [ 'apt-file', 'search', "/nodejs/$module_name/" ],
                nocheck    => 1,
                wait_child => 1,
                to_string  => \$out,
            );
            if ( !$@ and $out ) {
                $self->hint( 'embedded-module-which-exists-in-debian',
                    $module_name, $dir );
            }
        }
    } readdir $dh;
    closedir $dh;
}

sub vulnerable {
    my ($path) = @_;
    my ( $out, $err );
    $path =~ s#/package\.(?:json|yaml)$##;
    spawn(
        exec            => ['pkgjs-audit'],
        nocheck         => 1,
        wait_child      => 1,
        to_string       => \$out,
        error_to_string => \$err,
        chdir           => $path,
    );
    return pjson($path)->{name} . " or its dependencies are vulnerable"
      if $out =~ /found [1-9]\d* vulnerabilities/i;
    return;
}

1;
