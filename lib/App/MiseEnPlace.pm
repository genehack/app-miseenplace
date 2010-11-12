package App::MiseEnPlace;
# ABSTRACT: A place for everything and everything in its place

=head1 SYNOPSIS

See 'pod mise' for usage details.

=cut

use strict;
use warnings;
use 5.010;

use base 'App::Cmd::Simple';
use Carp;
use File::Basename;
use File::Path 2.08  qw/ make_path /;
use File::Path::Expand;
use Mouse;
use Try::Tiny;
use YAML        qw/ LoadFile /;

has 'bindir' => (
  is => 'rw' ,
  isa => 'Str' ,
  required => 1 ,
  default => sub { expand_filename '~/bin/' } ,
  lazy => 1 ,
);

has 'config_file' => (
  is       => 'rw' ,
  isa      => 'Str' ,
  default  => "$ENV{HOME}/.mise" ,
  lazy     => 1 ,
  required => 1 ,
);

has 'directories' => (
  is  => 'rw' ,
  isa => 'ArrayRef[Str]' ,
);

has 'homedir' => (
  is       => 'rw' ,
  isa      => 'Str' ,
  required => 1 ,
  lazy     => 1 ,
  default  => $ENV{HOME} ,
);

has 'links' => (
  is  => 'rw' ,
  isa => 'ArrayRef[ArrayRef[Str]]' ,
);

has 'verbose' => (
  is      => 'rw' ,
  isa     => 'Bool' ,
  default => 0 ,
);

sub opt_spec {
  return (
    [ 'config|C=s' => 'config file location (default = ~/.mise)' ] ,
    [ 'verbose|v' => 'be verbose' ] ,
    [ 'version|V' => 'show version' ] ,
  );
}

sub validate_args {
  my( $self , $opt , $args ) = @_;

  $self->usage_error( "No args needed" ) if @$args;

  if ( $opt->{version} ) {
    say $App::MiseEnPlace::VERSION;
    exit;
  }

  $self->config_file( $opt->{config} ) if $opt->{config};
  $self->verbose( $opt->{verbose} ) if $opt->{verbose};

}

sub execute {
  my( $self , $opt , $args ) = @_;

  $self->_load_configs;

  $self->_create_dir( $_ )  for ( @{ $self->directories } );
  $self->_create_link( $_ ) for ( @{ $self->links } );

}

sub _create_dir {
  my( $self , $dir ) = @_;

  given( $dir ) {
    when( -e -d ) {
      say "'$dir' exists" if $self->verbose;
    }
    when( -e ) {
      return if -l $dir;
      say "ERROR: Creation of '$dir' blocked by non-dirctory";
    }
    default {
      make_path $dir;
      say "Created '$dir'" if $self->verbose;
    }
  }
}

sub _create_link {
  my( $self , $linkpair ) = @_;

  my( $src , $target ) = @$linkpair;

  if ( -e -l $target ) {
    ### FIXME should make sure that target points to right src
    say "Link from '$src' to '$target' exists" if $self->verbose;
  }
  elsif ( ! -e $src ) {
    say "Not linking '$src': it does not exist" if $self->verbose;
  }
  elsif ( -e $target ) {
    say "ERROR: Creation of link from '$src' to '$target' blocked by existing file";
  }
  else {
    symlink $src , $target;
    say "Created link from $src to $target" if $self->verbose;
  }
}

sub _load_configs {
  my( $self ) = shift;

  unless ( -e $self->config_file ) {
    say "Whoops, it looks like you don't have a ~/.mise file yet.";
    say "Please review the documentation, create one, and try again.";
    exit;
  }

  my $base_config = _load_config_file( $self->config_file );

  my @links = map { _parse_linkpair( $_ , $self->homedir) }
    @{ $base_config->{create}{links} };

  my @dirs = map { _prepend_dir( $_ , $self->homedir) }
    @{ $base_config->{create}{directories} };

  my @managed_dirs = map { glob _prepend_dir( $_ , $self->homedir ) }
    @{ $base_config->{manage} };

  for my $managed_dir ( @managed_dirs ) {
    my $mise_file = "$managed_dir/.mise";
    if ( -e -r $mise_file ) {
      my $config = _load_config_file( $mise_file );

      for ( @{ $config->{create}{directories} } ) {
        push @dirs , _prepend_dir( $_ , $managed_dir );
      }

      for ( @{ $config->{create}{links} } ) {
        push @links , _parse_linkpair( $_ , $managed_dir );
      }
    }
  }

  $self->directories( \@dirs );

  $self->links( $self->_parse_create_links( \@links ) );
}

sub _load_config_file {
  my $file = shift;

  my $config;

  try { $config = LoadFile( glob($file) ) }
  catch {
    say "Failed to parse config file $file:\n\t$_";
    exit;
  };

  return $config;

}

sub _parse_create_links {
  my( $self, $link_array ) = @_;

  my( %link_targets , @links );

  for my $link_pair ( @$link_array ) {
    my( $src , $target ) = ( %$link_pair );

    my $src_base = basename( $src );

    $target = $self->bindir if $target =~ m'BIN$';
    $target = "$target$src_base" if $target =~ m|/$|;

    if (exists $link_targets{$target} ) {
      say "ERROR: Attempting to create multiple links to the same target:";
      printf "%s -> %s\n%s -> %s\n" ,
        $link_targets{$target} , $target , $src , $target;
    }

    $link_targets{$target} = $src;

    push @links , [ $src , $target ];
  }

  return \@links;

}

sub _parse_linkpair {
  confess "BAD ARGS" unless
    my( $linkpair , $dir ) = @_;

  confess "BAD LINKPAIR" unless
    my( $src , $target ) = ( %$linkpair );

  # this lets 'DIR' turn into enclosing directory
  $src = '' if $src eq 'DIR';

  $src    = _prepend_dir( $src , $dir );
  $target = _prepend_dir( $target , $dir ) unless $target eq 'BIN';

  return { $src => $target };
}

sub _prepend_dir {
  confess "BAD ARGS" unless
    my( $base , $dir ) = @_;

  return expand_filename $base if $base =~ m|^~|;
  return "$dir/$base" unless $base =~ m|^/|;
  return $base;
}

1;
