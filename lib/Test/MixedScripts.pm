package Test::MixedScripts;

use utf8;

# ABSTRACT: test text for mixed and potentially confusable Unicode scripts

use v5.14;
use warnings;

use Carp          qw( croak );
use Exporter 5.57 qw( import );
use IO            qw( File );
use Unicode::UCD  qw( charscript );

use Test2::API qw( context );

our @EXPORT_OK = qw( file_scripts_ok );

=encoding utf8

=export file_scripts_ok

  file_scripts_ok( $filepath, @scripts );

This tests that the text file at C<$filepath> contains only characters in the specified C<@scripts>.
If no scripts are given, it defaults to C<Common> and C<Latin> characters.

You can override the defaults by adding a list of Unicode scripts, for example

  file_scripts_ok( $filepath, qw/ Common Latin Cyryllic / );

You can also pass options as a hash reference,

  file_scripts_ok( $filepath, { scripts => [qw/ Common Latin Cyryllic /] } );

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
        my $message = sprintf( 'Unexpected %s character on line %u character %s', $script, $lino, length($pre) + 1 );

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

1;

=head1 SEE ALSO

L<Test::PureASCII> tests that only ASCII characters are used.

=cut
