# NAME

Data::FauxSON - A forgiving JSON parser that attempts to extract data from malformed JSON

# VERSION

Version 1.00

# SYNOPSIS

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

# DESCRIPTION

`Data::FauxSON` is a JSON parser designed to be forgiving of common JSON errors while
still maintaining the ability to distinguish between valid and invalid JSON. It attempts
to extract usable data even from malformed JSON, making it useful for situations where
you need to work with potentially invalid JSON data.

The parser supports both single JSON objects and JSONL format (multiple JSON objects,
one per line). It provides detailed error reporting and can handle various common JSON
errors including:

- Trailing commas
- Missing closing brackets or braces
- Unclosed strings
- Extra text around valid JSON
- Invalid characters outside strings

# METHODS

## new(%options)

Creates a new parser instance. Accepts the following options:

- jsonl => 0|1

    Set to 1 to parse JSONL format (multiple JSON objects, one per line).
    Default is 0 (single JSON object mode).

## parse($json)

Parses the provided JSON text. Returns the parser object for method chaining.

## data

Returns the parsed data structure (if any was successfully extracted).

## success

Returns true if any data was successfully extracted, even if the JSON was invalid.

## valid

Returns true only if the JSON was completely valid according to spec.

## reason

Returns an error message describing why the JSON was considered invalid, or an
empty string if no errors were found.

## Error Predicates

The following methods return true if the specific error type was encountered:

- has\_error\_no\_structure

    No valid JSON structure was found.

- has\_error\_extra\_text

    Extra text was found outside the main JSON structure.

- has\_error\_invalid\_format

    Invalid characters or format were encountered.

- has\_error\_invalid\_structure

    The JSON structure was invalid.

- has\_error\_unclosed\_string

    A string was missing its closing quote.

- has\_error\_incomplete

    The JSON structure was incomplete.

# AUTHOR

Curtis "Ovid" Poe

# BUGS

Please report any bugs or feature requests via the GitHub issue tracker at
[https://github.com/Ovid/data-fauxson/issues](https://github.com/Ovid/data-fauxson/issues).

# SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Data::FauxSON

# LICENSE AND COPYRIGHT

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
