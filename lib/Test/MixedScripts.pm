package Test::MixedScripts;

use utf8;

# ABSTRACT: test text for mixed and potentially confusable Unicode scripts

use v5.16;
use warnings;

use Carp          qw( croak );
use Cwd qw( cwd );
use Exporter 5.57 qw( import );
use File::Find;
use File::Spec;
use IO            qw( File );
use Unicode::UCD  qw( charscript );

use Test2::API 1.302200 qw( context );

our @EXPORT_OK = qw( all_perl_files_scripts_ok file_scripts_ok );

our $VERSION = 'v0.2.2';

=encoding utf8

=head1 SYNOPSIS

  use Test::MixedScripts qw( all_perl_files_scripts_ok file_scripts_ok );

  all_perl_files_scripts_ok();

  file_scripts_ok( 'assets/site.js' );

=head1 DESCRIPTION

This is a module to test that Perl code and other text files do not have potentially malicious or confusing Unicode
combinations.

For example, the text for the domain names "оnе.example.com" and "one.example.com" look indistinguishable in many fonts,
but the first one has Cyrillic letters.  If your software interactied with a service on the second domain, then someone
can operate a service on the first domain and attempt to fool developers into using their domain instead.

This might be through a malicious patch submission, or even text from an email or web page that they have convinced a
developer to copy and paste into their code.

=export file_scripts_ok

  file_scripts_ok( $filepath, @scripts );

This tests that the text file at C<$filepath> contains only characters in the specified C<@scripts>.
If no scripts are given, it defaults to C<Common> and C<Latin> characters.

You can override the defaults by adding a list of Unicode scripts, for example

  file_scripts_ok( $filepath, qw/ Common Latin Cyrillic / );

You can also pass options as a hash reference,

  file_scripts_ok( $filepath, { scripts => [qw/ Common Latin Cyrillic /] } );

A safer alternative to overriding the default scripts for a file is to specify an exception on each line using a special
comment:

   "English bŭlgarski" ## Test::MixedScripts Latin,Cyrillic,Common

=cut

sub file_scripts_ok {
    my ( $file, @args ) = @_;

    my $options = @args == 1 && ref( $args[0] ) eq "HASH" ? $args[0] : { scripts => \@args };
    $options->{scripts} //= [];
    push @{ $options->{scripts} }, qw( Latin Common ) unless defined $options->{scripts}[0];

    my $ctx = context();

    if ( my $error = _check_file_scripts( $file, $options ) ) {

        my ( $lino, $pre, $char ) = @{$error};

        # Ideally we would use charprop instead of charscript, since that supports Script_Extensions, but Unicode::UCD
        # is not dual life and charprop is only available after v5.22.0.

        my $script  = charscript( ord($char) );
        my $message =
          sprintf( 'Unexpected %s character on line %u character %s in %s', $script, $lino, length($pre) + 1, "$file" );

        $ctx->fail( $file, $message );

    }
    else {
        $ctx->pass( $file );
    }

    $ctx->release;
}

sub _check_file_scripts {
    my ( $file, $options ) = @_;

    my @scripts = @{ $options->{scripts} };
    my $default = _make_regex(@scripts);

    my $fh = IO::File->new( $file, "r" ) or croak "Cannot open ${file}: $!";

    $fh->binmode(":utf8");

    while ( my $line = $fh->getline ) {
        my $re = $default;
        # TODO custom comment prefix based on the file type
        if ( $line =~ s/\s*##\s+Test::MixedScripts\s+(\w+(?:,\w+)*).*$// ) {
            $re = _make_regex( split /,\s*/, $1 );
        }
        unless ( $line =~ $re ) {
            my $fail = _make_negative_regex(@scripts);
            $line =~ $fail;
            return [ $fh->input_line_number, ${^PREMATCH}, ${^MATCH} ];
        }
    }

    $fh->close;

    return 0;
}

sub _make_regex_set {
    return join( "", map { sprintf( '\p{scx=%s}', $_ ) } @_ );
}

sub _make_regex {
    my $set = _make_regex_set(@_);
    return qr/^[${set}]*$/u;
}

sub _make_negative_regex {
    my $set = _make_regex_set(@_);
    return qr/([^${set}])/up;
}

=export all_perl_files_scripts_ok

  all_perl_files_scripts_ok();

  all_perl_files_scripts_ok( \%options, @dirs );

This applies L</file_scripts_ok> to all of the Perl scripts in C<@dirs>, or the current directory if they are omitted.

=cut

# This code is based on code from Test::EOL v2.02, originally by Tomas Doran <bobtfish@bobtfish.net>

sub all_perl_files_scripts_ok {
    my $options = { };
    $options = shift if ref $_[0] eq 'HASH';
    my @files   = _all_perl_files(@_);
    foreach my $file (@files) {
        file_scripts_ok( $file, $options );
    }
}

sub _all_perl_files {
    my @files = _all_files(@_);
    return grep { _is_perl_module($_) || _is_perl_script($_) || _is_pod_file($_) || _is_xs_file($_) } @files;
}

sub _all_files {
    my $options = { };
    $options = shift if ref $_[0] eq 'HASH';
    my @base_dirs = @_ ? @_ : cwd();
    my @found;
    my $want_sub = sub {
        my @chunks = ( '', File::Spec->splitdir($File::Find::name) );
        return $File::Find::prune = 1
          if -d $File::Find::name
          and (
            $chunks[-1] eq 'CVS'                                            # cvs
            or $chunks[-1] eq '.svn'                                        # subversion
            or $chunks[-1] eq '.git'                                        # git
            or $chunks[-1] eq '.build'                                      # Dist::Zilla
            or $chunks[-1] eq '.mite'                                       # Mite
            or ( $chunks[-2] eq 'blib' and $chunks[-1] eq 'libdoc' )        # pod doc
            or ( $chunks[-2] eq 'blib' and $chunks[-1] =~ /^man[0-9]$/ )    # pod doc
            or $chunks[-1] eq 'local'                                       # Carton
            or $chunks[-1] eq 'inc'                                         # Module::Install
          );
        return if $chunks[-1] eq 'Build';                                   # autogenerated Build script
        return unless ( -f $File::Find::name && -r _ );
        shift @chunks;
        push @found, File::Spec->catfile(@chunks);
    };
    find(
        {
            untaint         => 1,
            untaint_pattern => qr|^([-+@\w./:\\]+)$|,
            untaint_skip    => 1,
            wanted          => $want_sub,
            no_chdir        => 1,
        },
        @base_dirs
    );
    return File::Spec->no_upwards(@found);
}

sub _is_perl_module {
    $_[0] =~ /\.pm$/i || $_[0] =~ /::/;
}

sub _is_pod_file {
    $_[0] =~ /\.pod$/i;
}

sub _is_perl_script {
    my $file = shift;
    return 1 if $file =~ /\.pl$/i;
    return 1 if $file =~ /\.t$/;
    my $fh = IO::File->new( $file, "r" ) or return;
    my $first = $fh->getline;
    return 1 if defined $first && ( $first =~ /^#!.*perl\b/ );
    return;
}

sub _is_xs_file {
    $_[0] =~ /\.(c|h|xs)$/i;
}

1;

=head1 KNOWN ISSUES

The current version does not support specifying exceptions to specific lines of POD.

=head1 SEE ALSO

L<Test::PureASCII> tests that only ASCII characters are used.

L<Unicode Confusables|https://util.unicode.org/UnicodeJsps/confusables.jsp>

L<Detecting malicious Unicode|https://daniel.haxx.se/blog/2025/05/16/detecting-malicious-unicode/>

=head1 append:BUGS

=head2 Reporting Security Vulnerabilities

Security issues should not be reported on the bugtracker website. Please see F<SECURITY.md> for instructions how to
report security vulnerabilities

=head1 append:AUTHOR

The file traversing code used in L</all_perl_files_scripts_ok> is based on code from L<Test::EOL> by Tomas Doran
<bobtfish@bobtfish.net> and others.

=cut
