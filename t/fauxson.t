#!/usr/bin/env perl

use v5.20.0;
use Test::Most;
use experimental 'signatures';
use Data::FauxSON;

subtest 'Basic Valid JSON' => sub {
    my $json = <<~'END_JSON';
        {
            "name": "Luna",
            "species": "cat",
            "age": 3,
            "color": "black",
            "favorite_toys": ["laser pointer", "mouse", "yarn"]
        }
    END_JSON

    my $parser = Data::FauxSON->new;
    $parser->parse($json);

    ok $parser->success, 'parsing succeeded';
    ok $parser->valid,   'JSON is valid';
    is $parser->reason, '', 'no error message';

    my $expected = {
        name          => 'Luna',
        species       => 'cat',
        age           => 3,
        color         => 'black',
        favorite_toys => [ 'laser pointer', 'mouse', 'yarn' ]
    };

    eq_or_diff $parser->data, $expected, 'data structure matches expected';
};

subtest 'Trailing Commas' => sub {
    my $json = <<~'END_JSON';
        {
            "name": "Luna",
            "species": "cat",
            "age": 3,
            "color": "black",
            "favorite_toys": ["laser pointer", "mouse", "yarn",],
        }
    END_JSON

    my $parser = Data::FauxSON->new;
    $parser->parse($json);

    ok $parser->success, 'parsing succeeded';
    #ok !$parser->valid,  'JSON is not valid';
    is $parser->reason, '', 'no error message despite invalid JSON';

    my $expected = {
        name          => 'Luna',
        species       => 'cat',
        age           => 3,
        color         => 'black',
        favorite_toys => [ 'laser pointer', 'mouse', 'yarn' ]
    };

    eq_or_diff $parser->data, $expected, 'data structure matches expected';
};

subtest 'Incomplete JSON' => sub {
    my $json = <<'END_JSON';
        {
            "name": "Ovid",
            "species": "pig",
            "age": 8,
            "favorite_toys": ["mud", "bone
END_JSON

    my $parser = Data::FauxSON->new;
    $parser->parse($json);

    ok defined $parser->data, 'Partial data extracted';

    ok $parser->success, 'parsing succeeded';
    ok !$parser->valid,   'JSON is not valid';
    like $parser->reason, qr/Unclosed string starting at "bone/, 'appropriate error message';

    my $expected = {
        name          => 'Ovid',
        species       => 'pig',
        age           => 8,
        favorite_toys => [ 'mud', 'bone' ],
    };

    eq_or_diff $parser->data, $expected, 'data structure matches expected';
};

subtest 'Corrupted JSON' => sub {
    my $json = <<'END_JSON';
        {
            name = "Luna"
            'age': 3,
            species: cat,
            "colors": [
                red;
                brown
                "black"
        }
END_JSON

    my $parser = Data::FauxSON->new;
    $parser->parse($json);

    ok !defined $parser->data, 'no data extracted';
    ok !$parser->success, 'parsing failed';
    ok !$parser->valid,   'JSON is not valid';
    like $parser->reason, qr/Failed to parse/, 'appropriate error message';
};

subtest 'JSONL Format' => sub {
    my $jsonl = <<'END_JSONL';
{"name": "Alice", "age": 25, "city": "Seattle"}
{"name": "Bob", "points": 42, "active": true}
{"timestamp": "2024-03-11", "status": "complete", "count": 17}
END_JSONL

    my $parser = Data::FauxSON->new( jsonl => 1 );
    $parser->parse($jsonl);

    ok $parser->success, 'parsing succeeded';
    ok $parser->valid,   'JSONL is valid';
    is_deeply $parser->reason, [], 'no error messages';

    my $expected = [
        { name      => 'Alice',      age    => 25,         city   => 'Seattle' },
        { name      => 'Bob',        points => 42,         active => 1 },
        { timestamp => '2024-03-11', status => 'complete', count  => 17 }
    ];

    eq_or_diff $parser->data, $expected, 'data structure matches expected';
};

subtest 'Extra Text Around JSON' => sub {
    my $json = <<'END_JSON';
        Here's the JSON you asked for!

        {
            "name": "Luna",
            "species": "cat",
            "age": 3,
            "color": "black",
            "favorite_toys": ["laser pointer", "mouse", "yarn"]
        }

        I hope you like it!
END_JSON

    my $parser = Data::FauxSON->new;
    $parser->parse($json);

    ok $parser->success, 'parsing succeeded';
    ok !$parser->valid,  'JSON is not valid due to extra text';
    like $parser->reason, qr/extra text/, 'notes extra text in reason';

    my $expected = {
        name          => 'Luna',
        species       => 'cat',
        age           => 3,
        color         => 'black',
        favorite_toys => [ 'laser pointer', 'mouse', 'yarn' ]
    };

    eq_or_diff $parser->data, $expected, 'data structure matches expected';
};

subtest 'Trailing Garbage' => sub {
    my $json = <<'END_JSON';
        {
            "name": "Luna",
            "species": "cat",
            "age": 3,
            "color": "black",
            "favorite_toys": ["laser pointer", "mouse", "yarn"]
        }-{}
END_JSON

    my $parser = Data::FauxSON->new;
    $parser->parse($json);

    ok $parser->success, 'parsing succeeded';
    ok !$parser->valid,  'JSON is not valid due to trailing garbage';
    like $parser->reason, qr/extra text/, 'notes extra text in reason';

    my $expected = {
        name          => 'Luna',
        species       => 'cat',
        age           => 3,
        color         => 'black',
        favorite_toys => [ 'laser pointer', 'mouse', 'yarn' ]
    };

    eq_or_diff $parser->data, $expected, 'data structure matches expected';
};

subtest 'Edge Cases' => sub {
    subtest 'Empty Input' => sub {
        my $parser = Data::FauxSON->new;
        $parser->parse('');

        ok !$parser->success, 'parsing failed';
        ok !$parser->valid,   'empty input is not valid';
        like $parser->reason, qr/No valid JSON/, 'appropriate error message';
    };

    subtest 'Whitespace Only' => sub {
        my $parser = Data::FauxSON->new;
        $parser->parse("   \n   \t   ");

        ok !$parser->success, 'parsing failed';
        ok !$parser->valid,   'whitespace only is not valid';
        like $parser->reason, qr/No valid JSON/, 'appropriate error message';
    };

    subtest 'Invalid Characters Outside String' => sub {
        my $parser = Data::FauxSON->new;
        $parser->parse('{ "test": true } @#$%');

        ok $parser->success, 'parsing succeeded';
        ok !$parser->valid,  'invalid due to extra characters';
        like $parser->reason, qr/extra text/, 'notes extra text in reason';

        eq_or_diff $parser->data, { test => 1 }, 'correct data extracted';
    };

    subtest 'Multiple JSON Objects (Non-JSONL)' => sub {
        my $parser = Data::FauxSON->new;
        $parser->parse('{"a":1}{"b":2}');

        ok $parser->success, 'parsing succeeded';
        ok !$parser->valid,  'invalid due to multiple objects';
        like $parser->reason, qr/extra text/, 'notes extra text in reason';

        eq_or_diff $parser->data, { a => 1 }, 'first object extracted';
    };
};

done_testing;
