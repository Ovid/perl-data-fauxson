package Data::FauxSON;

# ABSTRACT: A forgiving JSON parser that attempts to extract data from malformed JSON

use Moo;                          # Modern OO framework
use experimental 'signatures';    # Enable parameter signatures

our $VERSION = '1.00';

# Whatever you last tried to parse
has original_json => (
    is => 'rwp',
);

# Flag indicating if this is processing JSONL format (multiple JSON objects, one per line)
has jsonl => (
    is      => 'ro',              # Read-only attribute
    default => sub {0},           # Default to single JSON mode
);

# Holds the parsed data structure (could be hashref, arrayref, or scalar)
has data => (
    is      => 'rwp',             # Read-write private
    default => sub {undef},       # Initially undefined
);

# Indicates if any data was successfully extracted, even if JSON was invalid
has success => (
    is      => 'rwp',
    default => sub {0},
);

# Indicates if the JSON was completely valid according to spec
has valid => (
    is      => 'rwp',
    default => sub {0},
);

# Internal storage for error messages
has _reason => (
    is      => 'rw',
    default => sub {''},
);

# Storage for numeric error codes
has error_codes => (
    is      => 'rwp',
    default => sub { [] },
);

# Define error code constants for different types of parsing failures
use constant {
    ERR_NONE              => 0,    # No error
    ERR_NO_STRUCTURE      => 1,    # No valid JSON structure found
    ERR_EXTRA_TEXT        => 2,    # Text outside main JSON structure
    ERR_INVALID_FORMAT    => 3,    # Invalid characters or format
    ERR_INVALID_STRUCTURE => 4,    # Structurally invalid JSON
    ERR_UNCLOSED_STRING   => 5,    # String missing closing quote
    ERR_INCOMPLETE        => 6,    # Incomplete JSON structure
};

# Helper method to add error codes to the current list
sub _push_error_codes( $self, @codes ) {
    push $self->error_codes->@*, @codes;
}

# Predicate methods to check for specific types of errors
sub has_error_no_structure($self) {
    return grep { ERR_NO_STRUCTURE == $_ } $self->error_codes->@*;
}

sub has_error_extra_text($self) {
    return grep { ERR_EXTRA_TEXT == $_ } $self->error_codes->@*;
}

sub has_error_invalid_format($self) {
    return grep { ERR_INVALID_FORMAT == $_ } $self->error_codes->@*;
}

sub has_error_invalid_structure($self) {
    return grep { ERR_INVALID_STRUCTURE == $_ } $self->error_codes->@*;
}

sub has_error_unclosed_string($self) {
    return grep { ERR_UNCLOSED_STRING == $_ } $self->error_codes->@*;
}

sub has_error_incomplete($self) {
    return grep { ERR_INCOMPLETE == $_ } $self->error_codes->@*;
}

# Public accessor for error messages
sub reason($self) { $self->_reason }

# Main entry point for parsing JSON data
sub parse ( $self, $json ) {
    $self->_set_original_json($json);
    $json =~ s/^\s+|\s+$//g;    # trim leading and trailing whitespace
    return $self->_parse_jsonl($json) if $self->jsonl;
    return $self->_parse_single($json);
}

# Handles parsing of JSONL format (multiple JSON objects, one per line)
sub _parse_jsonl ( $self, $json ) {
    my @lines = split /\n/, $json;
    my @data;
    my @reasons;
    my $all_valid = 1;

    # Process each line independently
    foreach my $line (@lines) {
        next unless $line =~ /\S/;    # skip blank lines
        $self->_parse_single($line);
        if ( $self->success ) {
            push @data, $self->data;
            $all_valid &&= $self->valid;
            push @reasons, $self->reason if $self->reason;
        }
        else {
            push @reasons, $self->reason;
            $all_valid = 0;
        }
    }

    # Set overall results
    $self->_set_data( \@data );
    $self->_set_success( @data > 0 );
    $self->_set_valid( $all_valid && @data > 0 );
    $self->_reason( join "\n", @reasons ) if @reasons;
    return $self;
}

# Tokenizes JSON text into a sequence of tokens
sub _tokenize( $self, $text ) {
    my @tokens;
    my $pos = 0;
    my $len = length($text);
    my $last_string;
    my $max_tokens  = 10000;    # safeguard against infinite loops
    my $token_count = 0;

    while ( $pos < $len && $token_count < $max_tokens ) {
        $token_count++;
        my $char = substr( $text, $pos, 1 );

        # Skip whitespace
        if ( $char =~ /\s/ ) {
            $pos++;
            next;
        }

        # Handle structural characters
        if ( $char =~ /[{}\[\]:,]/ ) {
            push @tokens, $char;
            $pos++;
            next;
        }

        # Handle strings
        if ( $char eq '"' ) {
            my $string = '';
            my $start  = substr( $text, $pos );
            $pos++;    # Skip opening quote
            my $found_end = 0;

            # Process string contents
            while ( $pos < $len && !$found_end ) {
                $char = substr( $text, $pos, 1 );
                if ( $char eq '"' && substr( $text, $pos - 1, 1 ) ne '\\' ) {
                    $found_end = 1;
                    last;
                }
                $string .= $char;
                $pos++;
            }

            if ($found_end) {
                $pos++;    # Skip closing quote
                push @tokens, [ 'STRING', $string ];
            }
            else {
                # Handle unclosed string
                push @tokens, [ 'STRING', $string ];
                $last_string = $start =~ /^"([^"\s]+)/ ? $1 : '';
            }
            next;
        }

        # Handle literals (true/false/null)
        if ( substr( $text, $pos ) =~ /^(true|false|null)(?![a-zA-Z])/ ) {
            my $value = $1;
            push @tokens, [ 'LITERAL', $value ];
            $pos += length($value);
            next;
        }

        # Handle numbers
        if ( $char =~ /[-\d]/ ) {
            my $number = '';
            while ( $pos < $len && substr( $text, $pos, 1 ) =~ /[-\d.]/ ) {
                $number .= substr( $text, $pos, 1 );
                $pos++;
            }
            if ( $number =~ /^-?\d+(?:\.\d+)?$/ ) {
                push @tokens, [ 'NUMBER', $number ];
            }
            next;
        }

        # Skip invalid characters
        $pos++;
    }

    return ( \@tokens, $last_string );
}

# Parses a sequence of tokens into a data structure
sub _parse_tokens( $self, $tokens ) {
    my $pos      = 0;
    my $complete = 1;

    # Recursive value parser
    my $parse_value;
    $parse_value = sub {
        return undef if $pos >= @$tokens;

        my $token = $tokens->[ $pos++ ];
        return undef unless defined $token;

        # Handle typed tokens (STRING, NUMBER, LITERAL)
        if ( ref $token eq 'ARRAY' ) {
            my ( $type, $value ) = @$token;
            if ( $type eq 'STRING' ) {
                return $value;
            }
            elsif ( $type eq 'NUMBER' ) {
                return $value + 0;
            }
            elsif ( $type eq 'LITERAL' ) {
                return 1     if $value eq 'true';
                return 0     if $value eq 'false';
                return undef if $value eq 'null';
            }
        }

        # Handle arrays
        if ( $token eq '[' ) {
            my @array;
            while ( $pos < @$tokens && $tokens->[$pos] ne ']' ) {
                my $value = $parse_value->();
                push @array, $value if defined $value;
                if ( $pos < @$tokens && $tokens->[$pos] eq ',' ) {
                    $pos++;
                }
            }
            if ( $pos >= @$tokens ) {
                $complete = 0;
            }
            else {
                $pos++;    # skip ']'
            }
            return \@array;
        }

        # Handle objects
        if ( $token eq '{' ) {
            my %hash;
            while ( $pos < @$tokens && $tokens->[$pos] ne '}' ) {
                my $key = $tokens->[$pos];
                if ( ref $key eq 'ARRAY' && $key->[0] eq 'STRING' ) {
                    $pos++;    # move past key
                    if ( $pos < @$tokens && $tokens->[$pos] eq ':' ) {
                        $pos++;
                    }
                    my $value = $parse_value->();
                    $hash{ $key->[1] } = $value if defined $value;
                }
                else {
                    # Skip invalid keys
                    $pos++;
                }
                if ( $pos < @$tokens && $tokens->[$pos] eq ',' ) {
                    $pos++;
                }
            }
            if ( $pos >= @$tokens ) {
                $complete = 0;
            }
            else {
                $pos++;    # skip '}'
            }
            return \%hash;
        }

        return $token;    # Return unexpected tokens as-is
    };

    # Parse the main value
    my $data;
    {
        local $@;
        $data = eval { $parse_value->() };
        if ($@) {
            return ( undef, 0 );
        }
    }

    # Check for extra tokens
    if ( defined $data && $pos < @$tokens ) {
        $complete = 0;
        $self->_reason("Found extra text outside JSON structure") unless $self->reason;
        $self->_push_error_codes(ERR_EXTRA_TEXT);
    }

    return ( $data, $complete );
}

# Reset parser state
sub _reset_state($self) {
    $self->_set_error_codes( [] );
    $self->_set_data(undef);
    $self->_set_success(0);
    $self->_set_valid(0);
    $self->_reason('');
}

# Parse a single JSON object
sub _parse_single ( $self, $json ) {
    $self->_reset_state;

    # Handle empty input
    if ( $json =~ /^\s*$/ ) {
        $self->_reason("No valid JSON structure found");
        $self->_push_error_codes(ERR_NO_STRUCTURE);
        return $self;
    }

    # Find start of JSON structure
    my $start;
    if ( $json =~ /([\{\[])/ ) {
        $start = $-[1];
    }
    else {
        $self->_reason("No valid JSON structure found");
        $self->_push_error_codes(ERR_NO_STRUCTURE);
        return $self;
    }

    # Extract and analyze the structure
    my $extract    = substr( $json, $start );
    my $depth      = 0;
    my $in_string  = 0;
    my $escape     = 0;
    my $end_pos    = -1;
    my $first_char = substr( $extract, 0, 1 );

    # Find matching closing bracket/brace
    for my $i ( 0 .. length($extract) - 1 ) {
        my $c = substr( $extract, $i, 1 );

        # Handle string boundaries
        if ( $c eq '"' && !$escape ) {
            $in_string = !$in_string;
        }

        # Track escape sequences in strings
        if ($in_string) {
            $escape = ( !$escape && $c eq '\\' );
            next;
        }

        # Skip whitespace outside strings
        next if $c =~ /\s/;

        # Track structure depth
        if ( $c eq '{' or $c eq '[' ) {
            $depth++;
        }
        elsif ( $c eq '}' or $c eq ']' ) {
            $depth--;
            if ( $depth == 0 ) {
                $end_pos = $i;
                last;
            }
        }
    }

    # Handle incomplete structures
    if ( $end_pos == -1 ) {
        $end_pos = length($extract) - 1;
    }

    my $main_json = substr( $extract, 0, $end_pos + 1 );

    # Clean up common issues
    $main_json =~ s/,(\s*[\]}])/$1/g;    # Remove trailing commas

    # Validate character usage
    {
        my $check_str = 0;
        my $esc       = 0;
        for ( my $i = 0; $i < length($main_json); $i++ ) {
            my $ch = substr( $main_json, $i, 1 );
            if ( $ch eq '"' && !$esc ) {
                $check_str = !$check_str;
            }
            $esc = ( !$esc && $ch eq '\\' );
            next if $check_str;    # inside string

            if ( $ch eq '=' || $ch eq ';' || $ch eq '\'' ) {
                $self->_reason("Failed to parse: Invalid JSON format");
                $self->_push_error_codes(ERR_INVALID_FORMAT);
                return $self;
            }
        }
    }

    # Tokenize and parse
    my ( $tokens, $last_string ) = $self->_tokenize($main_json);
    unless (@$tokens) {
        $self->_reason("Failed to parse: No valid JSON structure found");
        $self->_push_error_codes(ERR_NO_STRUCTURE);
        return $self;
    }

    my ( $data, $complete ) = $self->_parse_tokens($tokens);

    # Handle parse failures
    if ( !defined $data ) {
        $self->_reason("Failed to parse: Invalid JSON structure") unless $self->reason;
        $self->_push_error_codes(ERR_INVALID_STRUCTURE);
        return $self;
    }

    # Store successful parse
    $self->_set_data($data);
    $self->_set_success(1);

    # Handle unclosed strings
    if ($last_string) {
        $self->_set_valid(0);
        $self->_reason("Unclosed string starting at \"$last_string");
        $self->_push_error_codes(ERR_UNCLOSED_STRING);
        return $self;
    }

    # Handle incomplete structures
    if ( !$complete && !$self->reason ) {
        $self->_reason("Incomplete JSON structure");
        $self->_push_error_codes(ERR_INCOMPLETE);
    }

    # Check for surrounding text
    my $structure_end_index = $start + $end_pos;
    my $before              = substr( $json, 0, $start );
    my $after               = substr( $json, $structure_end_index + 1 );

    # Handle extra text
    if ( $before =~ /\S/ || $after =~ /\S/ ) {
        $self->_set_valid(0);
        $self->_reason("Found extra text outside JSON structure");
        $self->_push_error_codes(ERR_EXTRA_TEXT);
        return $self;
    }

    # Set valid flag if no errors encountered
    $self->_set_valid( !$self->reason );

    return $self;
}

1;

__END__

=head1 NAME

Data::FauxSON - A forgiving JSON parser that attempts to extract data from malformed JSON

=head1 VERSION

Version 1.00

=head1 SYNOPSIS

    use Data::FauxSON;
    
    # Create a parser
    my $parser = Data::FauxSON->new;
    
    # Parse a single JSON object
    $parser->parse($json);
    
    if ($parser->success) {
        my $data = $parser->data;
        if ($parser->valid) {
            say "Valid JSON parsed successfully";
        } else {
            say "Warning: ", $parser->reason;
            say "Extracted data anyway: ", explain($data);
        }
    }
    
    # Parse JSONL (multiple JSON objects, one per line)
    my $jsonl_parser = Data::FauxSON->new(jsonl => 1);
    $jsonl_parser->parse($jsonl_text);

=head1 DESCRIPTION

C<Data::FauxSON> is a JSON parser designed to be forgiving of common JSON errors while
still maintaining the ability to distinguish between valid and invalid JSON. It attempts
to extract usable data even from malformed JSON, making it useful for situations where
you need to work with potentially invalid JSON data.

The parser supports both single JSON objects and JSONL format (multiple JSON objects,
one per line). It provides detailed error reporting and can handle various common JSON
errors including:

The primary motivation of this module was dealing with "broken" JSON that is often output
by LLMs, including trailing commas, missing closing brackets or braces, unclosed strings,

=over 4

=item * Trailing commas

=item * Missing closing brackets or braces

=item * Unclosed strings

=item * Extra text around valid JSON

=item * Invalid characters outside strings

=back

=head1 METHODS

=head2 new(%options)

Creates a new parser instance. Accepts the following options:

=over 4

=item * jsonl => 0|1

Set to 1 to parse JSONL format (multiple JSON objects, one per line).
Default is 0 (single JSON object mode).

=back

=head2 parse($json)

Parses the provided JSON text. Returns the parser object for method chaining.

=head2 data

Returns the parsed data structure (if any was successfully extracted).

=head2 success

Returns true if any data was successfully extracted, even if the JSON was invalid.

=head2 valid

Returns true only if the JSON was completely valid according to spec.

=head2 reason

Returns an error message describing why the JSON was considered invalid, or an
empty string if no errors were found.

=head2 Error Predicates

The following methods return true if the specific error type was encountered:

=over 4

=item * has_error_no_structure

No valid JSON structure was found.

=item * has_error_extra_text

Extra text was found outside the main JSON structure.

=item * has_error_invalid_format

Invalid characters or format were encountered.

=item * has_error_invalid_structure

The JSON structure was invalid.

=item * has_error_unclosed_string

A string was missing its closing quote.

=item * has_error_incomplete

The JSON structure was incomplete.

=back

=head1 EXAMPLES

=head2 Trailing Commas

    {
        "name": "Luna",
        "species": "cat",
        "alive": true,
        "age": 3,
        "color": "black",
        "favorite_toys": ["laser pointer", "mouse", "yarn",],
    }

Trailing commas are ignored. The above parses as:

    {
        name          => 'Luna',
        species       => 'cat',
        alive         => 1,
        age           => 3,
        color         => 'black',
        favorite_toys => [ 'laser pointer', 'mouse', 'yarn' ]
    };

=head2 Incomplete JSON

    {
        "name": "Ovid",
        "species": "pig",
        "age": 8,
        "favorite_toys": ["mud", "bone

Incomplete JSON is handled gracefully (for some values of "gracefully"). The above parses as:

    {
        name          => 'Ovid',
        species       => 'pig',
        age           => 8,
        favorite_toys => [ 'mud', 'bone' ]
    };

Often, an LLM will stop generating JSON in the middle of a line, so the last
line of JSON will be incomplete.  This can be caused by a variety of reasons,
including a "max tokens" parameter being passed to the LLM. Often this can be
"repaired" by simply passing the word "continue" to the LLM and it will pick
up where it left off. However, if the JSON you've already received has bad
data, such as a bad ID or a bad timestamp, asking the LLM to "continue" to
generate bad data is a waste of money and CPU.

This gives you a chance to inspect what little you have and decide if it's
worth asking the LLM to continue.

=head2 Extra Text Around JSON

    Here's the JSON you asked for!

    {
        "name": "Luna",
        "species": "cat",
        "age": 3,
        "color": "black",
        "favorite_toys": ["laser pointer", "mouse", "yarn"]
    }

    I hope you like it!

The above returns:

    {
        name          => 'Luna',
        species       => 'cat',
        age           => 3,
        color         => 'black',
        favorite_toys => [ 'laser pointer', 'mouse', 'yarn' ]
    };

Typically, you can tell the LLM something like "Only output the JSON, do not
include anything else" and it will only give you the JSON. Sometimes that
works. Other times, it doesn't. This module tried to take that into account.

This also means that things like this (which we've gotten from Claude), will
parse as "expected":

    {
        "name": "Luna",
        "species": "cat",
        "age": 3,
        "color": "black",
        "favorite_toys": ["laser pointer", "mouse", "yarn"]
    }"}}

=head2 Multiple JSON Objects

    {
        "name": "Luna",
        "species": "cat",
    }
    {
        "name": "Ovid",
        "species": "pig",
    }

On the surface, this looks like invalid JSON, but it's not valid. It should either be
in a JSON and have each object separated by a comma or it should be in JSONL format.
Because we can't be sure what to do with this, the agove will parse, but only the 
first object will be returned.

    {
        name    => 'Luna',
        species => 'cat'
    }

See the tests for more examples.

=head1 TRUTH

At the present time, JSON C<true> and C<false> are converted to Perl's C<1>
and C<0>.  This might change in the future if requested. There's the open
question of whether you want true booleans (newer versions of Perl) or JSON
boolean objects.

=head1 PERFORMANCE

This module is slow due to how it parses. You probably want to use a fast JSON
parser first, in case you have valid JSON. If that fails, then you can use
this module.

=head1 AUTHOR

Curtis "Ovid" Poe

=head1 BUGS

Please report any bugs or feature requests via the GitHub issue tracker at
L<https://github.com/Ovid/data-fauxson/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Data::FauxSON

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2024 by Curtis "Ovid" Poe.

This is free software, licensed under:

The MIT License (MIT)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=cut
