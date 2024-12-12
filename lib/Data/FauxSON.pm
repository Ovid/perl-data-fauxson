
package Data::FauxSON;
use Moo;
use experimental 'signatures';

has jsonl => (
    is      => 'ro',
    default => sub { 0 },
);

has data => (
    is      => 'rwp',
    default => sub { undef },
);

has success => (
    is      => 'rwp',
    default => sub { 0 },
);

has valid => (
    is      => 'rwp',
    default => sub { 0 },
);

has _reason => (
    is      => 'rw',
    default => sub { '' },
);

sub reason($self) { $self->_reason }

sub parse ( $self, $json ) {
    $json =~ s/^\s+|\s+$//g;  # trim leading and trailing whitespace
    return $self->_parse_jsonl($json) if $self->jsonl;
    return $self->_parse_single($json);
}

sub _parse_jsonl ( $self, $json ) {
    my @lines = split /\n/, $json;
    my @data;
    my @reasons;
    my $all_valid = 1;

    foreach my $line (@lines) {
        next unless $line =~ /\S/;    # skip blank lines
        my $parser = Data::FauxSON->new;
        $parser->_parse_single($line);
        if ($parser->success) {
            push @data, $parser->data;
            $all_valid &&= $parser->valid;
            push @reasons, $parser->reason if $parser->reason;
        }
        else {
            push @reasons, $parser->reason;
            $all_valid = 0;
        }
    }

    $self->_set_data(\@data);
    $self->_set_success(@data > 0);
    $self->_set_valid($all_valid && @data > 0);
    $self->_reason(\@reasons);
    return $self;
}

sub _tokenize($self, $text) {
    my @tokens;
    my $pos = 0;
    my $len = length($text);
    my $last_string;
    my $max_tokens = 10000; # safeguard against infinite loops
    my $token_count = 0;
    
    while ($pos < $len && $token_count < $max_tokens) {
        $token_count++;
        my $char = substr($text, $pos, 1);
        
        if ($char =~ /\s/) {
            $pos++;
            next;
        }
        
        if ($char =~ /[{}\[\]:,]/) {
            push @tokens, $char;
            $pos++;
            next;
        }
        
        if ($char eq '"') {
            my $string = '';
            my $start = substr($text, $pos);
            $pos++;  # Skip opening quote
            my $found_end = 0;
            
            while ($pos < $len && !$found_end) {
                $char = substr($text, $pos, 1);
                if ($char eq '"' && substr($text, $pos-1, 1) ne '\\') {
                    $found_end = 1;
                    last;
                }
                $string .= $char;
                $pos++;
            }
            
            if ($found_end) {
                $pos++;  # Skip closing quote
                push @tokens, ['STRING', $string];
            } else {
                # Unclosed string
                push @tokens, ['STRING', $string];
                $last_string = $start =~ /^"([^"\s]+)/ ? $1 : '';
            }
            next;
        }
        
        # Handle true/false/null
        if (substr($text, $pos) =~ /^(true|false|null)(?![a-zA-Z])/) {
            my $value = $1;
            push @tokens, ['LITERAL', $value];
            $pos += length($value);
            next;
        }
        
        # Handle numbers
        if ($char =~ /[-\d]/) {
            my $number = '';
            while ($pos < $len && substr($text, $pos, 1) =~ /[-\d.]/) {
                $number .= substr($text, $pos, 1);
                $pos++;
            }
            if ($number =~ /^-?\d+(?:\.\d+)?$/) {
                push @tokens, ['NUMBER', $number];
            }
            next;
        }
        
        # Invalid character outside strings: skip it
        $pos++;
    }
    
    return (\@tokens, $last_string);
}

sub _parse_tokens($self, $tokens) {
    my $pos = 0;
    my $complete = 1;
    
    my $parse_value; 
    $parse_value = sub {
        return undef if $pos >= @$tokens;
        
        my $token = $tokens->[$pos++];
        return undef unless defined $token;
        
        if (ref $token eq 'ARRAY') {
            my ($type, $value) = @$token;
            if ($type eq 'STRING') {
                return $value;
            } elsif ($type eq 'NUMBER') {
                return $value+0;
            } elsif ($type eq 'LITERAL') {
                return 1 if $value eq 'true';
                return 0 if $value eq 'false';
                return undef if $value eq 'null';
            }
        }
        
        if ($token eq '[') {
            my @array;
            while ($pos < @$tokens && $tokens->[$pos] ne ']') {
                my $value = $parse_value->();
                push @array, $value if defined $value;
                if ($pos < @$tokens && $tokens->[$pos] eq ',') {
                    $pos++;
                }
            }
            if ($pos >= @$tokens) {
                $complete = 0;
            } else {
                $pos++; # skip ']'
            }
            return \@array;
        }
        
        if ($token eq '{') {
            my %hash;
            while ($pos < @$tokens && $tokens->[$pos] ne '}') {
                my $key = $tokens->[$pos];
                if (ref $key eq 'ARRAY' && $key->[0] eq 'STRING') {
                    $pos++; # move past key
                    if ($pos < @$tokens && $tokens->[$pos] eq ':') {
                        $pos++;
                    }
                    my $value = $parse_value->();
                    $hash{$key->[1]} = $value if defined $value;
                } else {
                    # invalid key or no colon
                    $pos++;
                }
                if ($pos < @$tokens && $tokens->[$pos] eq ',') {
                    $pos++;
                }
            }
            if ($pos >= @$tokens) {
                $complete = 0;
            } else {
                $pos++; # skip '}'
            }
            return \%hash;
        }
        
        return $token; # leftover token, generally invalid
    };
    
    my $data;
    {
        local $@;
        $data = eval { $parse_value->() };
        if ($@) {
            return (undef, 0);
        }
    }

    # If extra tokens left after parsing one structure, extra text
    if (defined $data && $pos < @$tokens) {
        $complete = 0;
        $self->_reason("Found extra text outside JSON structure") unless $self->reason;
    }

    return ($data, $complete);
}

sub _parse_single ( $self, $json ) {
    # Reset state
    $self->_set_data(undef);
    $self->_set_success(0);
    $self->_set_valid(0);
    $self->_reason('');

    # Empty or whitespace only
    if ($json =~ /^\s*$/) {
        $self->_reason("No valid JSON structure found");
        return $self;
    }

    # Find first structure start
    my $start;
    if ($json =~ /([\{\[])/) {
        $start = $-[1];
    } else {
        $self->_reason("No valid JSON structure found");
        return $self;
    }

    # Extract from the start of the JSON structure
    my $extract = substr($json, $start);

    my $depth = 0;
    my $in_string = 0;
    my $escape = 0;
    my $end_pos = -1;
    my $first_char = substr($extract,0,1);
    $depth = 1 if $first_char eq '{' or $first_char eq '[';

    # Find matching end_pos for the structure
    for my $i (0..length($extract)-1) {
        my $c = substr($extract, $i, 1);
        if ($c eq '"' && !$escape) {
            $in_string = !$in_string;
        } elsif (!$in_string) {
            if ($c eq '{' or $c eq '[') {
                $depth++;
            } elsif ($c eq '}' or $c eq ']') {
                $depth--;
                if ($depth == 0) {
                    $end_pos = $i;
                    last;
                }
            }
        }
        $escape = (!$escape && $c eq '\\');
    }

    # If never closed properly, we just take what we have (incomplete)
    if ($end_pos == -1) {
        $end_pos = length($extract)-1;
    }

    my $main_json = substr($extract, 0, $end_pos+1);
    # Clean trailing commas
    $main_json =~ s/,(\s*[\]}])/$1/g;

    # Check for invalid characters outside strings (e.g., '=',';','\'')
    {
        my $check_str = 0;
        my $esc = 0;
        for (my $i=0; $i<length($main_json); $i++) {
            my $ch = substr($main_json, $i, 1);
            if ($ch eq '"' && !$esc) {
                $check_str = !$check_str;
            }
            $esc = (!$esc && $ch eq '\\');
            next if $check_str; # inside string, ignore checks
            
            if ($ch eq '=' || $ch eq ';' || $ch eq '\'') {
                $self->_reason("Failed to parse: Invalid JSON format");
                return $self;
            }
        }
    }

    my ($tokens, $last_string) = $self->_tokenize($main_json);
    unless (@$tokens) {
        $self->_reason("Failed to parse: No valid JSON structure found");
        return $self;
    }

    my ($data, $complete) = $self->_parse_tokens($tokens);

    if (!defined $data) {
        $self->_reason("Failed to parse: Invalid JSON structure") unless $self->reason;
        return $self;
    }

    # We have some data
    $self->_set_data($data);
    $self->_set_success(1);

    # If there's an unclosed string
    if ($last_string) {
        $self->_set_valid(0);
        $self->_reason("Unclosed string starting at \"$last_string");
        return $self;
    }

    # If not complete and no reason yet, it's incomplete
    if (!$complete && !$self->reason) {
        $self->_reason("Incomplete JSON structure");
    }

    # Determine extra text
    # $start + $end_pos = end of the JSON structure in the original $json$ string
    my $structure_end_index = $start + $end_pos;
    my $before = substr($json, 0, $start);
    my $after  = substr($json, $structure_end_index+1);

    if ($before =~ /\S/ || $after =~ /\S/) {
        $self->_set_valid(0);
        if (!$self->reason || $self->reason !~ /extra text/) {
            $self->_reason("Found extra text outside JSON structure");
        }
    } else {
        # If no errors so far
        $self->_set_valid(!$self->reason);
    }

    return $self;
}

1;
