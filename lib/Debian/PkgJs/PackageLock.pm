package Debian::PkgJs::PackageLock;

use strict;
use Debian::Control;
use Debian::PkgJs::Utils;
use Debian::PkgJs::Version;
use Dpkg::IPC;
use Exporter 'import';
use JSON;

our @EXPORT = ( '&buildPackageLock', '&builtUsing' );

our $BUILTUSING = {};
our $PACKAGES   = {};
our $PATHS      = {};

my $WEBPACKS = qr/^.*\b(?:node-rollup-plugin-node-resolve|browserify(?:-lite)?|webpack)\b.*/i;
*debug = \&Debian::PkgJs::Utils::debug;

sub nodepathNoError {
    my ( $related, @mods ) = @_;
    my ( %res, @PIDS );
    foreach my $mod (@mods) {
        if ( $PATHS->{$mod} and ( $related or $PACKAGES->{$mod} ) ) {
            $res{$mod} = [ $PACKAGES->{$mod}, $PATHS->{$mod} ];
        }
        else {
            my ( $read, $null );
            $read = IO::Handle->new;
            open $null, '>', '/dev/null';
            push @PIDS,
              [
                $mod,
                spawn(
                    exec => [ 'nodepath', ( $related ? '-pr' : '-p' ), $mod ],
                    to_pipe         => $read,
                    error_to_handle => $null,
                    wait_child      => 0,
                ),
                $read, $null,
              ];
        }
    }
    foreach (@PIDS) {
        my ( $mod, $pid, $out, $null ) = @$_;
        use Data::Dumper;
        eval {
            my $p = wait_child( $pid, cmdline => 'z' );
            my ( $pkg, $path ) = split /: /, <$out>;
            chomp $path;

            # Fix reproducibility
            unless ( $path =~ s#.*(/usr/(?:share|lib(?:/[^/]+)?)/nodejs/)#$1# )
            {
                $path =~ s#^/.*$#node_modules/$mod#;
            }
            $PACKAGES->{$mod} = $pkg if $pkg;
            if ($path) {
                $PATHS->{$mod} = $path;
                $res{$mod} = [ $pkg, $path ];
            }
        };
        close $out;
        close $null;
    }
    return \%res;
}

sub buildPackageLock {
    my ( $src, $dst, $check ) = @_;
    die 'Destination needed' unless $dst;
    if ($check) {
        return unless search_bd_in_debian_control($WEBPACKS);
        debug("Package looks like a bundle, generating pkgjs-lock.json file");
    }
    my $pjson = pjson($src);
    my $deps  = {
        %{ $pjson->{devDependencies}  // {} },
        %{ $pjson->{dependencies}     // {} },
        %{ $pjson->{peerDependencies} // {} },
    };
    my $res = {
        name            => $pjson->{name},
        version         => $pjson->{version},
        lockfileVersion => 2,
        packages        => {
            "" => {
                name    => $pjson->{name},
                version => $pjson->{version},
            },
        },
        dependencies  => {},
        pkgjs_version => $VERSION,
    };
    my $count = 0;
    if ( $deps and %$deps ) {
        my $nodePaths = nodepathNoError( 1,
            map { -d "node_modules/$_" ? () : $_ } keys %$deps );
        foreach my $dep ( keys %$deps ) {
            my ( $out, $err );
            if ( -d "node_modules/$dep" ) {
                $out = "node_modules/$dep";
            }
            else {
                $out = $nodePaths->{$dep}->[1];
            }
            if ( $out and my $pjs = pjson($out) ) {
                $count++;
                $res->{packages}->{$out} = {
                    name    => $dep,
                    version => $pjs->{version} || 'unknown',
                };
                $res->{dependencies}->{$dep} =
                  { version => $pjs->{version} || '*', };
                $BUILTUSING->{$dep} = $pjs->{version} || '';
            }
        }
    }
    unless ($count) {
        debug("No build dependencies found, skip pkgjs-lock.json");
        return;
    }
    open my $fdst, '>', $dst or die "Unable to write package-lock.json: $!";
    my $str = JSON->new->canonical->indent->encode($res);
    $str =~ s/   / /g;
    chomp $str;
    print $fdst $str;
    close $fdst;
    return 1;
}

sub builtUsing {
    my %res;
    my $nodePaths = nodepathNoError( 0, keys %$BUILTUSING );
    map {
        my ( $pkg, $version, $err );
        if ( $pkg = $nodePaths->{$_}->[0] ) {
            eval {
                unless ( $res{$pkg} ) {
                    spawn(
                        exec => [
                            'dpkg-query', '--showformat=${Version}',
                            '--show',     $pkg,
                        ],
                        wait_child      => 1,
                        to_string       => \$version,
                        error_to_string => \$err,
                    );
                    chomp $version;
                    $res{$pkg} = $version;
                    debug("Add $pkg (= $version) in \${nodejs:BuiltUsing}");
                }
            };
        }
    } keys %$BUILTUSING;
    return join( ',', map { "$_ (= $res{$_})" } sort keys %res );
}

1;
__END__
=head1 NAME

Debian::PkgJS::PackageLock - Perl module to build pkgjs-lock.json files

=head1 SYNOPSIS

  use Debian::PkgJS::PackageLock;
  
  for my $path (@jsModulePaths) {
      buildPackageLock( $path, "$path/pkgjs-locj.json");
  }
  
  use Debian::Debhelper::Dh_Lib;
  
  addsubstvar( $pkg, builtUsing() );

=head1 DESCRIPTION

=head2 EXPORT

=over

=item B<buildPackageLock( $path, $dest )>

=item B<builtUsing()>

=back

=head1 COPYRIGHT AND LICENSE

Copyright Yadd E<lt>yadd@debian.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

On Debian systems, the complete text of version 2 of the GNU General
Public License can be found in `/usr/share/common-licenses/GPL-2'.
If not, see L<http://www.gnu.org/licenses/>.

=cut
