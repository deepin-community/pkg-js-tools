#!/usr/bin/perl
# debhelper sequence file

use warnings;
use strict;
use Debian::Debhelper::Dh_Lib;

add_command_options( "dh_auto_test",      "--buildsystem=nodejs" );
add_command_options( "dh_auto_configure", "--buildsystem=nodejs" );
add_command_options( "dh_auto_build",     "--buildsystem=nodejs" );
add_command_options( "dh_auto_install",   "--buildsystem=nodejs" );
add_command_options( "dh_auto_clean",     "--buildsystem=nodejs" );
insert_before( 'dh_gencontrol', 'dh_nodejs_substvars' );

1;
