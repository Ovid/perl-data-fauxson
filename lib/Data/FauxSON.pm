
package Data::FauxSON;
use Moo;
use experimental 'signatures';
use Carp 'croak';

has jsonl => (
    is      => 'ro',
    default => sub { 0 },
);

has _data => (
    is      => 'rw',
    default => sub { undef },
);

has _success => (
    is      => 'rw',
    default => sub { 0 },
);

has _valid => (
    is      => 'rw',
    default => sub { 0 },
);

has _reason => (
    is      => 'rw',
    default => sub { '' },
);

sub data($self)    { $self->_data }
sub success($self) { $self->_success }
sub valid($self)   { $self->_valid }
sub reason($self)  { $self->_reason }

sub parse ( $self, $json ) {
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

    $self->_data(\@data);
    $self->_success(@data > 0);
    $self->_valid($all_valid && @data > 0);
    $self->_reason(\@reasons);
    return $self;
}

sub _tokenize($self, $text) {
    my @tokens;
    my $pos = 0;
    my $len = length($text);
    
    while ($pos < $len) {
        my $char = substr($text, $pos, 1);
        
        # Skip whitespace
        if ($char =~ /\s/) {
            $pos++;
            next;
        }
        
        # Handle structural characters
        if ($char =~ /[{}\[\]:,]/) {
            push @tokens, $char;
            $pos++;
            next;
        }
        
        # Handle strings
        if ($char eq '"') {
            my $string = '';
            $pos++;  # Skip opening quote
            while ($pos < $len) {
                $char = substr($text, $pos, 1);
                last if $char eq '"' && substr($text, $pos-1, 1) ne '\\';
                $string .= $char;
                $pos++;
            }
            if ($pos < $len) {  # Found closing quote
                $pos++;  # Skip closing quote
            }
            push @tokens, ['STRING', $string];
            next;
        }
        
        # Handle numbers, true, false, and null
        if ($char =~ /[\d-]/ || substr($text, $pos, 4) eq 'true' || substr($text, $pos, 5) eq 'false') {
            my $value = '';
            while ($pos < $len && substr($text, $pos, 1) =~ /[\w.-]/) {
                $value .= substr($text, $pos, 1);
                $pos++;
            }
            push @tokens, ['VALUE', $value];
            next;
        }
        
        # Skip unknown characters
        $pos++;
    }
    
    return \@tokens;
}

sub _parse_tokens($self, $tokens) {
    my $pos = 0;
    my $truncated;
    my $extra_text;
    
    my $parse_value;
    $parse_value = sub {
        return undef if $pos >= @$tokens;
        
        my $token = $tokens->[$pos++];
        
        # Handle arrays
        if ($token eq '[') {
            my @array;
            while ($pos < @$tokens && $tokens->[$pos] ne ']') {
                my $value = $parse_value->();
                push @array, $value if defined $value;
                $pos++ if $pos < @$tokens && $tokens->[$pos] eq ',';
            }
            $pos++ if $pos < @$tokens && $tokens->[$pos] eq ']';
            return \@array;
        }
        
        # Handle objects
        if ($token eq '{') {
            my %hash;
            while ($pos < @$tokens && $tokens->[$pos] ne '}') {
                my $key = $tokens->[$pos];
                $pos += 2;  # Skip key and colon
                my $value = $parse_value->();
                if (ref $key eq 'ARRAY' && $key->[0] eq 'STRING') {
                    $hash{$key->[1]} = $value if defined $value;
                }
                $pos++ if $pos < @$tokens && $tokens->[$pos] eq ',';
            }
            $pos++ if $pos < @$tokens && $tokens->[$pos] eq '}';
            return \%hash;
        }
        
        # Handle literals
        if (ref $token eq 'ARRAY') {
            if ($token->[0] eq 'STRING') {
                return $token->[1];
            }
            if ($token->[0] eq 'VALUE') {
                return 0 if $token->[1] eq 'false';
                return 1 if $token->[1] eq 'true';
                return $token->[1] + 0;  # Convert to number
            }
        }
        
        return $token;
    };
    
    my $result = $parse_value->();
    
    # Check for extra text
    $extra_text = 1 if $pos < @$tokens;
    
    return ($result, $extra_text);
}

sub _parse_single ( $self, $json ) {
    # Reset state
    $self->_data(undef);
    $self->_success(0);
    $self->_valid(0);
    $self->_reason('');

    # Handle empty or whitespace-only input
    if ($json =~ /^\s*$/) {
        $self->_reason("No valid JSON structure found");
        return $self;
    }

    # Look for text outside JSON structure
    my ($pre, $json_struct, $post) = $json =~ /^(\s*)([\[{].*?[\]}])(\s*.*)$/s;
    if (!$json_struct) {
        # Try to find a partial structure
        ($pre, $json_struct) = $json =~ /^(\s*)([\[{].*)$/s;
    }
    
    unless ($json_struct) {
        $self->_reason("Failed to parse: No valid JSON structure found");
        return $self;
    }

    # Note extra text
    if (($pre && $pre =~ /\S/) || ($post && $post =~ /\S/)) {
        $self->_reason("Found extra text outside JSON structure");
    }

    # Tokenize and parse
    my $tokens = $self->_tokenize($json_struct);
    my ($data, $extra_text) = $self->_parse_tokens($tokens);
    
    if (defined $data) {
        $self->_data($data);
        $self->_success(1);
        $self->_valid(!$extra_text && !$self->reason);
    }

    return $self;
}

1;
