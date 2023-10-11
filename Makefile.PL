use 5.028001;
use ExtUtils::MakeMaker;

my @exe = map {chomp; $_} split /\s+/g, `ls tools/*`;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME => 'Debian::PkgJs',
    VERSION   => '0.8.14',    # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM => {},          # e.g., Module::Name => 1.1
    ABSTRACT_FROM => 'lib/Debian/PkgJs/Npm.pm',  # retrieve abstract from module
    AUTHOR        => 'xavier <yadd@debian.org>',
    EXE_FILES     => \@exe,

    #LICENSE           => 'perl',
    #Value must be from legacy list of licenses here
    #http://search.cpan.org/perldoc?Module%3A%3ABuild%3A%3AAPI
);
