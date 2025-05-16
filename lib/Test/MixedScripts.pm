package Test::MixedScripts;

use v5.14;
use warnings;

use Carp         qw( croak );
use Exporter     qw( import );
use IO           qw( File );
use Unicode::UCD qw( charprop );

use Test2::API qw( context );

our @EXPORT_OK = qw( file_scripts_ok );

sub file_scripts_ok {
    my ( $file, @scripts ) = @_;
    push @scripts, qw( Latin Common ) unless @scripts;

    my $ctx = context();

    if ( my $error = _check_file_scripts( $file, @scripts ) ) {

        my ( $lino, $pre, $char ) = @{$error};

        my $script  = charprop( ord($char), "Script_Extensions" );
        my $message = sprintf( 'Unexpected %s character on line %u character %s', $script, $lino, length($pre) + 1 );

        $ctx->fail( $file, $message );

    }
    else {
        $ctx->pass( $file );
    }

    $ctx->release;
}

sub _check_file_scripts {
    my ( $file, @scripts ) = @_;

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
