use JSON;

my $input = {};
$input->{item} = {};
$input->{item}->{name} = "TestName2";
$input->{item}->{description} = "TestDesc2";
$input->{item}->{assigned_to}->{id} = 100;
$input->{item}->{project}->{id} = 11;
print encode_json($input);



