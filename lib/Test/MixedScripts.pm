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
use List::Util    qw( first );
use Unicode::UCD  qw( charinfo charscripts );

use Test2::API 1.302200 qw( context );

our @EXPORT_OK = qw( all_perl_files_scripts_ok file_scripts_ok );

our $VERSION = 'v0.3.1';

=encoding utf8

=head1 SYNOPSIS

  use Test::V0;
  use Test::MixedScripts v0.3.0 qw( all_perl_files_scripts_ok file_scripts_ok );

  all_perl_files_scripts_ok();

  file_scripts_ok( 'assets/site.js' );

  done_testing;

=head1 DESCRIPTION

This is a module to test that Perl code and other text files do not have potentially malicious or confusing Unicode
combinations.

For example, the text for the domain names "E<0x043e>nE<0x0435>.example.com" and "one.example.com" look indistinguishable in many fonts,
but the first one has Cyrillic letters.  If your software interacted with a service on the second domain, then someone
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

You can also override the default scripts with a special POD directive, which will change the scripts for all lines
(code or POD) that follow:

    =for Test::MixedScripts Latin,Cyrillic,Common

You can reset to the default scripts using:

    =for Test::MixedScripts default

You can escape the individual characters in strings and regular expressions using hex codes, for example,

   say qq{The Cyryllic "\x{043e}" looks like an "o".};

and in POD using the C<E> formatting code. For example,

    =pod

    The Cyryllic "E<0x043e>" looks like an "o".

    =cut

See L<perlpod> for more information.

When tests fail, the diagnostic message will indicate the unexpected script and where the character was in the file:

    Unexpected Cyrillic character CYRILLIC SMALL LETTER ER on line 286 character 45 in lib/Foo/Bar.pm

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

        my $info    = charinfo( ord($char) );
        my $message = sprintf(
            'Unexpected %s character %s on line %u character %u in %s',
            $info->{script},               #
            $info->{name} || "NO NAME",    #
            $lino,                         #
            length($pre) + 1,              #
            "$file"
        );

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

    my $current = $default;

    while ( my $line = $fh->getline ) {
        my $re = $current;
        # TODO custom comment prefix based on the file type
        if ( $line =~ s/\s*##\s+Test::MixedScripts\s+(\w+(?:,\w+)*).*$// ) {
            $re = _make_regex( split /,\s*/, $1 );
        }
        elsif ( $line =~ /^=for\s+Test::MixedScripts\s+(\w+(?:,\w+)*)$/ ) {
            $current = $1 eq "default" ? $default : _make_regex( split /,\s*/, $1 );
            next;
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
    state $scripts = charscripts();
    if ( my $err = first { !exists $scripts->{$_} } @_ ) {
        croak "Unknown script ${err}";
    }
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
            or $chunks[-1] eq 'tmp'                                         # tmp
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

=head2 Unicode and Perl Versions

Some scripts were added to later versions of Unicode, and supported by later versions of Perl.  This means that you
cannot run tests for some scripts on older versions of Perl.
See L<Unicode Supported Scripts|https://www.unicode.org/standard/supported.html> for a list of scripts supported
by Unicode versions.

=head2 Pod::Weaver

The C<=for> directive is not consistently copied relative to the sections that occur in by L<Pod::Weaver>.

=head2 Other Limitations

This will not identify confusable characters from the same scripts.

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
