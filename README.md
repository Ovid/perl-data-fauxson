![License](https://img.shields.io/github/license/ovid/perl-data-fauxson?style=flat-square)
![GitHub Actions Workflow Status](https://github.com/ovid/perl-data-fauxson/actions/workflows/linux.yml/badge.svg)

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

The primary motivation of this module was dealing with "broken" JSON that is often output
by LLMs, including trailing commas, missing closing brackets or braces, unclosed strings,

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

# EXAMPLES

## Trailing Commas

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

## Incomplete JSON

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

## Extra Text Around JSON

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

## Multiple JSON Objects

    {
        "name": "Luna",
        "species": "cat",
    }
    {
        "name": "Ovid",
        "species": "pig",
    }

On the surface, this might look like valid JSON, but it's not. It should either be
in a JSON and have each object separated by a comma or it should be in JSONL format.
Because we can't be sure what to do with this, the agove will parse, but only the 
first object will be returned.

    {
        name    => 'Luna',
        species => 'cat'
    }

See the tests for more examples.

# TRUTH

At the present time, JSON `true` and `false` are converted to Perl's `1`
and `0`.  This might change in the future if requested. There's the open
question of whether you want true booleans (newer versions of Perl) or JSON
boolean objects.

# PERFORMANCE

This module is slow due to how it parses. You probably want to use a fast JSON
parser first, in case you have valid JSON. If that fails, then you can use
this module.

# BUGS

Please report any bugs or feature requests via the GitHub issue tracker at
[https://github.com/Ovid/data-fauxson/issues](https://github.com/Ovid/data-fauxson/issues).

# SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Data::FauxSON
