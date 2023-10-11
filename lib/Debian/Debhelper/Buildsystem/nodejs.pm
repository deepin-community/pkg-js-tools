# A debhelper build system class for handling pkg-js-autopkgtest test.
#
# Copyright: Yadd <yadd@debian.org>
# License: GPL-2+

package Debian::Debhelper::Buildsystem::nodejs;

use strict;
use warnings;
use Debian::Debhelper::Dh_Lib;
use File::Find;
use JSON;
use Graph;
use IPC::Run qw(run);
use Debian::PkgJs::PackageLock;
use Debian::PkgJs::Utils;
use parent qw(Debian::Debhelper::Buildsystem);

use constant MAX_BUILD_LOOP => 3;

sub NPMIGNOREDEFAULT {
    $ENV{NPMIGNOREDEFAULT} || '/usr/share/pkg-js-tools/npmignore.default';
}

set_debug(1);

# echo, touch and ls are here to help tests
my @known_build_commands = (qw(grunt echo touch ls));

#(qw(babel grunt gulp node rollup tsc webpack cat echo touch ls));

# Order is important here, example: tsc must be launched before other
my @knwonBuildFiles = (
    [ 'Gruntfile.js'     => ['grunt'] ],
    [ 'Gruntfile.coffee' => ['grunt'] ],

    #[ 'tsconfig.json'     => ['tsc'] ],
    [ 'gulpfile.js'       => ['gulp'] ],
    [ 'rollup.config.js'  => [ 'rollup',  '-c' ] ],
    [ 'rollup.config.mjs' => [ 'rollup',  '-c' ] ],
    [ 'webpack.config.js' => [ 'webpack', '--mode', 'production' ] ],
    [ 'webpackfile.js'    => [ 'webpack', '--mode', 'production' ] ],
);

my $knownCommandMap = { babel => 'babeljs', };

my $noexecFiles = qr/\.(?:[cm]?js|json|[cm]?ts)/;

sub DEBUG     { $ENV{DEB_BUILD_PKG_JS_DEBUG} }
sub DEBUGFILE { $ENV{DEB_BUILD_PKG_JS_DEBUG_FILE} }

sub DESCRIPTION {
    "dh-sequence-nodejs";
}

### CONSTANTS

# Regexp compiled from dh_nodejs/dh_root_files.excluded
my $rootFilesIgnored =
qr/^(?:(?:g(?:ulpfile\.(?:babel\.m?j|(?:t|m?j))|runt(?:file)?\.j)|(?:rollup[\.\-].*config|karma\.conf)\.j)s|j(?:a(?:kefile(?:\.js)?|smine\.json)|est\.config\.js|sl\.node\.conf)|b(?:abel\.config\.js(?:on)?|inding\.gyp|ench.*\.js|ower\.json)|c(?:o(?:mponent\.json|ntribute|pying)|hange(?:log|s?)|akefile)|a(?:ut(?:otest\.watchr|hors?)|va\.config\.js|ppveyor\.yml)|\.(?:babelrc(?:\.js(?:on)?)?|mocharc\.js(?:on)?|.*)|.*\.(?:m(?:arkdown|d)|pdf|txt)|t(?:sconfig.*\.json|ests?\.js)|l(?:icen[cs]e.*|erna\.json)|(?:docker|make)file|package-lock\.json|yarn\.lock|history)$/i;
my $filesIgnored =
qr/^(?:\.(?:(?:wafpickle-|eslint|_).*|npm(?:ignore|rc)|lock-wscript|gitignore)|.*\.(?:c(?:offee|\+\+|cp?)?|orig|def|mk|h)|(?:[jm]|binding.M)akefile|readme(?:\.(?:txt|md))?|tsconfig\.tsbuildinfo|package-lock\.json|npm-debug\.log|yarn\.lock)$/i;

# Regexp compiled from dh_nodejs/dh_dirs.excluded
my $dirIgnored =
qr{^(?:(?:.*/)?(?:\.(?:_.*|git|svn|hg)|.(?:DS_Store|deps)|__[^/]*__|fixtures?|CVS)|(?:archived-packag|node_modul)es|t(?:ap-snapshots|ests?)|(?:example|doc)s?|bench|\..*)(?:/.*)?}i;

# Extensions that overrides $rootFilesIgnored if set in package.json#files
my $authorizedExt = qr/\.(?:js)$/;

### PRIVATE METHODS

sub pattern {
    my ( $self, $line ) = @_;
    my ( $p, $pattern );
    print "Parsing expression $line\n";
    $line =~ m/^(.*?)([\{\*].*)$/ or error "Bad line $line";
    my $tmp = $line;
    my ( $dir, $expr ) = ( $1, $2 );
    if ($dir) {
        $dir =~ s#/+([^/]*)$##;
        $expr = "$1$expr";
        $p    = $dir;
    }
    else {
        $p = $self->main_package;
    }
    my @dirs = split( m#\*\*/#, $expr );
    @dirs = map {
        my $s = quotemeta($_);
        $s =~ s#\\\*#[^/]*#g;
        $s =~ s#\\\((.*?)\\\)#(?:$1)?#g;
        $s =~ s#\\\[(.*?)\\\]#[$1]#g;
        while ( $s =~ s/\\\{(.*?)\\\}/_____/ ) {
            my $tmp = '(?:' . join( '|', split( /\\?,/, $1 ) ) . ')';
            $s =~ s/_____/$tmp/;
        }
        $s
    } @dirs;
    my $pat = "^$p/" . join( '.*(?<=/)', @dirs ) . '(?:/.*)?$';
    print "Line $tmp becomes: $pat\n";
    eval { $pattern = qr/$pat/ };
    error << "EOF" if ($@);

Unable to parse expression: "$tmp" (converted into "$pat")
If it is correct, please fill a bug against pkg-js-tools.
To workaround, you can overwrite "files" field in debian/nodejs. See
/usr/share/doc/pkg-js-tools/README.md.

EOF
    return ( $p, $pattern );
}

# Private method to build modules
sub build_module {
    my ( $self, $dir ) = @_;
    my $buildCommand;

    # Instead of an override, maintainers can write a debian/nodejs/build
    # or debian/nodejs/<component>/build
    my $builddir = $self->get_buildpath . "/$dir";
    my @count    = ( $dir =~ m#(/)#g );

    if ( -e "debian/nodejs/$dir/build" ) {
        print "Found debian/nodejs/$dir/build\n";
        print_and_doit(
            { chdir => $builddir },
            'sh', '-ex',
            (
                ( $dir ne '.' ? '../' x ( scalar(@count) + 1 ) : '' )
                . "debian/nodejs/$dir/build"
            )
        );
        return 1;
    }
    $buildCommand = $self->pjson($dir)->{scripts}->{build};
    my @commands;
    if ($buildCommand) {
        @commands = $self->resolve_command( $dir, $buildCommand );
    }
    else {
        print "No build command found, searching known files\n";
        foreach my $i (@knwonBuildFiles) {
            if ( -e "$dir/$i->[0]" ) {
                push @commands, $i->[1];
            }
        }
    }
    my $failures = 0;
    my $success  = 0;
    foreach my $cmd (@commands) {

        #$self->_generic_doit_in_dir( $dir, \&print_and_doit, @$_ );
        my $res = print_and_doit_noerror( { chdir => $builddir }, @$cmd );
        if ($res) {
            print 'Command "' . join( ' ', @$cmd ) . qq'" succeeded in $dir\n';
            $success++;
        }
        else {
            warning '### Command "'
              . join( ' ', @$cmd )
              . qq'" failed in $dir\n';
            $failures++;
        }
    }
    if ( $failures and not $success ) {
        warning <<EOF;

############################################################################
$failures failures, unable to build automatically.
Install a debian/nodejs/$dir/build or add a "override_dh_auto_build:" target
in debian/rules
############################################################################
EOF
    }
    return $failures ? $success : 1;
}

sub resolve_command {
    my ( $self, $dir, $command, $count ) = @_;
    $count //= 0;
    if ( $count > MAX_BUILD_LOOP ) {
        warning "Max loop command exceed, aborting";
        return ();
    }
    my @tmp = split /\s*&&\s*/, $command;
    my @commands;
    foreach my $inst (@tmp) {
        my ( $cmd, @rargs ) = split /\s+/, $inst;
        my @args;
        while ( my $c = shift @rargs ) {
            if ( $c =~ s/^(["'])// ) {
                my $sep = $1;
                while ( not( $c =~ s/$sep$// ) and @rargs ) {
                    $c = "$c " . shift(@rargs);
                }
            }
            push @args, $c;
        }
        if ( $cmd eq 'npm' and $args[0] and $args[0] eq 'run' ) {
            my $target = $self->pjson($dir)->{scripts}->{ $args[1] };
            if ( $target and $target ne $command ) {
                $count++;
                push @commands, $self->resolve_command( $dir, $target, $count );
            }
            next;
        }
        elsif ( grep { $cmd eq $_ } @known_build_commands ) {
            $cmd = $knownCommandMap->{$cmd} if $knownCommandMap->{$cmd};
            push @commands, [ $cmd, @args ];
        }
    }
    return @commands;
}

# Symlinks methods
sub dolink {
    my ( $self, $src, $dest ) = @_;
    return if $src eq $dest;
    my $dir = $dest;
    $self->doit_in_builddir( 'mkdir', '-p', $dir )
      if $dir =~ s#/[^/]*$##
      and
      not doit_noerror( { chdir => $self->get_buildpath }, 'test', '-e', $dir );
    my @count = ( $dir =~ m#(/)#g );
    $src = ( '../' x ( scalar(@count) + 1 ) ) . $src unless $src =~ m#^/#;
    $self->doit_in_builddir( 'ln', '-s', $src, $dest );
}

sub do_unlink {
    my ( $self, $link ) = @_;
    unlink $link;
    while ( $link =~ s#/[^/]*?$## ) {
        rmdir $link;
    }
}

# Private method to install modules: search for package.json#files field, if
# not found, install any files except ignored by regexp
sub install_module {
    my ( $self, $destdir, $archPath, $path, $dir, @excludedDirs ) = @_;
    my $re = (
        @excludedDirs
        ? '^(?:' . join( '|', @excludedDirs ) . ')(?:/.*)?$'
        : '##'
    );
    $re = qr/$re/;

    # If debian/nodejs/$dir/install or debian/nodejs/$dir/files or
    # "package.json#files" field exists, only its paths will be examined
    my @files;
    my $noFilesField = 1;
    my $skipFiles    = 1;
    if ( -e "debian/nodejs/$dir/install" ) {
        map {
            s/^\s*(.*?)\s*/$1/;
            next if /^\s*#/;
            my $dest = $path;
            my $src  = $_;
            if (/^(.+?)\s+(.+)$/) {
                $src = $1;
                my $tmp = $2;
                if ( $tmp =~ m{^/} ) {
                    $dest = "$destdir/$tmp";
                }
                else {
                    $dest = "$archPath/$tmp";
                }
            }

            $self->doit_in_builddir( 'mkdir', '-p', $dest )
              unless doit_noerror( { chdir => $self->get_buildpath },
                'test', '-e', $dest );
            $self->doit_in_builddir( 'cp', '--reflink=auto', '-a', "$dir/$src",
                $dest );
        } $self->open_file("debian/nodejs/$dir/install");
        return;
    }
    my $npmignore = -e "$dir/.npmignore" ? "$dir/.npmignore" : NPMIGNOREDEFAULT;
    if ( -e "debian/nodejs/$dir/files" ) {
        @files =
          $self->readFilesField( $dir,
            $self->open_file("debian/nodejs/$dir/files") );
        $noFilesField = 0;
        $skipFiles    = 0;
    }
    elsif ( $self->pjson($dir)->{files} ) {
        @files = $self->readFilesField(
            $dir,
            $self->filesFieldToList( $dir, 'files' ),
            $self->filesFieldToList( $dir, 'typings' ),
            $self->filesFieldToList( $dir, 'types' ),
        );
        if ( $self->pjson($dir)->{types} and not $self->pjson($dir)->{typings} )
        {
            warning qq{# /!\ "types" field should be replaced by "typings"}
              . " in $dir/package.json\nPlease report this bug\n";
        }
        $noFilesField = 0;
        push @files,
          grep { $_ ne "$dir/package.json" and $_ ne "$dir/package.yaml" }
          $self->readFilesField(
            $dir,
            ( map { s/^/!/; s/^\!\!//; $_ } ( $self->open_file($npmignore) ) )
          );
    }
    else {
        print qq{No "files" field in $dir/package.json, install all files\n};
        @files = ($dir);
        push @files,
          grep { $_ ne "$dir/package.json" and $_ ne "$dir/package.yaml" }
          $self->readFilesField(
            $dir,
            ( map { s/^/!/; s/^\!\!//; $_ } ( $self->open_file($npmignore) ) )
          );
        print "Files to install: " . join( ', ', @files ) . "\n";
    }
    push @files, autoexcluded() if $dir eq '.';
    my @dest;
    my $mainFile =
      $self->toJs( $dir, $self->pjson($dir)->{main} || "index.js" );
    $mainFile =~ s#^(?:\./)+##;
    $mainFile = "$dir/$mainFile";
    $mainFile = "$mainFile/index.js" if -d $mainFile;
    warning "MAIN: $mainFile\n" if (DEBUG);
    $mainFile =~ s#//+#/#g;
    my $foundMain    = 0;
    my $foundPkgJson = 0;

    foreach my $p (@files) {
        my $pattern;
        my $not = 0;
        if ( $p =~ s/^\!// ) {
            $not = 1;
        }
        if ( $p =~ s/\!(.*)$// ) {
            push @files, "!$p$1";
        }
        if ( $p =~ m/[\*|\{\(]/ ) {
            ( $p, $pattern ) = $self->pattern($p);
        }
        unless ( -e $p ) {
            warning "### Missing $p, skipping\n";
            next;
        }
        find(
            sub {
                my $d = $File::Find::dir;
                return if $pattern and "$d/$_" !~ $pattern and $d !~ $pattern;
                $d =~ s#^$dir/?##;

                # Exclusion tests:
                # ----------------
                #
                #  - $skipFiles=1 unless Debian maintainer specified a
                #                 debian/nodejs/install or debian/nodejs/files
                #  - $noFilesField = 1 unless:
                #                      - DM specified a debian/nodejs/install
                #                      - DM specified a debian/nodejs/files
                #                      - package.json contains a "files" field
                my @tests = (

                    # test0: Ignore directories
                    ( -d $_ ),

                    # test1: Don't parse components sub dir for main module
                    ( $d and $d =~ $re and $skipFiles ),

                    # test2: Ignore our debian/ dir
                    (
                              $dir eq '.'
                          and $File::Find::dir =~ m{^(?:./)?debian}
                          and $skipFiles
                    ),

                    # test3: Ignore license, changelog, readme,... files
                    ( $_ =~ $rootFilesIgnored and $noFilesField and !$d ),

                    # test4:
                    (
                              $_ =~ $rootFilesIgnored
                          and $skipFiles
                          and ( $noFilesField or $_ !~ $authorizedExt )
                          and !$d
                    ),

                    # test5: Ignore Makefile, .eslint anywhere unless DM
                    # specified it explicitely
                    ( $_ =~ $filesIgnored and ( $pattern or $p !~ /$_$/ ) ),

                    # test6: Ignore test directory unless DM specified it
                    # explicitely
                    ( $d and $d =~ $dirIgnored and $skipFiles ),

                    # test7: Ignore test.js file unless specified in
                    # package.json#files
                    (
                              $File::Find::dir eq $dir
                          and /^(?:example|test)s?\.js$/i
                          and $noFilesField
                    ),
                );

                # Install files unless one exclusion test match
                if ($not) {
                    @dest = grep { $_->[1] ne $File::Find::name } @dest;
                }
                else {
                    unless ( grep { $_ } @tests ) {
                        push @dest, [ $d, $File::Find::name ];
                        $foundMain    = 1 if $File::Find::name eq $mainFile;
                        $foundPkgJson = 1
                          if $File::Find::name eq 'package.json'
                          or $File::Find::name eq 'package.yaml';
                    }

                    # Debug
                    elsif ( DEBUG and not DEBUGFILE ) {
                        warning "# FILE $File::Find::name\n";
                        for ( my $i = 0 ; $i < @tests ; $i++ ) {
                            warning "#     Test$i: "
                              . ( $tests[$i] || 0 ) . "\n";
                        }
                    }
                }
                if ( DEBUGFILE and $_ eq DEBUGFILE ) {
                    warning <<EOF;

# FILE $File::Find::name
#    D:            $d
#    PATH:         $File::Find::dir
#    DIR:          $dir
#    SKIP:         $skipFiles
#    NOFILESFIELD: $noFilesField
EOF
                    warning '# '
                      . ( ( grep { $_ } @tests ) ? 'EXCLUDED' : 'INSTALLED' )
                      . ":\n";
                    for ( my $i = 0 ; $i < @tests ; $i++ ) {
                        warning "#     Test$i: " . ( $tests[$i] || 0 ) . "\n";
                    }
                }
            },
            $p
        );
    }
    unless ( $foundMain or !$self->main_package ) {
        if ( -e $mainFile ) {
            warning
              "package.json#main file not installed, forcing it ($mainFile)\n";
            my $ldir = ( $mainFile =~ m#^(?:$dir/?)?(.*)/# ? $1 : "" );
            push @dest, [ $ldir, $mainFile ];
        }
    }
    unless ($foundPkgJson) {
        push @dest,
          [
            '',
            -e "$dir/package.yaml" ? "$dir/package.yaml" : "$dir/package.json"
          ];
    }

    # Install files in build dir
    foreach (@dest) {
        $self->doit_in_builddir( 'mkdir', '-p', "$path/$_->[0]" )
          unless doit_noerror( { chdir => $self->get_buildpath },
            'test', '-e', "$path/$_->[0]" );
        my $mode =
          ( ( -x $_->[1] and $_->[1] !~ $noexecFiles ) ? '755' : '644' );
        if ( -l $_->[1] ) {
            $self->doit_in_builddir( 'cp', '--reflink=auto', '-a', $_->[1],
                "$path/$_->[0]/" );
        }
        else {
            $self->doit_in_builddir( 'install', '-m', $mode, $_->[1],
                "$path/$_->[0]/" );
        }
    }
    buildPackageLock( $dir, "$path/pkgjs-lock.json", 1 );
}

sub filesFieldToList {
    my ( $self, $dir, $field ) = @_;
    return () unless $self->pjson($dir)->{$field};
    print qq{Found "$field" field in $dir/package.json, using it\n};
    if ( my $ref = ref $self->pjson($dir)->{$field} ) {
        return ( values %{ $self->pjson($dir)->{$field} } ) if $ref eq 'HASH';
        return @{ $self->pjson($dir)->{$field} };
    }
    return ( "$dir/" . $self->pjson($dir)->{$field} );
}

sub readFilesField {
    my ( $self, $dir, @lines ) = @_;
    my @files = map {
        my $prefix = '';
        $_ = $self->toJs( $dir, $_ );
        my $nowarn;
        if (s/^!//) {
            $prefix = '!';
            $nowarn = 1;
        }
        s#^\.?/##;
        warning "$dir/package.json#files: $_ does not exists\n"
          unless $nowarn
          or ( $_ and -e "$dir/$_" )
          or /[\{\*\!]/;
        $_ ? "$prefix$dir/$_" : ();
    } @lines;
    push @files,
      ( -e "$dir/package.yaml" ? "$dir/package.yaml" : "$dir/package.json" )
      unless grep { $_ eq "$dir/package.json" or $_ eq "$dir/package.yaml" }
      @files;
    return @files;
}

sub toJs {
    my ( $self, $dir, $file ) = @_;
    return (
        ( -e "$dir/$file.js" and not -e "$dir/$file" )
        ? "$file.js"
        : "$file"
    );
}

sub cmp_ordered_list {
    my ( $self, $components ) = @_;
    my $g = Graph->new;
    $components //= $self->component_list;
    $g->add_vertices( keys %$components );
    if ( -e 'debian/nodejs/build_order' ) {
        $g->add_path( $self->open_file('debian/nodejs/build_order') );
    }
    if ( -e 'debian/nodejs/component_links' ) {
        map {
            error "Malformed line $. in debian/nodejs/component_links: $_"
              unless /^([\w\-\.\/]+)\s+([\w\-\.\/]+)$/;
            $g->add_edge( $1, $2 );
        } $self->open_file('debian/nodejs/component_links');
    }
    my @res;
    eval { @res = $g->toposort };
    if ($@) {
        die
'Unable to resolve components build order: probably cyclic dependencies';
    }
    return @res;
}

# PUBLIC METHODS
# --------------

sub new {
    my $class = shift;
    return $class->SUPER::new(@_);
}

sub check_auto_buildable {
    my $self = shift;
    if ( -e 'package.json' or -e 'package.yaml' ) {
        return 1;
    }
    return 0;
}

# auto_configure step: if component are found, create node_modules links
sub configure {
    link_external_modules();
    link_internal_modules();
    link_build_modules();
}

# build step
sub build {
    my $self       = shift;
    my $components = $self->component_list;
    my @dirs       = $self->cmp_ordered_list($components);
    my $res        = 0;
    foreach my $dir ( @dirs, $self->main_package ) {
        $res += $self->build_module($dir);
    }
    unless ($res) {
        warning "Aborting auto_build\n";

        # To avoid hard transition, this step never fail
        exit 1;
    }
}

# test step: simple require or real test if declared
sub test {
    my $self       = shift;
    my $components = $self->component_list;
    my @dirs       = ( sort keys %$components );
    my @testlinks;
    my @testMods = list_test_modules();
    foreach my $mod (@testMods) {
        $self->dolink( "debian/tests/test_modules/$mod", "node_modules/$mod" );
        push @testlinks, $mod;
    }
    eval {
        if ( my $p = $self->main_package ) {
            $self->dolink( $p, 'node_modules/' . $self->pjson($p)->{name} );
            push @testlinks, $self->pjson($p)->{name};
        }
    };
    foreach (@dirs) {
        if ( -e "debian/nodejs/$_/test" ) {
            my @count = (m#(/)#g);
            print_and_doit( { chdir => $self->get_buildpath . "/$_" },
                'sh', '-ex',
                ( '../' x ( scalar(@count) + 1 ) ) . "debian/nodejs/$_/test" );
        }
    }
    my $testfile = (
        -e 'debian/nodejs/test'
        ? 'debian/nodejs/test'
        : 'debian/tests/pkg-js/test'
    );
    if ( -e $testfile ) {
        $self->doit_in_builddir( '/bin/sh', '-ex', $testfile );
    }
    elsif ( $self->main_package ) {
        if (    $self->pjson( $self->main_package )->{type}
            and $self->pjson( $self->main_package )->{type} eq 'module' )
        {
            print
"Found type=module, skipping require test (will do in autopkgtest)\n";
        }
        else {
            $self->doit_in_builddir( '/usr/bin/node', '-e',
                'require("./' . $self->main_package . '")' );
        }
    }
    foreach (@testlinks) {
        print "Removing node_modules/$_\n";
        unlink "node_modules/$_";
    }
}

# install step:
#  - if no debian/install file found, install automatically module
#  - install components

sub install {
    my $self    = shift;
    my $destdir = shift;
    my @pkgs    = grep { /\w/ } getpackages();
    my ($package) =
      $#pkgs ? ( grep { $_ =~ /^node-/ } getpackages() ) : @pkgs;
    ($package) = @pkgs unless ($package);
    my $realArchPath = (
        package_is_arch_all($package)
        ? '/usr/share/nodejs'
        : '/usr/lib/'
          . dpkg_architecture_value("DEB_HOST_MULTIARCH")
          . '/nodejs'
    );
    my $archPath = "$destdir/$realArchPath";
    my $node_module =
        $self->main_package
      ? $self->pjson( $self->main_package )->{name}
      : '';

    unless ($node_module) {
        warning <<EOT;
##############################################################
# /!\ No name found for main module, this may break install  #
# To fix this, fix main component path in debian/nodejs/main #
##############################################################
EOT
    }
    my $components = $self->component_list;
    my @dirs       = ( sort keys %$components );

    # main install
    my $path = "$archPath/$node_module";
    $self->install_module( $destdir, $archPath, $path, $self->main_package,
        @dirs )
      if $node_module;

    # Component install
    #return unless (@dirs);

    # Search root components
    my %root_cmp;
    if ( -e 'debian/nodejs/root_modules' ) {
        my @lines = $self->open_file('debian/nodejs/root_modules');
        if ( grep { $_ eq '*' } @lines ) {
            %root_cmp = map { ( $_ => 1 ) } @dirs;
        }
        else {
            %root_cmp = map {
                my $s = $_;
                map { ( $_ => 1 ) } glob($s)
            } @lines;
        }
    }
    elsif ( !$self->main_package ) {
        %root_cmp = map {
            my $s = $_;
            map { ( $_ => 1 ) } glob($s)
        } @dirs;
    }

    $path = "$path/node_modules";
    if ( -e 'debian/nodejs/submodules' ) {
        my @d = map { chomp; /^\w/ ? ( glob($_) ) : () }
          $self->open_file('debian/nodejs/submodules');
        unless (@d) {
            print
"Components auto-install is skipped by empty debian/nodejs/submodules";
            return;
        }
        my @tmp;
      CMP: foreach my $cmp (@d) {
            next CMP
              if $self->main_package and $cmp eq $self->main_package;
            foreach my $dir (@dirs) {
                if ( $dir eq $cmp or $components->{$dir} eq $cmp ) {
                    push @tmp, $dir;
                    next CMP;
                }
            }
            warning
              qq{# /!\ In debian/nodejs/submodules, "$cmp" matches nothing\n};
        }
        @dirs = @tmp;
    }

    my @provides;
    foreach my $dir (@dirs) {
        $self->install_module(
            $destdir,
            $archPath,
            (
                $root_cmp{$dir}
                ? "$destdir/$realArchPath"
                : $path
              )
              . "/$components->{$dir}",
            $dir
        );
        if ( $root_cmp{$dir} ) {
            my $tmp = 'node-' . normalize_name( $self->pjson($dir)->{name} );
            my $v;
            if ( defined( $v = $self->pjson($dir)->{version} ) ) {
                $tmp .= " (= $v)";
            }
            else {
                print STDERR
                  "# WARNING: missing version for component $tmp ($dir)\n";
            }
            push @provides, $tmp;
        }
    }
    my $pname = "node-$node_module";
    $pname =~ s/[\@_\/]/-/g;
    $pname =~ s/--*/-/g;
    if ( $package ne $pname ) {
        my $tmp = $pname;
        my $v;
        if (
            (
                   -e $self->main_package . "/package.json"
                or -e $self->main_package . "/package.yaml"
            )
            and defined( $v = $self->pjson( $self->main_package )->{version} )
          )
        {
            $tmp .= " (= $v)";
        }
        else {
            print STDERR "# No version found in main package!";
        }
        unshift @provides, $tmp;
    }
    if (@provides) {
        print "Populate \${nodejs:Provides}:\n";
        print " + $_\n" foreach (@provides);
        foreach my $pkg (@pkgs) {
            addsubstvar( $pkg, 'nodejs:Provides', join( ', ', @provides ) );
        }
    }
    if ( my $_builtUsing = builtUsing() ) {
        foreach my $pkg (@pkgs) {
            addsubstvar( $pkg, 'nodejs:BuiltUsing', $_builtUsing );
        }
    }

    my ( $in, $src );
    if ( -e 'debian/node-node-expat.substvars' ) {
        run [
            'grep', '-Po',
            'shlibs:Depends=.*libnode\d+ \(>= \K\S+(?=\))',
            'debian/node-node-expat.substvars'
          ],
          \$in, \$src;
    }
    if ( not $src ) {
        run [
            'dpkg-query', '--showformat=${source:Upstream-Version}',
            '--show',     'nodejs'
          ],
          \$in, \$src;
    }
    if ( not $src or $? ) {
        print STDERR "### node version not found\n";
    }
    else {
        chomp $src;
        foreach my $pkg (@pkgs) {
            addsubstvar( $pkg, 'nodejs:Version', $src );
        }
        print "Set \${nodejs:Version} to $src\n";
    }

    # Links
    if ( -e "debian/nodejs/links" ) {
        my $tmp = $self->auto_install_dir($package);
        map {
            my $line = $_;
            my ( $src, $dest ) =
              map { m#^/# ? $_ : "$realArchPath/$_" } split /\s+/, $line;
            unless ( $src and $dest ) {
                error "Bad line in debian/nodejs/links: $_";
            }
            print "Linking $dest to $src\n";
            make_symlink( $dest, $src, $tmp );
        } $self->open_file("debian/nodejs/links");
    }

}

# clean step: try to clean node_modules directories
sub clean {
    my $self       = shift;
    my $components = $self->component_list;
    my @dirs       = ( sort keys %$components );
    foreach my $dir ( main_package, @dirs ) {
        $self->doit_in_sourcedir( 'rm', '-rf', "$dir/node_modules/.cache",
            "$dir/.nyc_output" );
        clean_own_stuff($dir);
    }
    clean_external_modules;
    clean_internal_modules;
    clean_build_modules();
    clean_test_modules();

    # Clean test link
    if ( my $p = $self->main_package ) {
        $self->do_unlink( 'node_modules/' . $self->pjson($p)->{name} );
    }

    # Try to clean node_modules
    rmdir 'node_modules';
}

sub auto_install_dir {
    my ( $self, $package ) = @_;
    my $destdir;
    my @allpackages = getpackages();
    if ( @allpackages > 1 or not compat(14) ) {
        $destdir = "debian/tmp";
    }
    else {
        $destdir = tmpdir($package);
    }
    return $destdir;
}

1;
