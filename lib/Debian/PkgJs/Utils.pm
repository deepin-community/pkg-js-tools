package Debian::PkgJs::Utils;

use strict;
use base 'Exporter';
use Dpkg::IPC;
use File::Path qw(make_path);
use JSON;

our @EXPORT = qw(
  clean_build_modules
  clean_test_modules
  component_list
  link_build_modules
  link_test_modules
  list_build_modules
  list_test_modules
  ln
  normalize_name
  normalize_name_strict
  open_file
  main_package
  pjson
);

sub open_file {
    my $file = pop;
    die "Missing file arg" unless $file;
    my $f;
    open( $f, $file ) or die $!;
    my @lines = map {
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
    die 'Malformed debian/nodejs/main'              if @lines > 1;
    print STDERR "Missing main directory $lines[0]" if @lines and !-d $lines[0];
    $main_p = $lines[0] || '';
    return @lines;
}

# package.json cache
sub pjson {
    my $dir = pop;
    unless ( -e "$dir/package.json" ) {
        print STDERR "/!\\ $dir/package.json not found\n";
        $json{$dir} = {};
    }
    else {
        return $json{$dir} if $json{$dir};
        my $pkgjson;
        open $pkgjson, "$dir/package.json";
        my $content = join '', <$pkgjson>;
        close $pkgjson;
        $json{$dir} = JSON::from_json($content);
    }
    if ( -e "debian/nodejs/$dir/name" ) {
        $json{$dir}->{name} =
          [ open_file("debian/nodejs/$dir/name") ]->[0];
    }
    return $json{$dir};
}

sub component_list {
    my ( @components, %packages );
    if ( -e 'debian/watch' ) {
        map { push @components, $1 if (/component=([\w\-\.]+)/) }
          open_file('debian/watch');
    }
    if ( -e 'debian/nodejs/additional_components' ) {
        print "Found debian/nodejs/additional_components\n";
        map {
            print 'Adding component(s): ' . join( ', ', glob($_) ) . "\n";
            push @components, glob($_)
        } open_file('debian/nodejs/additional_components');
    }
    foreach my $component (@components) {
        next if main_package() and $component eq main_package();
        if ( -d $component ) {
            my $package;
            eval { $package = pjson($component)->{name} };
            if ( $@ or !$package ) {
                print STDERR "Unable to load $component: $@";
                next;
            }
            $packages{$component} = $package;
        }
        else {
            print STDERR "Can't find $component directory in " . `pwd`;
            next;
        }
    }
    return \%packages;
}

sub ln {
    my $module = pop;
    die "Missing module arg" unless $module;
    my $path;
    spawn(
        exec       => [ 'nodepath', $module ],
        to_string  => \$path,
        wait_child => 1,
    );
    chomp $path;
    my $rpath = $path;
    $rpath =~ s#.*?nodejs/##;
    my $count = scalar( $rpath =~ m#(/)#g );
    $rpath =~ s#[^/]*$##;
    $rpath = "node_modules/$rpath";
    $rpath =~ s#/$##;
    spawn( exec => [ 'mkdir', '-p', $rpath ], wait_child => 1 );
    $rpath = "node_modules/$module";
    my $res = symlink $path, $rpath;

    if ( $res == 0 ) {
        return undef;
    }
    return 1;
}

sub link_build_modules {
    _link_modules('debian/build_modules');
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

sub clean_test_modules {
    return _cleanMods('debian/tests/test_modules');
}

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
    opendir my $d, $dir;
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
        print "Link $dst -> $src\n";
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

1;
