package Debian::PkgJs::Utils;

use strict;
use base 'Exporter';
use Dpkg::IPC;
use File::Path qw(make_path);
use Graph;
use JSON;
use Debian::PkgJs::Npm;

use constant CLEANLIST => [
    qw(
      dhnodejsBundle.cjs
    )
];

our @EXPORT = qw(
  $OPTS
  clean_build_modules
  clean_external_modules
  clean_internal_modules
  clean_test_modules
  clean_own_stuff
  component_list
  root_components_list
  link_build_modules
  link_external_modules
  link_internal_modules
  link_test_modules
  list_build_modules
  list_test_modules
  ln
  normalize_name
  normalize_name_strict
  open_file
  main_package
  packages_list
  pjson
  set_debug
  search_bd_in_debian_control
  autoexcluded
);

our $DEBUG;
our $OPTS = { lerna => 1 };
our @AUTOEXCLUDED;
our $WANTTS;

sub set_debug {
    $DEBUG = pop @_;
}

sub debug {
    print @_, "\n" if $DEBUG;
}

sub autoexcluded {
    return map { "!./$_/**/*" } @AUTOEXCLUDED;
}

sub open_file {
    my $file = pop;
    die "Missing file arg" unless $file;
    my $f;
    open( $f, $file ) or die $!;
    my @lines = map {
        s/\r//g;
        chomp;
        s/#.*$//;
        s/^\s*(.*?)\s*/$1/;
        $_ ? $_ : ();
    } <$f>;
    close $f;
    return @lines;
}

my ( %json, $main_p );

sub main_package {
    return ( $main_p ? $main_p : () ) if defined $main_p;
    return '.' unless -e 'debian/nodejs/main';
    my @lines = open_file('debian/nodejs/main');
    die 'Malformed debian/nodejs/main' if @lines > 1;
    print STDERR "Missing main directory $lines[0]\n"
      if @lines and !-d $lines[0];
    $main_p = $lines[0] || '';
    return $main_p;
}

# package.json cache
sub pjson {
    my $dir = pop;
    return {} if -f $dir;
    unless ( -e "$dir/package.json" or -e "$dir/package.yaml" ) {
        print STDERR "/!\\ $dir/package.json not found\n";
        $json{$dir} = {};
    }
    else {
        return $json{$dir} if $json{$dir};
        my $pkgjson;
        if ( -e "$dir/package.json" ) {
            open $pkgjson, "$dir/package.json";
            my $content = join '', <$pkgjson>;
            close $pkgjson;
            $json{$dir} = JSON::from_json($content);
        }
        else {
            require YAML;
            $json{$dir} = YAML::LoadFile("$dir/package.yaml");
        }
    }
    if ( -e "debian/nodejs/$dir/name" ) {
        $json{$dir}->{name} =
          [ open_file("debian/nodejs/$dir/name") ]->[0];
    }
    return $json{$dir};
}

my %lernaFiles;

sub readLerna {
    my $dir = pop;
    return $lernaFiles{$dir} if $lernaFiles{$dir};
    my $globs = {};
    if ( -e "$dir/lerna.json" ) {
        debug("$dir/lerna.json found\n");
        my $jsonc;
        open $jsonc, "$dir/lerna.json";
        my $content = join '', <$jsonc>;
        close $jsonc;
        $globs = JSON::from_json($content);
    }
    if ( my $tmp = pjson($dir)->{workspaces} ) {
        debug("workspaces field found in package.json\n");
        if ( ref $tmp ) {
            if ( ref($tmp) eq 'HASH' and $tmp->{packages} ) {
                $globs->{packages} = $tmp->{packages};
            }
            elsif ( ref $tmp eq 'ARRAY' ) {
                $globs->{packages} = $tmp;
            }
            else {
                print STDERR "Unsupported $dir/package.json format\n";
            }
        }
        else {
            print STDERR "Bad $dir/package.json#workspaces\n";
        }
    }
    $lernaFiles{$dir} = $globs;
    if ( my $lpkgs = $globs->{packages} ) {
        $lpkgs = [$lpkgs] unless ref $lpkgs;
        unless ( ref $lpkgs eq 'ARRAY' ) {
            print STDERR
"Unable to parse lerna.conf#packages and/or package.json#workspaces. Use debian/nodejs/additional_components\n";
            return $lernaFiles{$dir} = {};
        }
        my @pkgs;
        foreach my $entry (@$lpkgs) {
            push @pkgs,
              map { s#^\Q$dir/\E##; m#^tests?/# ? () : $_ } glob("$dir/$entry");
        }
        $lernaFiles{$dir}->{packages} = \@pkgs;
    }
    return $lernaFiles{$dir};
}

sub component_list {
    my $lerna = $OPTS->{lerna};
    my ( @components, %packages, @toDelete );
    my $addPackage = sub {
        my $dir = shift;
        next if -f $dir;
        $dir =~ s#^(?:\.)+/##;
        my $package;
        eval { $package = pjson($dir)->{name} };
        if ( $@ or !$package ) {
            print STDERR "Unable to load $dir $@\n";
            next;
        }
        $packages{$dir} = $package;
    };
    if ( -e 'debian/watch' ) {
        map { push @components, $1 if (/^[^#]*component=([\w\-\.]+)/) }
          open_file('debian/watch');
    }
    if ( $lerna
        and my $lernaPackages = readLerna('.')->{packages} )
    {
        foreach my $p (@$lernaPackages) {
            next if main_package() and $p eq main_package();
            $addPackage->($p);
        }
    }
    if ( -e 'debian/nodejs/additional_components' ) {
        debug "Found debian/nodejs/additional_components";
        map {
            if (s/^!//) {
                push @toDelete, $_;
            }
            else {
                debug 'Adding component(s): ' . join( ', ', glob($_) );
                push @components, glob($_);
            }
        } open_file('debian/nodejs/additional_components');
    }
    foreach my $component (@components) {
        next if main_package() and $component eq main_package();
        if ( -d $component ) {
            my $package;
            if ( $lerna
                and my $lernaPackages = readLerna($component)->{packages} )
            {
                $addPackage->("$component/$_") foreach (@$lernaPackages);
                push @AUTOEXCLUDED, $component;
            }
            else {
                $addPackage->($component);
            }
        }
        else {
            print STDERR "Can't find $component directory in " . `pwd` . "\n";
            next;
        }
    }
    foreach (@toDelete) {
        my $ref = $_;
        @components = grep { $_ ne $ref } @components;
        delete $packages{$ref};
    }
    return \%packages;
}

sub root_components_list {
    return () unless -e 'debian/nodejs/root_modules';
    my @lines = open_file('debian/nodejs/root_modules');
    my $cmps  = component_list();
    if ( grep { $_ eq '*' } @lines ) {
        return $cmps;
    }
    my %res = map {
        map { $_ => $cmps->{$_} } glob($_);
    } @lines;
    return \%res;
}

sub ln {
    my $module = pop;
    die "Missing module arg" unless $module;
    my $path = nodepath($module);
    $module = "\@types/$module" if $WANTTS and $path =~ m#(\@types/.*)/?$#;
    unless ($path) {
        print STDERR "$module not found in nodejs directories\n";
        return;
    }
    my $rpath = $path;
    $rpath =~ s#.*?nodejs/##;
    my $count = scalar( $rpath =~ m#(/)#g );
    $rpath =~ s#[^/]*$##;
    $rpath = "node_modules/$rpath";
    $rpath =~ s#/$##;
    spawn( exec => [ 'mkdir', '-p', $rpath ], wait_child => 1 );
    $rpath = "node_modules/$module";

    if ( -e $rpath ) {
        print STDERR "$module exists\n";
        return -1;
    }
    my $res = symlink $path, $rpath;
    return $res;
}

sub link_build_modules {
    _link_modules('debian/build_modules');
}

sub link_external_modules {
    _extLinks();
}

sub link_internal_modules {
    _intLinks();
}

sub link_test_modules {
    _link_modules('debian/tests/test_modules');
}

sub list_build_modules {
    return _modList('debian/build_modules');
}

sub list_test_modules {
    return _modList('debian/tests/test_modules');
}

sub clean_build_modules {
    return _cleanMods('debian/build_modules');
}

sub clean_external_modules {
    return _cleanExtLinks();
}

sub clean_internal_modules {
    return _cleanIntLinks();
}

sub clean_test_modules {
    return _cleanMods('debian/tests/test_modules');
}

sub clean_own_stuff {
    my $dir = pop;
    unlink "$dir/$_" foreach ( @{&CLEANLIST} );
}

# Internal subroutines

sub _link_modules {
    my ($srcDir) = @_;
    return unless -d $srcDir;
    my @mods = _modList( $srcDir, '' );
    foreach (@mods) {
        _dolink( "$srcDir/$_", "node_modules/$_" );
    }
}

my %dirs;

sub _modList {
    my ( $dir, $prefix ) = @_;
    my @res;
    return ()
      unless -d $dir;
    my $d;
    opendir $d, $dir;
    while ( readdir $d ) {
        next if /^\./;
        if (/^\@/) {
            $dirs{$_}++;
            push @res, _modList( "$dir/$_", "$_" );
        }
        else {
            push @res, ( $prefix ? "$prefix/$_" : $_ );
        }
    }
    closedir $d;
    return sort(@res);
}

sub _dolink {
    my ( $src, $dst ) = @_;
    return if $src eq $dst;
    if ( -e $dst ) {
        print STDERR "Unable to link $src into $dst: dest exists\n";
        return;
    }
    my $dir   = $dst;
    my @count = ( $dir =~ m#(/)#g );
    $dir =~ s#/[^/]*?$##;
    make_path $dir;
    $src = ( '../' x ( scalar(@count) ) ) . $src unless $src =~ m#^/#;
    my $res = symlink $src, $dst;
    if ($res) {
        debug "Link $dst -> $src";
    }
}

sub _cleanMods {
    my ($dir) = @_;
    my @mods = _modList( $dir, '' );
    unlink "node_modules/$_" foreach (@mods);
    rmdir "node_modules/$_"  foreach keys %dirs;
    rmdir 'node_modules';
    %dirs = ();
}

sub normalize_name {
    my $moduleName = pop;

    # Translate module name into component name
    # Ex: @types/assert_test becomes types-assert-test

    # 1. Replace @, / and _ into -
    $moduleName =~ s#[\@\-/_]#-#g;
    $moduleName =~ s/--+/-/g;

    # 2. Drop "-" at beginning and end
    $moduleName =~ s/^-//;

    # 3. Remove other special characters
    $moduleName =~ s/[^\w\.\-]//g;
    return $moduleName;
}

sub normalize_name_strict {
    my $moduleName = pop;
    $moduleName =~ s/\./-/g;
    return normalize_name($moduleName);
}

sub _extLinks {
    my $components = component_list;
    my @dirs       = ( sort keys %$components );
    return
      unless ( @dirs
        or -e 'debian/nodejs/extlinks'
        or -e 'debian/nodejs/extcopies'
        or -e 'debian/nodejs/' . main_package() . '/extlinks'
        or -e 'debian/nodejs/' . main_package() . '/extcopies'
        or -d 'debian/build_modules' && main_package() eq '.' );
    mkdir 'node_modules' unless -e 'node_modules';

    # External links
    foreach my $dir (
        (
            main_package()
            ? (
                main_package() ne '.'
                ? ( main_package(), '.' )
                : ('.')
            )
            : ('.')
        ),
        @dirs
      )
    {

        # Link or copy modules listes in debian/nodejs/extlinks and
        # debian/nodejs/extcopies
        my %cmds = (

            # Case "links" launch doLink()
            links => sub {
                _dolink( $_[0], "$dir/node_modules/$_[1]" );
            },

            # Case "copies" launch build subdir if needed and launch "cp"
            copies => sub {
                if ( $_[1] =~ s#/.*?$## ) {
                    spawn(
                        exec => [ 'mkdir', '-p', "$dir/node_modules/$_[1]" ],
                        wait_child => 1,
                    ) unless -e "$dir/node_modules/$_[1]";
                }
                else {
                    $_[1] = '';
                }
                spawn(
                    exec => [ 'cp', '-rL', $_[0], "$dir/node_modules/$_[1]" ],
                    nocheck    => 1,
                    wait_child => 1,
                );
                debug "Copy $_[0] -> $dir/node_modules/$_[1]";
            }
        );

        # Common Links/copies process
        foreach my $type ( ( 'links', 'copies' ) ) {
            if ( -e "debian/nodejs/$dir/ext$type" ) {

                # read debian/nodejs/{extlinks,extcopies}
                map {

                    # Drop "  test" if exists
                    $_ =~ s/\s+(\S*).*?$//;

                    # If "  test" exists, link/copy module only if !nocheck
                    if (
                            $1
                        and $1 eq 'test'
                        and (
                            (
                                    $ENV{DEB_BUILD_OPTIONS}
                                and $ENV{DEB_BUILD_OPTIONS} =~ /\bnocheck\b/
                            )
                            or (    $ENV{DEB_BUILD_PROFILES}
                                and $ENV{DEB_BUILD_PROFILES} =~ /\bnocheck\b/ )
                        )
                      )
                    {
                        print STDERR "Skipping $_ link\n";
                    }
                    else {
                        # Search module using nodepath
                        my ($src);
                        spawn(
                            exec       => [ 'nodepath', '-B', $_ ],
                            wait_child => 1,
                            to_string  => \$src,
                            nocheck    => 1,
                        );

                        # Fail if not found
                        if ( $? or not $src ) {
                            print STDERR "### $_ is required by "
                              . "debian/nodejs/$dir/ext$type"
                              . " but not available\n";
                            if ( $_ =~ s#^\@types/## ) {
                                print STDERR "# Typescript definition "
                                  . "detected, Fallback to main module\n";
                                spawn(
                                    exec       => [ 'nodepath', '-B', $_ ],
                                    wait_child => 1,
                                    to_string  => \$src,
                                    nocheck    => 1,
                                );
                                if ( $? or not $src ) {
                                    print STDERR "### $_ isn't available too\n";
                                    exit 1;
                                }
                                print STDERR "### You SHOULD update your "
                                  . "debian/nodejs/$dir/ext$type file!\n";
                            }
                            else {
                                exit 1;
                            }
                        }
                        chomp $src;
                        my $tmp = $src;
                        $tmp =~ s#^.*?nodejs/##;
                        $cmds{$type}->( $src, $tmp );
                    }
                } open_file("debian/nodejs/$dir/ext$type");
            }
        }
    }
}

sub _intLinks {
    my $components = component_list;
    my @dirs       = ( sort keys %$components );

    # Link each component in node_modules
    foreach my $component (@dirs) {
        my $package = $components->{$component};
        _dolink( "$component", "node_modules/$package" )
          unless -e "debian/nodejs/$component/nolink";
    }

    # Links between components
    if ( -e 'debian/nodejs/component_links' ) {
        map {
            unless (/^([\w\-\.\/]+)\s+([\w\-\.\/]+)$/) {
                print STDERR
                  "Malformed line $. in debian/nodejs/component_links: $_\n";
            }
            else {
                my ( $src, $dest ) = ( $1, $2 );
                my $success = 1;
                foreach my $s ( $src, $dest ) {
                    unless ( $components->{$s} ) {
                        print STDERR "component_links: Unknown component $s\n";
                        $success = 0;
                    }
                }
                _dolink( $src => "$dest/node_modules/$components->{$src}" )
                  if $success;
            }
        } open_file('debian/nodejs/component_links');
    }
}

sub _cleanExtLinks {
    my $components = component_list;
    my @dirs       = ( sort keys %$components );
    push @dirs, main_package;
    push @dirs, '.' unless main_package eq '.';
    foreach my $dir ( main_package, @dirs ) {
        debug "rm $dir/node_modules/.cache";
        spawn(
            exec       => [ 'rm', '-rf', "$dir/node_modules/.cache" ],
            wait_child => 1
        );
        if ( -e "debian/nodejs/$dir/extlinks" ) {
            map {
                s/\s.*$//;
                debug "unlink $dir/node_modules/$_";
                unlink "$dir/node_modules/$_";
                if (s#/.*?$##) {
                    debug "Trying to remove $dir/node_modules/$_";
                    rmdir "$dir/node_modules/$_";
                }
            } open_file("debian/nodejs/$dir/extlinks");
        }
        if ( -e "debian/nodejs/$dir/extcopies" ) {
            map {
                s/\s.*$//;
                debug "rm $dir/node_modules/$_";
                spawn(
                    exec       => [ 'rm', '-rf', "$dir/node_modules/$_" ],
                    wait_child => 1
                );
                if (s#/.*?$##) {
                    debug "Trying to remove $dir/node_modules/$_";
                    rmdir "$dir/node_modules/$_";
                }
            } open_file("debian/nodejs/$dir/extcopies");
        }
    }

}

sub _cleanIntLinks {
    my $components = component_list;
    my @dirs       = ( sort keys %$components );
    if ( -e 'debian/nodejs/component_links' ) {
        map {
            unless (/^([\w\-\.\/]+)\s+([\w\-\.\/]+)$/) {
                print STDERR
                  "Malformed line $. in debian/nodejs/component_links: $_\n";
            }
            my ( $src, $dest ) = ( $1, $2 );
            debug "unlink $dest/node_modules/$components->{$src}";
            unlink("$dest/node_modules/$components->{$src}");
        } open_file('debian/nodejs/component_links');
    }
    foreach my $component ( main_package, @dirs ) {
        my $package = $components->{$component};

        # Error not catched here
        if ( $package and not $component eq "node_modules/$package" ) {
            debug "unlink node_modules/$package";
            unlink("node_modules/$package");
        }
    }
}

sub nodepath {
    my ($module) = pop;
    my $path;
    spawn(
        exec       => [ 'nodepath', '-B', ( $WANTTS ? ('-t') : () ), $module ],
        to_string  => \$path,
        wait_child => 1,
        nocheck    => 1,
    );
    chomp $path;
    return $path;
}

sub _debian_control {
    require Debian::Control;
    my $c = Debian::Control->new;
    $c->read('debian/control');
    return $c;
}

sub search_bd_in_debian_control {
    my $re    = pop;
    my $found = 0;
    map { $found++ if $_->pkg =~ $re }
      @{ _debian_control->source->Build_Depends };
    return $found;
}

sub packages_list {
    return keys %{ _debian_control->binary };
}

sub ordered_components_list {
    my $components = component_list;
    my @cmps       = sort keys %$components;
    $components->{&main_package} = pjson(main_package)->{name};
    push @cmps, &main_package;
    my $modules = { map { ( $components->{$_} => $_ ) } keys %$components };

    #my $g = Graph->new;
    #$g->add_vertices( keys %$components );
    my %needs;

    sub deplist {
        my ($cmp) = @_;
        return () unless -d $cmp;
        my $name = pjson($cmp)->{name};
        my @deps = sort ( ( keys %{ pjson($cmp)->{dependencies} // {} } ),
            ( keys %{ pjson($cmp)->{devDependencies}  // {} } ),
            ( keys %{ pjson($cmp)->{peerDependencies} // {} } ),
        );
        map {
            my $s = $components->{$_};

          #map { $g->add_edge( $modules->{$_}, $cmp ) } grep { $_ eq $s } @deps;
            map { $needs{$cmp}->{ $modules->{$_} } = 1 }
              grep { $_ eq $s } @deps;
        } @cmps;
    }
    deplist($_) foreach (@cmps);
    my ( @list, @res );
    foreach my $cmp (@cmps) {
        if ( $needs{$cmp} ) {
            push @list, $cmp;
        }
        else {
            push @res, $cmp;
        }
    }

    sub findB {
        my ( $b, $deps, $level ) = @_;
        return 1 if $deps->{$b};
        return 0 if $level >= $#list;
        foreach my $k ( keys %$deps ) {
            return 1 if findB( $b, $needs{$k}, $level + 1 );
        }
        return 0;
    }
    push @res, sort {
        return 1  if findB( $b, $needs{$a}, 0 );
        return -1 if findB( $a, $needs{$b}, 0 );
    } @list;

    #eval { @res = $g->toposort };
    #if ($@) {
    #    die "Unable to resolve automatically components build order"
    #}
    return @res;
}

1;
