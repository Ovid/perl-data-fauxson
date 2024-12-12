
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
    default => sub { '' },
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

sub _clean_json($self, $json) {
    # Handle trailing commas
    $json =~ s/,(\s*[\]}])/$1/g;
    
    # Quote unquoted keys
    $json =~ s/([{,]\s*)(\w+)\s*:/$1"$2":/g;
    
    # Convert single quotes to double quotes
    $json =~ s/'([^']*)'/"$1"/g;
    
    # Quote unquoted string values
    $json =~ s/:(\s*)(\w+)(\s*[,}])/:$1"$2"$3/g;
    
    # Handle boolean values
    $json =~ s/:\s*true\b/:1/g;
    $json =~ s/:\s*false\b/:0/g;
    
    return $json;
}

sub _parse_single ( $self, $json ) {
    # Reset state
    $self->_data('');
    $self->_success(0);
    $self->_valid(0);
    $self->_reason('');

    # Handle empty or whitespace-only input
    if ($json =~ /^\s*$/) {
        $self->_reason("No valid JSON structure found");
        return $self;
    }

    # Find the JSON-like structure
    my ($pre, $json_like, $post) = $json =~ /^(.*?)({[\s\S]*}|\[[\s\S]*\])(.*?)$/s;
    
    unless ($json_like) {
        $self->_reason("Failed to parse: No valid JSON structure found");
        return $self;
    }

    # Note if we had extra text
    if ($pre =~ /\S/ || $post =~ /\S/) {
        $self->_reason("Found extra text outside JSON structure");
    }

    # Clean up the JSON
    $json_like = $self->_clean_json($json_like);

    # Try to parse
    my $data;
    {
        local $@;
        eval {
            # Convert to Perl syntax
            my $perl = $json_like;
            $perl =~ s/:"([^"]+)"/:$1/g;    # Remove quotes from values
            $perl =~ s/:/=>/g;               # Convert : to =>
            $perl =~ s/"([^"]+)"(\s*=>)/$1$2/g;  # Remove quotes from keys
            $data = eval $perl;
        };
        if ($@) {
            $self->_reason("Failed to parse: $@");
            $self->_success(0);
            return $self;
        }
    }

    # Set success state
    $self->_data($data);
    $self->_success(1);
    
    # A JSON is valid if:
    # 1. It was parsed successfully
    # 2. Has no extra text before or after
    # 3. Has no trailing commas
    # 4. Has proper quote marks
    $self->_valid(
        $data &&                     # Successfully parsed
        !($pre =~ /\S/) &&          # No leading text
        !($post =~ /\S/) &&         # No trailing text
        $json_like !~ /,(\s*[\]}])/ # No trailing commas
    );
    
    return $self;
}

1;
