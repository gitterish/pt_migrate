use XML::Simple;
use Data::Dumper;

my $parser = XML::Simple->new();
my $doc = $parser->XMLin ("$ARGV[0]", ForceArray=>1);
print Dumper ($doc);

